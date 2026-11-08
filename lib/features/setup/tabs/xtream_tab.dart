import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tvapp/core/models/playlist_source.dart';
import 'package:tvapp/core/ui/focus/tv_shortcuts.dart';
import 'package:tvapp/features/setup/import_progress.dart';
import 'package:tvapp/features/setup/setup_screen.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

/// Na fase 1 a importação usa `get.php?type=m3u_plus`, o mesmo parser
/// das listas M3U. O `player_api.php` entra na fase 3.
class XtreamTab extends StatefulWidget {
  const XtreamTab({super.key});

  @override
  State<XtreamTab> createState() => _XtreamTabState();
}

class _XtreamTabState extends State<XtreamTab> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _host = TextEditingController();
  final TextEditingController _port = TextEditingController();
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  PlaylistSource? _buildSource() {
    final form = _form.currentState;
    if (form == null || !form.validate()) return null;
    final portText = _port.text.trim();
    final creds = XtreamCredentials(
      host: _host.text.trim(),
      port: portText.isEmpty ? null : int.parse(portText),
      username: _user.text.trim(),
      password: _pass.text,
    );
    final uri = creds.m3uUri();
    return PlaylistSource(
      name: uri.host,
      kind: SourceKind.xtream,
      location: uri.toString(),
      xtream: creds,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    String? requiredField(String? v) =>
        v == null || v.trim().isEmpty ? l.validationRequired : null;

    return SetupTabFrame(
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              DpadFieldGuard(
                child: TextFormField(
                  controller: _host,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l.fieldHost,
                    hintText: 'http://servidor.exemplo',
                  ),
                  validator: (v) =>
                      XtreamCredentials.tryParseHost(v ?? '') == null
                      ? l.validationHost
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              DpadFieldGuard(
                child: TextFormField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: l.fieldPort),
                  validator: (v) {
                    final text = (v ?? '').trim();
                    if (text.isEmpty) return null;
                    final port = int.tryParse(text);
                    return port == null || port < 1 || port > 65535
                        ? l.validationPort
                        : null;
                  },
                ),
              ),
              const SizedBox(height: 16),
              DpadFieldGuard(
                child: TextFormField(
                  controller: _user,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: InputDecoration(labelText: l.fieldUser),
                  validator: requiredField,
                ),
              ),
              const SizedBox(height: 16),
              DpadFieldGuard(
                child: TextFormField(
                  controller: _pass,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: l.fieldPassword,
                    suffixIcon: IconButton(
                      tooltip: _obscure ? l.showPassword : l.hidePassword,
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: requiredField,
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
