import 'package:flutter/material.dart';
import 'package:mevora/shared/widgets/mevora_banner.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MevoraBanner(message: message, tone: MevoraTone.error);
  }
}
