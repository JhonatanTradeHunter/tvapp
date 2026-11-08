import 'package:flutter/material.dart';
import 'package:tvapp/core/models/playlist_source.dart';
import 'package:tvapp/core/ui/focus/tv_shortcuts.dart';
import 'package:tvapp/features/setup/import_progress.dart';
import 'package:tvapp/features/setup/setup_screen.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

class UrlTab extends StatefulWidget {
  const UrlTab({super.key});

  @override
  State<UrlTab> createState() => _UrlTabState();
}

class _UrlTabState extends State<UrlTab> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _url = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  static bool isValidPlaylistUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  PlaylistSource? _buildSource() {
    final form = _form.currentState;
    if (form == null || !form.validate()) return null;
    final url = _url.text.trim();
    final name = _name.text.trim();
    return PlaylistSource(
      name: name.isEmpty ? Uri.parse(url).host : name,
      kind: SourceKind.url,
      location: url,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SetupTabFrame(
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              DpadFieldGuard(
                child: TextFormField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l.fieldUrl,
                    hintText: 'https://exemplo.com/lista.m3u',
                  ),
                  validator: (v) => v == null || !isValidPlaylistUrl(v)
                      ? l.validationUrl
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              DpadFieldGuard(
                child: TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(labelText: l.fieldName),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SetupActionBar(buildSource: _buildSource),
      ],
    );
  }
}
