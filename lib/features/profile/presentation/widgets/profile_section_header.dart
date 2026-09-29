import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/shared/widgets/mevora_section_header.dart';

class ProfileSectionHeader extends StatelessWidget {
  const ProfileSectionHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return MevoraSectionHeader(
      title: title,
      subtitle: subtitle,
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
    );
  }
}
