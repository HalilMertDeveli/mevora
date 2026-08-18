import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('chip reports selection changes', (tester) async {
    var selected = false;

    await tester.pumpWidget(
      wrapWithApp(
        MevoraChip(
          label: 'Travel',
          selected: selected,
          onSelected: (value) => selected = value,
        ),
      ),
    );

    await tester.tap(find.text('Travel'));
    expect(selected, isTrue);
  });
}
