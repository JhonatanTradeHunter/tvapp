import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/db/daos/profile_dao.dart';
import 'package:tvapp/core/data/profiles/profile_providers.dart';
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/models/channel_group.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/core/ui/focus/tv_shortcuts.dart';
import 'package:tvapp/features/profiles/pin_pad.dart';
import 'package:tvapp/features/profiles/profile_picker_screen.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

/// Grupos sem o filtro do perfil ativo: quem edita precisa ver todos.
final _rawGroupsProvider = StreamProvider.autoDispose
    .family<List<ChannelGroup>, BlockedKind>((ref, kind) {
      final key = ref.watch(activeListingKeyProvider);
      if (key == null) return Stream.value(const <ChannelGroup>[]);
      final db = ref.watch(databaseProvider);
      switch (kind) {
        case BlockedKind.live:
          return db.channelDao.watchGroups(key.$1, key.$2);
        case BlockedKind.vod:
          return db.vodDao.watchVodCategories(key.$1, key.$2);
        case BlockedKind.series:
          return db.vodDao.watchSeriesCategories(key.$1, key.$2);
      }
    });

const List<int?> _ageOptions = <int?>[0, 10, 12, 14, 16, null];

/// Cria ([profileId] nulo) ou edita um perfil: nome, cor, infantil com
/// idade máxima, PIN e grupos escondidos por tipo.
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key, this.profileId});

  final int? profileId;

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final TextEditingController _name = TextEditingController();
  int _color = 0;
  bool _kids = false;
  int? _maxAge = 12;
  String? _newPin;
  bool _removePin = false;
  bool _loaded = false;
  final Map<BlockedKind, Set<String>> _blocked = <BlockedKind, Set<String>>{
    for (final k in BlockedKind.values) k: <String>{},
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.profileId;
    if (id == null) {
      setState(() => _loaded = true);
      return;
    }
    final dao = ref.read(databaseProvider).profileDao;
    final profile = await dao.byId(id);
    final blocked = <BlockedKind, Set<String>>{
      for (final k in BlockedKind.values)
        k: await dao.watchBlocked(id, k).first,
    };
    if (!mounted || profile == null) return;
    setState(() {
      _name.text = profile.name;
      _color = profile.colorIndex;
      _kids = profile.isKids;
      _maxAge = profile.isKids ? profile.maxAge : 12;
      _blocked.addAll(blocked);
      _loaded = true;
    });
  }

  ProfileRow? get _existing {
    final id = widget.profileId;
    if (id == null) return null;
    for (final p
        in ref.read(profilesProvider).valueOrNull ?? const <ProfileRow>[]) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> _definePin() async {
    final l = AppLocalizations.of(context);
    final first = await showPinPad(context, title: l.pinNewTitle);
    if (first == null || !mounted) return;
    final confirm = await showPinPad(
      context,
      title: l.pinConfirmTitle,
      validate: (value) => value == first,
      errorText: l.pinMismatch,
    );
    if (confirm == null || !mounted) return;
    setState(() {
      _newPin = confirm;
      _removePin = false;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final dao = ref.read(databaseProvider).profileDao;
    var id = widget.profileId;
    if (id == null) {
      id = await dao.createProfile(
        name: name,
        colorIndex: _color,
        isKids: _kids,
        maxAge: _maxAge,
        pin: _newPin,
      );
    } else {
      await dao.updateProfile(
        id,
        name: name,
        colorIndex: _color,
        isKids: _kids,
        maxAge: _maxAge,
      );
      if (_newPin != null) await dao.setPin(id, _newPin);
      if (_removePin) await dao.setPin(id, null);
    }
    for (final kind in BlockedKind.values) {
      await dao.setBlocked(id, kind, _blocked[kind]!);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final id = widget.profileId;
    if (id == null) return;
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.deleteProfile),
        content: Text(l.deleteProfileConfirm(_name.text.trim())),
        actions: [
          AppButton(
            label: l.cancel,
            primary: false,
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: l.deleteProfile,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(databaseProvider).profileDao.deleteProfile(id);
    final active = ref.read(activeProfileIdProvider);
    if (active == id) ref.read(activeProfileIdProvider.notifier).signOut();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final existing = _existing;
    final hasPin =
        !_removePin &&
        (_newPin != null || (existing != null && profileHasPin(existing)));
    final profiles =
        ref.watch(profilesProvider).valueOrNull ?? const <ProfileRow>[];
    final canDelete = existing != null && profiles.length > 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profileId == null ? l.addProfile : l.editProfile),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DpadFieldGuard(
                    child: TextField(
                      controller: _name,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(labelText: l.profileName),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    children: [
                      for (var i = 0; i < profileColors.length; i++)
                        FocusableScale(
                          onSelect: () => setState(() => _color = i),
                          borderRadius: const BorderRadius.all(
                            Radius.circular(24),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: profileColors[i],
                              child: i == _color
                                  ? const Icon(Icons.check, color: Colors.white)
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _Toggle(
                    label: l.profileKids,
                    hint: l.profileKidsHint,
                    value: _kids,
                    onChanged: (v) => setState(() => _kids = v),
                  ),
                  if (_kids) ...[
                    const SizedBox(height: 12),
                    Text(l.maxAgeLabel, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final age in _ageOptions)
                          _Choice(
                            label: age == null
                                ? l.ageNoLimit
                                : age == 0
                                ? l.ageFree
                                : l.ageYears(age),
                            selected: _maxAge == age,
                            onSelect: () => setState(() => _maxAge = age),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(l.pinLabel, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      AppButton(
                        label: hasPin ? l.pinChange : l.pinSet,
                        icon: Icons.lock_outline,
                        primary: false,
                        onPressed: _definePin,
                      ),
                      if (hasPin)
                        AppButton(
                          label: l.pinRemove,
                          icon: Icons.lock_open,
                          primary: false,
                          onPressed: () => setState(() {
                            _newPin = null;
                            _removePin = true;
                          }),
                        ),
                    ],
                  ),
                  for (final kind in BlockedKind.values) ...[
                    const SizedBox(height: 24),
                    _BlockedGroups(
                      kind: kind,
                      selected: _blocked[kind]!,
                      onToggle: (group) => setState(() {
                        final set = _blocked[kind]!;
                        if (!set.remove(group)) set.add(group);
                      }),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      AppButton(
                        label: l.save,
                        icon: Icons.check,
                        onPressed: _save,
                      ),
                      if (canDelete)
                        AppButton(
                          label: l.deleteProfile,
                          icon: Icons.delete_outline,
                          primary: false,
                          onPressed: _delete,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BlockedGroups extends ConsumerWidget {
  const _BlockedGroups({
    required this.kind,
    required this.selected,
    required this.onToggle,
  });

  final BlockedKind kind;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final groups =
        ref.watch(_rawGroupsProvider(kind)).valueOrNull ??
        const <ChannelGroup>[];
    if (groups.isEmpty && kind != BlockedKind.live) {
      return const SizedBox.shrink();
    }
    final title = switch (kind) {
      BlockedKind.live => l.blockedGroupsLive,
      BlockedKind.vod => l.blockedGroupsVod,
      BlockedKind.series => l.blockedGroupsSeries,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (groups.isEmpty)
          Text(l.noGroups, style: theme.textTheme.bodySmall)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in groups)
                _Choice(
                  label: g.name.isEmpty ? l.ungrouped : g.name,
                  selected: selected.contains(g.name),
                  icon: Icons.visibility_off_outlined,
                  onSelect: () => onToggle(g.name),
                ),
            ],
          ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusableScale(
      onSelect: () => onChanged(!value),
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.titleMedium),
                  Text(hint, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            ExcludeFocus(
              child: Switch(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onSelect,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const radius = BorderRadius.all(Radius.circular(18));
    final mark = icon;
    return FocusableScale(
      onSelect: onSelect,
      borderRadius: radius,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: radius,
          color: selected
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.surfaceContainerHigh,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected && mark != null) ...[
              Icon(mark, size: 16),
              const SizedBox(width: 6),
            ],
            Text(label, style: theme.textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}
