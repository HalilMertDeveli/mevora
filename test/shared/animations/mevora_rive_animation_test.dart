import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('Rive wrapper falls back in tests without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithApp(
        const MevoraRiveAnimation(
          asset: MevoraRiveAssets.loading,
          width: 32,
          height: 32,
          fallback: Text('fallback'),
        ),
      ),
    );

    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('loading still exposes a progress fallback', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(const MevoraLoading.page(message: 'Finding people')),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Finding people'), findsOneWidget);
  });

  testWidgets('empty and error views keep copy with fallbacks', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        const MevoraEmptyState(
          riveAsset: MevoraRiveAssets.empty,
          title: 'No profiles',
          message: 'Try later.',
        ),
      ),
    );
    expect(find.text('No profiles'), findsOneWidget);

    await tester.pumpWidget(wrapWithApp(const MevoraErrorView(title: 'Oops')));
    expect(find.text('Oops'), findsOneWidget);
  });
}
