import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/boost/domain/entities/smart_boost_preview.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';

/// Loads real eligible-active counts from [getSmartBoostPreview].
/// Never invents numbers — hides stats when the call fails.
class SmartBoostPreviewCard extends StatefulWidget {
  const SmartBoostPreviewCard({super.key, this.backend});

  final BackendCallable? backend;

  @override
  State<SmartBoostPreviewCard> createState() => _SmartBoostPreviewCardState();
}

class _SmartBoostPreviewCardState extends State<SmartBoostPreviewCard> {
  SmartBoostPreview? _preview;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final backend = widget.backend ?? FirebaseFunctionsCallable();
      final raw = await backend.invoke('getSmartBoostPreview');
      if (!mounted) {
        return;
      }
      setState(() {
        _preview = SmartBoostPreview.fromMap(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
        _loading = false;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _preview = null;
        _loading = false;
      });
    }
  }

  String _suggestionLabel(String key) {
    return switch (key) {
      'add_bio' => 'Add a bio',
      'add_location' => 'Add your location',
      'select_relationship_goal' => 'Select a relationship goal',
      'complete_personality_test' => 'Complete the personality test',
      final s when s.startsWith('add_') && s.endsWith('_photos') =>
        'Add more photos',
      _ => key.replaceAll('_', ' '),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final preview = _preview;
    return MevoraCard(
      emphasis: MevoraCardEmphasis.elevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '🚀 Smart Boost',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Not more random people — more people who actually fit you.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          if (preview != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Şu anda sana uygun ${preview.suitableActiveCount} aktif kişi var.',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${preview.durationMinutes} dakika boyunca profilini sana uygun '
              'adayların önünde daha görünür yap.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (preview.lowTraffic) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Şu anda daha az uygun aday aktif. Daha iyi sonuç için '
                'biraz sonra tekrar deneyebilirsin.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(
              'Profile Quality ${preview.profileQualityScore}%',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            if (preview.suggestions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                "Boost'tan daha iyi sonuç almak için profilini tamamla.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              ...preview.suggestions.take(3).map(
                (s) => Text(
                  '• ${_suggestionLabel(s)}',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
