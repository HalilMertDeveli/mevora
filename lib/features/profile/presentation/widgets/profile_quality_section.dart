import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/music_scope.dart';
import 'package:mevora/core/di/relationship_scope.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/services/profile_quality_calculator.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_quality_card.dart';

/// Loads live profile + answer + Spotify signals for Profile Quality UX.
class ProfileQualitySection extends StatefulWidget {
  const ProfileQualitySection({
    super.key,
    this.compact = false,
    this.boostHint = false,
  });

  final bool compact;
  final bool boostHint;

  @override
  State<ProfileQualitySection> createState() => _ProfileQualitySectionState();
}

class _ProfileQualitySectionState extends State<ProfileQualitySection> {
  StreamSubscription<UserProfile?>? _profileSub;
  String? _uid;
  UserProfile? _profile;
  int _answerCount = 0;
  bool _spotifyConnected = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = AuthScope.maybeOf(context)?.user?.id;
    if (uid == null || uid == _uid) {
      return;
    }
    _uid = uid;
    unawaited(_profileSub?.cancel());
    final settings = SettingsScope.maybeOf(context);
    if (settings != null) {
      _profileSub = settings.settingsHub.watchProfile(uid).listen((profile) {
        if (!mounted) {
          return;
        }
        setState(() => _profile = profile);
      });
    }
    unawaited(_loadExtras());
  }

  Future<void> _loadExtras() async {
    final relationship = RelationshipScope.maybeOf(context);
    final music = MusicScope.maybeOf(context);
    final profileAnswers = RelationshipScope.profileAnswersOf(context);
    final uid = _uid;
    var answers = 0;
    var spotify = false;
    if (relationship != null) {
      final result = await relationship.getAnswered();
      if (result case Success(:final value)) {
        answers = value.answerCount;
      }
    }
    if (music != null) {
      final result = await music.getProfile();
      if (result case Success(:final value)) {
        spotify = value.connected;
      }
    }
    if (answers == 0 && profileAnswers != null && uid != null) {
      try {
        final list = await profileAnswers
            .watchAnswers(uid)
            .first
            .timeout(const Duration(seconds: 3));
        answers = list.length;
      } catch (_) {
        // Keep zero — quality still floors.
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _answerCount = answers;
      _spotifyConnected = spotify;
    });
  }

  @override
  void dispose() {
    unawaited(_profileSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    if (profile == null) {
      return const SizedBox.shrink();
    }
    final result = ProfileQualityCalculator.calculate(
      profile: profile,
      personalityAnswerCount: _answerCount,
      spotifyConnected: _spotifyConnected,
    );
    if (widget.boostHint) {
      return ProfileQualityBoostHint(result: result);
    }
    return ProfileQualityCard(result: result, compact: widget.compact);
  }
}
