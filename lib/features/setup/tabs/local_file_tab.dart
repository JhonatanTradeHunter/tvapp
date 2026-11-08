import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/models/playlist_source.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/features/setup/import_progress.dart';
import 'package:tvapp/features/setup/setup_screen.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

class LocalFileTab extends ConsumerStatefulWidget {
  const LocalFileTab({super.key});

  @override
  ConsumerState<LocalFileTab> createState() => _LocalFileTabState();
}

class _LocalFileTabState extends ConsumerState<LocalFileTab> {
  String? _name;
  String? _storedPath;
  bool _copying = false;
  bool _copyFailed = false;

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (!mounted || file == null) return;
    setState(() {
      _name = file.name;
      _storedPath = null;
      _copying = true;
      _copyFailed = false;
    });
    try {
      final stored = await ref
          .read(sourceRepositoryProvider)
          .persistPickedFile(file.name, file.readAsByteStream());
      if (!mounted) return;
      setState(() {
        _storedPath = stored;
        _copying = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _copying = false;
        _copyFailed = true;
      });
    }
  }

  PlaylistSource? _buildSource() {
    final path = _storedPath;
    if (path == null) return null;
    return PlaylistSource(
      name: _name ?? p.basename(path),
      kind: SourceKind.localFile,
      location: path,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final name = _name;
    final ready = _storedPath != null;
    return SetupTabFrame(
      children: [
        AppButton(
          label: l.pickFile,
          icon: Icons.folder_open,
          autofocus: true,
          primary: !ready,
          onPressed: _copying ? null : _pick,
        ),
        const SizedBox(height: 12),
        Text(name == null ? l.noFileSelected : l.selectedFile(name)),
        if (_copying) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_copyFailed) ...[
          const SizedBox(height: 12),
          Text(
            l.srcErrNotFound,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        if (ready) SetupActionBar(buildSource: _buildSource),
      ],
    );
  }
}
