import 'package:flutter/material.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_signal.dart';
import 'package:mevora/shared/art/mevora_mark.dart';
import 'package:mevora/shared/art/mevora_motion.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:mevora/shared/widgets/mevora_widgets.dart';

/// The living style guide (debug route `/debug/design-system`).
///
/// Every token and component in one scroll, rendered by the real theme — the
/// quickest way to check a change to the design system on a device.
class DesignSystemPage extends StatefulWidget {
  const DesignSystemPage({super.key, required this.config});

  final AppConfig config;

  @override
  State<DesignSystemPage> createState() => _DesignSystemPageState();
}

class _DesignSystemPageState extends State<DesignSystemPage> {
  bool _travelSelected = true;
  bool _fitnessSelected = false;
  bool _switch = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final scheme = theme.colorScheme;

    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.xl,
        bottom: AppSpacing.s12,
      ),
      child: MevoraSectionHeader(title: title),
    );

    Widget swatch(String name, Color color, [Color? on]) => Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: p.border),
          ),
          alignment: Alignment.center,
          child: on == null
              ? null
              : Text(
                  'Aa',
                  style: theme.textTheme.labelLarge?.copyWith(color: on),
                ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          width: 64,
          child: Text(
            name,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall,
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text('${widget.config.appName} · Design system')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          AppSpacing.sm,
          AppSpacing.screenPadding,
          AppSpacing.xxl,
        ),
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: MevoraLogo(size: 40, axis: Axis.horizontal),
          ),
          section('Colour'),
          Wrap(
            spacing: AppSpacing.s12,
            runSpacing: AppSpacing.s12,
            children: [
              swatch('primary', scheme.primary, scheme.onPrimary),
              swatch('ink', p.textPrimary, p.background),
              swatch('background', p.background, p.textPrimary),
              swatch('surface', p.surface, p.textPrimary),
              swatch('muted', p.surfaceMuted, p.textPrimary),
              swatch('compat', p.compatibility, AppColors.paper),
              swatch('music', p.music, AppColors.paper),
              swatch('humor', p.humor, AppColors.paper),
              swatch('match', p.match, AppColors.paper),
              swatch('premium', p.premium, p.premiumSurface),
              swatch('success', p.success, AppColors.paper),
              swatch('error', p.error, AppColors.paper),
            ],
          ),
          section('Type'),
          Text('Display', style: theme.textTheme.displaySmall),
          Text('Headline large', style: theme.textTheme.headlineLarge),
          Text('Headline small', style: theme.textTheme.headlineSmall),
          Text('Title large', style: theme.textTheme.titleLarge),
          Text('Title medium', style: theme.textTheme.titleMedium),
          Text(
            'Body large — Ağır ğ, ş, İ ve ı harfleri',
            style: theme.textTheme.bodyLarge,
          ),
          Text(
            'Body medium — supporting text',
            style: theme.textTheme.bodyMedium,
          ),
          Text('Body small — captions', style: theme.textTheme.bodySmall),
          Text('LABEL SMALL', style: theme.textTheme.labelSmall),
          section('Buttons'),
          MevoraButton(label: 'Primary', onPressed: () {}),
          const SizedBox(height: AppSpacing.sm),
          MevoraButton(
            label: 'Secondary',
            variant: MevoraButtonVariant.secondary,
            onPressed: () {},
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: MevoraButton(
                  label: 'Tonal',
                  variant: MevoraButtonVariant.tonal,
                  onPressed: () {},
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: MevoraButton(
                  label: 'Ghost',
                  variant: MevoraButtonVariant.ghost,
                  onPressed: () {},
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const MevoraButton(label: 'Disabled'),
          const SizedBox(height: AppSpacing.sm),
          MevoraButton(
            label: 'Delete account',
            variant: MevoraButtonVariant.destructive,
            onPressed: () {},
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              MevoraIconButton(
                icon: MevoraIcons.filters,
                tooltip: 'Plain',
                onPressed: () {},
              ),
              MevoraIconButton(
                icon: MevoraIcons.edit,
                tooltip: 'Tonal',
                variant: MevoraIconButtonVariant.tonal,
                onPressed: () {},
              ),
              MevoraIconButton(
                icon: MevoraIcons.more,
                tooltip: 'Surface',
                variant: MevoraIconButtonVariant.surface,
                onPressed: () {},
              ),
              MevoraIconButton(
                icon: MevoraIcons.liked,
                tooltip: 'Primary',
                variant: MevoraIconButtonVariant.primary,
                onPressed: () {},
              ),
            ],
          ),
          section('Chips, pills, badges'),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              MevoraChip(
                label: 'Travel',
                selected: _travelSelected,
                avatar: const Icon(MevoraIcons.travel),
                onSelected: (v) => setState(() => _travelSelected = v),
              ),
              MevoraChip(
                label: 'Fitness',
                selected: _fitnessSelected,
                avatar: const Icon(MevoraIcons.fitness),
                onSelected: (v) => setState(() => _fitnessSelected = v),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          const Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              MevoraPill(label: 'Istanbul', icon: MevoraIcons.location),
              MevoraPill(
                label: 'Verified',
                icon: MevoraIcons.verified,
                tone: MevoraTone.compatibility,
              ),
              MevoraPill(
                label: 'Music · 82',
                icon: MevoraIcons.track,
                tone: MevoraTone.music,
              ),
              MevoraPill(
                label: 'Humor',
                icon: MevoraIcons.humor,
                tone: MevoraTone.humor,
              ),
              MevoraPill(
                label: 'Premium',
                icon: MevoraIcons.premium,
                tone: MevoraTone.premium,
              ),
              MevoraCountBadge(count: 3),
            ],
          ),
          section('Compatibility'),
          const Row(
            children: [
              CompatibilityRing(score: 84, size: 64),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: CompatibilitySignalPills(
                  signals: [
                    (kind: CompatibilitySignalKind.relationship, score: 88),
                    (kind: CompatibilitySignalKind.music, score: 76),
                    (kind: CompatibilitySignalKind.lifestyle, score: 64),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const CompatibilitySignalBar(
            signal: (kind: CompatibilitySignalKind.questions, score: 71),
          ),
          section('Surfaces'),
          const MevoraCard(child: Text('Standard card')),
          const SizedBox(height: AppSpacing.sm),
          const MevoraCard(
            emphasis: MevoraCardEmphasis.quiet,
            child: Text('Quiet card'),
          ),
          const SizedBox(height: AppSpacing.sm),
          const MevoraCard(
            emphasis: MevoraCardEmphasis.elevated,
            child: Text('Elevated card'),
          ),
          const SizedBox(height: AppSpacing.md),
          const MevoraBanner(
            title: 'Heads up',
            message: 'An inline message stays until its state changes.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const MevoraBanner(
            message: 'Something could not be saved.',
            tone: MevoraTone.error,
          ),
          const SizedBox(height: AppSpacing.md),
          MevoraListGroup(
            title: 'List group',
            children: [
              MevoraListRow(
                title: 'Row with glyph',
                subtitle: 'Supporting line',
                icon: MevoraIcons.notifications,
                onTap: () {},
              ),
              MevoraSwitchRow(
                title: 'Switch row',
                icon: MevoraIcons.privacy,
                value: _switch,
                onChanged: (v) => setState(() => _switch = v),
              ),
              MevoraListRow(
                title: 'Destructive',
                icon: MevoraIcons.delete,
                destructive: true,
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const MevoraMeter(value: 0.62),
          section('Motion & art'),
          const Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MevoraOrbitLoader(),
              MevoraSuccessMark(size: 64),
              MevoraBoostBurst(size: 64),
              MevoraMarkIntro(size: 56),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final art in MevoraArt.values)
                MevoraSpot(art: art, size: 56),
            ],
          ),
          section('States'),
          const MevoraCard(
            emphasis: MevoraCardEmphasis.quiet,
            child: MevoraEmptyState(
              art: MevoraArt.emptyMatches,
              compact: true,
              title: 'No matches yet',
              message: 'When someone likes you back, they will appear here.',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const MevoraAvatar(name: 'Deniz Kaya', isVerified: true),
              const SizedBox(width: AppSpacing.md),
              const MevoraAvatar(name: 'Ece', showOnlineIndicator: true),
              const Spacer(),
              MevoraButton(
                label: 'Dialog',
                isExpanded: false,
                variant: MevoraButtonVariant.secondary,
                onPressed: () => MevoraDialog.show(
                  context,
                  title: 'Remove this photo?',
                  message: 'It will disappear from your profile.',
                  confirmVariant: MevoraButtonVariant.destructive,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
