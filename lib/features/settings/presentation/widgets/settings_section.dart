import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/shared/widgets/mevora_list.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// A titled settings group. Utility screens stay calmer than Discover or
/// Profile: one white surface per group, one hairline between rows.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.footer,
  });

  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: MevoraListGroup(title: title, footer: footer, children: children),
    );
  }
}

/// An untitled group of rows.
class MevoraSettingsGroup extends StatelessWidget {
  const MevoraSettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => MevoraListGroup(children: children);
}

/// A settings row that navigates (or acts). Destructive rows are drawn in
/// the error colour so account-ending actions are unmistakable.
class SettingsNavTile extends StatelessWidget {
  const SettingsNavTile({
    super.key,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.destructive = false,
    this.icon,
    this.iconTone = MevoraTone.neutral,
    this.value,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;
  final IconData? icon;
  final MevoraTone iconTone;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return MevoraListRow(
      title: title,
      subtitle: subtitle,
      icon: icon,
      iconTone: iconTone,
      value: value,
      trailing: trailing,
      destructive: destructive,
      showChevron: onTap != null && trailing == null && !destructive,
      onTap: onTap,
    );
  }
}
