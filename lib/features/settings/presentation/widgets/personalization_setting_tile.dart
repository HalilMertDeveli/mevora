import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/di/settings_services_factory.dart';
import 'package:mevora/features/settings/domain/entities/user_settings.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// "Personalize my recommendations based on my interactions".
///
/// Stored as `userSettings/{uid}.personalizeRecommendations`. The server reads
/// it before learning from an interaction and before ranking: OFF means
/// nothing new is learned and recommendations ignore what was learned before.
class PersonalizationSettingTile extends StatefulWidget {
  const PersonalizationSettingTile({super.key});

  @override
  State<PersonalizationSettingTile> createState() =>
      _PersonalizationSettingTileState();
}

class _PersonalizationSettingTileState
    extends State<PersonalizationSettingTile> {
  SettingsServices? _services;
  String? _uid;
  Stream<UserSettings>? _stream;
  UserSettings? _latest;

  /// Optimistic value while a save is in flight, so the switch does not
  /// bounce back before the snapshot catches up.
  bool? _pending;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = AuthScope.maybeOf(context)?.user?.id;
    final services = SettingsScope.maybeOf(context);
    if (uid == _uid && services == _services) {
      return;
    }
    _uid = uid;
    _services = services;
    _latest = null;
    _stream = uid == null || services == null
        ? null
        : services.settingsHub.watchSettings(uid);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final services = _services;
    final stream = _stream;
    if (services == null || stream == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<UserSettings>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.data != null) {
          _latest = snapshot.data;
        }
        final settings = _latest;
        final value = _pending ?? settings?.personalizeRecommendations ?? true;
        return SwitchListTile(
          key: const Key('personalizeRecommendationsSwitch'),
          title: Text(l10n.settingsPersonalizeRecommendations),
          subtitle: Text(l10n.settingsPersonalizeRecommendationsSubtitle),
          isThreeLine: true,
          value: value,
          onChanged: settings == null
              ? null
              : (next) => unawaited(_save(services, settings, next)),
        );
      },
    );
  }

  Future<void> _save(
    SettingsServices services,
    UserSettings settings,
    bool value,
  ) async {
    setState(() => _pending = value);
    try {
      await services.settingsHub.saveSettings(
        settings.copyWith(personalizeRecommendations: value),
      );
    } finally {
      if (mounted) {
        setState(() => _pending = null);
      }
    }
  }
}
