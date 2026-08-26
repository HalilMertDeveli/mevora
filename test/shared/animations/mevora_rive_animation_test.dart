import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/profile/presentation/pages/profile_tab_page.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';
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

  test('Rive stays disabled by default for emulator/device UI parity', () {
    expect(MevoraRiveAnimation.riveEnabled, isFalse);
  });

  test('loading and sync assets stay distinct and compact', () {
    expect(MevoraRiveAssets.loading, 'assets/rive/common/searching.riv');
    expect(MevoraRiveAssets.callConnecting, MevoraRiveAssets.loading);
    expect(MevoraRiveAssets.musicAnalyzing, 'assets/rive/common/loading.riv');
    expect(MevoraRiveAssets.spotifyConnecting, MevoraRiveAssets.musicAnalyzing);
    expect(MevoraRiveAssets.spotifyIdle, MevoraRiveAssets.loginAmbient);
    expect(
      MevoraRiveAssets.relationshipResult,
      MevoraRiveAssets.onboardingComplete,
    );
    expect(MevoraRiveAssets.profileLoading, MevoraRiveAssets.profileAccent);
    expect(MevoraRiveAssets.loading, isNot(MevoraRiveAssets.musicAnalyzing));
  });

  testWidgets('loading still exposes a progress fallback', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(const MevoraLoading.page(message: 'Finding people')),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Finding people'), findsOneWidget);
  });

  testWidgets('profile tab keeps the photo and does not overlay Rive', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithApp(const ProfileTabPage(), scaffold: false),
    );

    expect(find.byType(MevoraAvatar), findsOneWidget);
    expect(find.byType(MevoraRiveAnimation), findsNothing);
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
