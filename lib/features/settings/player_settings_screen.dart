import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/player/engine_capabilities.dart';
import 'package:tvapp/core/player/engine_selector.dart';
import 'package:tvapp/core/player/playback_controller.dart';
import 'package:tvapp/core/player/playback_engine.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

String engineLabel(EngineKind kind, AppLocalizations l) {
  switch (kind) {
    case EngineKind.exoPlayer:
      return l.engineExoPlayer;
    case EngineKind.avPlayer:
      return l.engineAvPlayer;
    case EngineKind.mpv:
      return l.engineMpv;
    case EngineKind.web:
      return l.engineWeb;
  }
}

String _capabilitiesText(EngineCapabilities caps, AppLocalizations l) {
  final parts = <String>[
    if (caps.supportsRawTs) l.capRawTs,
    if (caps.supportsTrackSelection) l.capTracks,
    if (caps.supportsAudioDelay) l.capAudioDelay,
    if (caps.supportsBufferTuning) l.capBuffer,
  ];
  return parts.isEmpty ? l.capBasic : parts.join(' · ');
}

/// Motor de vídeo preferido e tamanho do buffer. A preferência só muda a
/// ordem de tentativa: se o motor escolhido falhar, o app tenta o próximo.
class PlayerSettingsScreen extends ConsumerStatefulWidget {
  const PlayerSettingsScreen({super.key});

  @override
  ConsumerState<PlayerSettingsScreen> createState() =>
      _PlayerSettingsScreenState();
}

class _PlayerSettingsScreenState extends ConsumerState<PlayerSettingsScreen> {
  late EngineKind? _engine = ref.read(appPrefsProvider).preferredEngine;
  late BufferProfile _buffer = ref.read(appPrefsProvider).bufferProfile;

  void _setEngine(EngineKind? kind) {
    setState(() => _engine = kind);
    ref.read(appPrefsProvider).setPreferredEngine(kind);
  }

  void _setBuffer(BufferProfile profile) {
    setState(() => _buffer = profile);
    ref.read(appPrefsProvider).setBufferProfile(profile);
  }

  String _bufferLabel(BufferProfile p, AppLocalizations l) {
    switch (p) {
      case BufferProfile.compact:
        return l.bufferCompact;
      case BufferProfile.normal:
        return l.bufferNormal;
      case BufferProfile.large:
        return l.bufferLarge;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selector = ref.watch(engineSelectorProvider);
    final engines = <EngineDescriptor>[
      for (final d in selector.descriptors)
        if (d.isAvailable) d,
    ];
    final tunable = engines.any((d) => d.capabilities.supportsBufferTuning);

    return Scaffold(
      appBar: AppBar(title: Text(l.playerSettings)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: FocusTraversalGroup(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _Section(text: l.engineTitle),
                  Text(l.engineHint, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  _OptionRow(
                    label: l.engineAuto(
                      engineLabel(selector.platformDefault, l),
                    ),
                    selected:
                        _engine == null || !selector.isAvailable(_engine!),
                    autofocus: true,
                    onSelect: () => _setEngine(null),
                  ),
                  for (final d in engines)
                    _OptionRow(
                      label: engineLabel(d.kind, l),
                      detail: _capabilitiesText(d.capabilities, l),
                      selected: _engine == d.kind,
                      onSelect: () => _setEngine(d.kind),
                    ),
                  if (tunable) ...[
                    const SizedBox(height: 24),
                    _Section(text: l.bufferTitle),
                    Text(l.bufferHint, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    for (final p in BufferProfile.values)
                      _OptionRow(
                        label: _bufferLabel(p, l),
                        detail: l.bufferDetail(p.seconds, p.megabytes),
                        selected: _buffer == p,
                        onSelect: () => _setBuffer(p),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.selected,
    required this.onSelect,
    this.detail,
    this.autofocus = false,
  });

  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = detail;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: FocusableScale(
          onSelect: onSelect,
          autofocus: autofocus,
          semanticLabel: text == null ? label : '$label. $text',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: selected
                  ? theme.colorScheme.secondaryContainer
                  : theme.colorScheme.surfaceContainerHigh,
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.titleMedium),
                      if (text != null)
                        Text(text, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
