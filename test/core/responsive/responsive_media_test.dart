import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/responsive/responsive_media.dart';

void main() {
  test('clampAspect uses fallback and clamps extremes', () {
    expect(
      ResponsiveMedia.clampAspect(null, fallback: ResponsiveMedia.storyAspect),
      ResponsiveMedia.storyAspect,
    );
    expect(
      ResponsiveMedia.clampAspect(0.1, fallback: ResponsiveMedia.storyAspect),
      0.45,
    );
    expect(
      ResponsiveMedia.clampAspect(9, fallback: ResponsiveMedia.storyAspect),
      2.5,
    );
  });

  testWidgets('galleryMaxHeight scales with compact height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 640)),
          child: Builder(
            builder: (context) {
              final height = ResponsiveMedia.galleryMaxHeight(context);
              expect(height, closeTo(640 * 0.45, 0.01));
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  });
}
