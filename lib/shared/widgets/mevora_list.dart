import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/locale_casing.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// A titled group of [MevoraListRow]s on one white surface, separated by
/// inset hairlines — the building block of Profile, Settings and Privacy.
class MevoraListGroup extends StatelessWidget {
  const MevoraListGroup({
    super.key,
    required this.children,
    this.title,
    this.footer,
  });

  final String? title;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Divider(
            height: 1,
            indent: AppSpacing.md,
            endIndent: AppSpacing.md,
            color: p.divider,
          ),
        );
      }
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              0,
              AppSpacing.xs,
              AppSpacing.sm,
            ),
            child: Semantics(
              header: true,
              child: Text(
                // Turkish uppercases i to İ; the default mapping would not.
                LocaleCasing.upper(title!, Localizations.localeOf(context)),
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.4,
                  color: p.textTertiary,
                ),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: p.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: rows),
            ),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.xs,
              0,
            ),
            child: Text(footer!, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

/// One row: optional leading glyph, title, optional subtitle, and a trailing
/// chevron / value / switch. The whole row is the touch target.
class MevoraListRow extends StatelessWidget {
  const MevoraListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconTone = MevoraTone.neutral,
    this.leading,
    this.trailing,
    this.value,
    this.onTap,
    this.showChevron,
    this.destructive = false,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final MevoraTone iconTone;

  /// Replaces [icon] — e.g. an avatar.
  final Widget? leading;
  final Widget? trailing;

  /// Short current value shown before the chevron ("Istanbul", "On").
  final String? value;
  final VoidCallback? onTap;

  /// Defaults to true when [onTap] is set and there is no [trailing].
  final bool? showChevron;
  final bool destructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final titleColor = !enabled
        ? p.textTertiary
        : destructive
        ? p.error
        : p.textPrimary;
    final chevron = showChevron ?? (onTap != null && trailing == null);

    final lead =
        leading ??
        (icon == null
            ? null
            : destructive
            ? MevoraIconBadge(icon: icon!, tone: MevoraTone.error, size: 36)
            : MevoraIconBadge(icon: icon!, tone: iconTone, size: 36));

    return InkWell(
      onTap: enabled ? onTap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.s12,
          ),
          child: Row(
            children: [
              if (lead != null) ...[
                lead,
                const SizedBox(width: AppSpacing.s12 + 2),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: titleColor,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          height: 20 / 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: AppSpacing.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ],
              if (chevron) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(MevoraIcons.chevronRight, size: 18, color: p.textTertiary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A row whose trailing control is a switch; tapping anywhere toggles it.
class MevoraSwitchRow extends StatelessWidget {
  const MevoraSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.iconTone = MevoraTone.neutral,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final MevoraTone iconTone;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: MevoraListRow(
        title: title,
        subtitle: subtitle,
        icon: icon,
        iconTone: iconTone,
        enabled: onChanged != null,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        showChevron: false,
        trailing: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}
