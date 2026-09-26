import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_swipe_overlay.dart';

Future<void> _pump(WidgetTester tester, Offset drag) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 520,
          child: DiscoverySwipeOverlay(dragOffset: drag),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('right drag shows a heart and no label', (tester) async {
    await _pump(tester, const Offset(100, 0));
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('left drag shows a cross', (tester) async {
    await _pump(tester, const Offset(-100, 0));
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets('upward drag shows a star', (tester) async {
    await _pump(tester, const Offset(0, -100));
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
  });

  testWidgets('small drag shows nothing', (tester) async {
    await _pump(tester, const Offset(10, 0));
    expect(find.byType(Icon), findsNothing);
  });
}
