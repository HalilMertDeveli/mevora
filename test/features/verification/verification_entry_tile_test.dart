import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/features/verification/presentation/widgets/verification_entry_tile.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('verification entry shows verify title when not started', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithApp(
        const VerificationEntryTile(
          status: IdentityVerificationStatus.notStarted,
          accountVerified: false,
        ),
      ),
    );

    expect(find.text('Verify your profile'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('verification entry shows badge when verified', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        const VerificationEntryTile(
          status: IdentityVerificationStatus.verified,
          accountVerified: true,
        ),
      ),
    );

    expect(find.text('Profile verified'), findsOneWidget);
    expect(find.byIcon(Icons.verified), findsWidgets);
  });
}
