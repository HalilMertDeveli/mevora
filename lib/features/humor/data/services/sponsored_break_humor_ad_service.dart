import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/humor/domain/config/humor_ads_settings.dart';
import 'package:mevora/features/humor/domain/services/humor_ad_service.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Mevora-hosted sponsored break (not a third-party SDK).
/// Continue is enabled only after [HumorAdsSettings.minWatchSeconds].
/// This is our own format — not a fake wrapper over a skippable AdMob unit.
class SponsoredBreakHumorAdService implements HumorAdService {
  SponsoredBreakHumorAdService({
    this.settings = HumorAdsSettings.defaults,
  });

  final HumorAdsSettings settings;

  @override
  bool get isAvailable => true;

  @override
  Future<HumorAdResult> show(
    HumorAdRequest request, {
    BuildContext? hostContext,
  }) async {
    if (request.isPremium) {
      return HumorAdResult.completedOk;
    }
    final context = hostContext;
    if (context == null || !context.mounted) {
      return HumorAdResult.failedSoft;
    }
    try {
      final completed = await Navigator.of(context, rootNavigator: true).push<bool>(
        PageRouteBuilder<bool>(
          opaque: true,
          barrierDismissible: false,
          pageBuilder: (context, animation, secondaryAnimation) {
            return _SponsoredBreakPage(
              minWatchSeconds: settings.minWatchSeconds,
            );
          },
        ),
      );
      if (completed == true) {
        return HumorAdResult.completedOk;
      }
      return HumorAdResult.failedSoft;
    } catch (_) {
      return HumorAdResult.failedSoft;
    }
  }
}

class _SponsoredBreakPage extends StatefulWidget {
  const _SponsoredBreakPage({required this.minWatchSeconds});

  final int minWatchSeconds;

  @override
  State<_SponsoredBreakPage> createState() => _SponsoredBreakPageState();
}

class _SponsoredBreakPageState extends State<_SponsoredBreakPage> {
  late int _remaining;
  Timer? _timer;
  var _canContinue = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.minWatchSeconds.clamp(1, 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remaining <= 1) {
        timer.cancel();
        setState(() {
          _remaining = 0;
          _canContinue = true;
        });
        return;
      }
      setState(() => _remaining -= 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: theme.colorScheme.scrim,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.humorAdSponsoredLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onInverseSurface,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.campaign_outlined,
                  size: 72,
                  color: theme.colorScheme.onInverseSurface,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l10n.humorAdPreparing,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onInverseSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  _canContinue
                      ? l10n.humorAdCompleted
                      : l10n.humorAdCountdown(_remaining),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onInverseSurface
                        .withValues(alpha: 0.85),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _canContinue
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                      ),
                    ),
                    child: Text(l10n.humorAdContinue),
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
