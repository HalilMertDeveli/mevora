import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('avatar shows initials and a verified badge', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        const MevoraAvatar(name: 'Ada Lovelace', isVerified: true),
      ),
    );

    expect(find.text('AL'), findsOneWidget);
    expect(find.byIcon(Icons.verified), findsOneWidget);
  });
}
