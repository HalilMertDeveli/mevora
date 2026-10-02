import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/profile/domain/catalog/height_catalog.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_height_picker.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

import '../../helpers/pump_app.dart';

final _en = lookupAppLocalizations(const Locale('en'));

/// The picker inside a page that scrolls, the way onboarding step 2 and Edit
/// profile host it. The host keeps the value, so a confirmed height comes back
/// into the row.
class _Host extends StatefulWidget {
  const _Host({
    required this.initialCm,
    required this.enabled,
    required this.changes,
    required this.scroll,
  });

  final int? initialCm;
  final bool enabled;
  final List<int?> changes;
  final ScrollController scroll;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late int? _cm = widget.initialCm;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 120),
        ProfileHeightPicker(
          valueCm: _cm,
          enabled: widget.enabled,
          onChanged: (value) {
            widget.changes.add(value);
            setState(() => _cm = value);
          },
        ),
        const SizedBox(height: 1600),
      ],
    );
  }
}

class _Pumped {
  _Pumped(this.changes, this.scroll);

  final List<int?> changes;
  final ScrollController scroll;
}

Future<_Pumped> _pump(
  WidgetTester tester, {
  int? valueCm,
  bool enabled = true,
  Locale locale = const Locale('en'),
  Size? size,
  double textScale = 1.0,
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  final changes = <int?>[];
  final scroll = ScrollController();
  addTearDown(scroll.dispose);
  // Set on the platform so the sheet, which opens on the root navigator, is
  // scaled together with the page.
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    wrapWithApp(
      _Host(
        initialCm: valueCm,
        enabled: enabled,
        changes: changes,
        scroll: scroll,
      ),
      locale: locale,
    ),
  );
  await tester.pumpAndSettle();
  return _Pumped(changes, scroll);
}

Finder get _wheel => find.byType(ListWheelScrollView);

/// The height the open wheel is resting on.
int _wheelCm(WidgetTester tester) {
  final wheel = tester.widget<ListWheelScrollView>(_wheel);
  final controller = wheel.controller! as FixedExtentScrollController;
  return HeightCatalog.options[controller.selectedItem];
}

void main() {
  testWidgets('a drag that starts on the height row scrolls the page', (
    tester,
  ) async {
    final pumped = await _pump(tester, valueCm: 153);

    await tester.drag(find.byType(ProfileHeightPicker), const Offset(0, -90));
    await tester.pumpAndSettle();

    // The acceptance run lost 153 cm to 208 cm this way: the inline wheel
    // took the thumb's drag and the page stayed where it was.
    expect(pumped.scroll.offset, greaterThan(0));
    expect(pumped.changes, isEmpty);
    expect(find.text(_en.profileHeightCm(153)), findsOneWidget);

    // And back down again, still without touching the value.
    await tester.drag(find.byType(ProfileHeightPicker), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(pumped.changes, isEmpty);
    expect(_wheel, findsNothing);
  });

  testWidgets('the row holds no wheel until it is opened', (tester) async {
    await _pump(tester, valueCm: 170);

    expect(_wheel, findsNothing);
    expect(find.text(_en.profileHeightCm(170)), findsOneWidget);
  });

  testWidgets('confirming the sheet reports the chosen height once', (
    tester,
  ) async {
    final pumped = await _pump(tester, valueCm: 170);

    await tester.tap(find.byType(ProfileHeightPicker));
    await tester.pumpAndSettle();
    expect(_wheel, findsOneWidget);
    expect(_wheelCm(tester), 170);

    // Both directions: a downward drag on the wheel must turn the wheel, not
    // drag the sheet closed.
    await tester.drag(_wheel, const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(_wheel, findsOneWidget);
    expect(_wheelCm(tester), lessThan(170));

    await tester.drag(_wheel, const Offset(0, -400));
    await tester.pumpAndSettle();
    final chosen = _wheelCm(tester);
    expect(chosen, greaterThan(170));
    // Turning the wheel is not a decision yet.
    expect(pumped.changes, isEmpty);

    await tester.tap(find.widgetWithText(MevoraButton, _en.done));
    await tester.pumpAndSettle();

    expect(_wheel, findsNothing);
    expect(pumped.changes, [chosen]);
    expect(find.text(_en.profileHeightCm(chosen)), findsOneWidget);
  });

  testWidgets('dismissing the sheet changes nothing', (tester) async {
    final pumped = await _pump(tester, valueCm: 170);

    // Tapping outside the sheet.
    await tester.tap(find.byType(ProfileHeightPicker));
    await tester.pumpAndSettle();
    await tester.drag(_wheel, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(_wheelCm(tester), isNot(170));
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(_wheel, findsNothing);
    expect(pumped.changes, isEmpty);
    expect(find.text(_en.profileHeightCm(170)), findsOneWidget);

    // The system back gesture. The sheet opens on the saved height again,
    // not on where the abandoned wheel was left.
    await tester.tap(find.byType(ProfileHeightPicker));
    await tester.pumpAndSettle();
    expect(_wheelCm(tester), 170);
    await tester.drag(_wheel, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_wheel, findsNothing);
    expect(pumped.changes, isEmpty);
    expect(find.text(_en.profileHeightCm(170)), findsOneWidget);
  });

  testWidgets('a disabled row does not open the sheet', (tester) async {
    final pumped = await _pump(tester, valueCm: 170, enabled: false);

    await tester.tap(find.byType(ProfileHeightPicker), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(_wheel, findsNothing);
    expect(pumped.changes, isEmpty);
    expect(find.text(_en.profileHeightCm(170)), findsOneWidget);
  });

  testWidgets('no height yet: a placeholder, and confirming sets one', (
    tester,
  ) async {
    final pumped = await _pump(tester);

    expect(find.text(_en.profileHeightPlaceholder), findsOneWidget);
    expect(find.textContaining(' cm'), findsNothing);

    // Opening and leaving keeps "not set".
    await tester.tap(find.byType(ProfileHeightPicker));
    await tester.pumpAndSettle();
    expect(_wheel, findsOneWidget);
    final offered = _wheelCm(tester);
    expect(HeightCatalog.isValid(offered), isTrue);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(pumped.changes, isEmpty);
    expect(find.text(_en.profileHeightPlaceholder), findsOneWidget);

    await tester.tap(find.byType(ProfileHeightPicker));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MevoraButton, _en.done));
    await tester.pumpAndSettle();

    expect(pumped.changes, [offered]);
    expect(find.text(_en.profileHeightCm(offered)), findsOneWidget);
  });

  testWidgets('the row is one tappable node named after the field and value', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, valueCm: 170);

    final row = find.bySemanticsLabel(
      '${_en.profileHeightLabel}, ${_en.profileHeightCm(170)}',
    );
    expect(row, findsOneWidget);
    expect(
      tester.getSemantics(row),
      matchesSemantics(
        label: '${_en.profileHeightLabel}, ${_en.profileHeightCm(170)}',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    // The node's own tap opens the sheet, and Done is a labelled button.
    tester.semantics.tap(
      find.semantics.byLabel(
        '${_en.profileHeightLabel}, ${_en.profileHeightCm(170)}',
      ),
    );
    await tester.pumpAndSettle();
    expect(_wheel, findsOneWidget);
    expect(
      tester.getSemantics(find.widgetWithText(MevoraButton, _en.done)),
      matchesSemantics(
        label: _en.done,
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('an empty row announces the placeholder', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    expect(
      find.bySemanticsLabel(
        '${_en.profileHeightLabel}, ${_en.profileHeightPlaceholder}',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  for (final locale in const [Locale('tr'), Locale('en')]) {
    testWidgets('fits a 360x800 phone at text scale 1.3 ($locale)', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(locale);

      // Empty row, then the sheet over it.
      var pumped = await _pump(
        tester,
        locale: locale,
        size: const Size(360, 800),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.text(l10n.profileHeightPlaceholder), findsOneWidget);

      await tester.tap(find.byType(ProfileHeightPicker));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(l10n.profileHeightLabel), findsOneWidget);
      // Done is on screen, not pushed below the fold.
      final done = find.widgetWithText(MevoraButton, l10n.done);
      expect(done.hitTestable(), findsOneWidget);
      expect(tester.getBottomLeft(done).dy, lessThanOrEqualTo(800));

      await tester.drag(_wheel, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(_wheelCm(tester), HeightCatalog.maxCm);
      expect(tester.takeException(), isNull);
      await tester.tap(done);
      await tester.pumpAndSettle();

      // The widest value in the row.
      expect(pumped.changes, [HeightCatalog.maxCm]);
      expect(
        find.text(l10n.profileHeightCm(HeightCatalog.maxCm)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      pumped = await _pump(
        tester,
        valueCm: HeightCatalog.minCm,
        locale: locale,
        size: const Size(360, 800),
        textScale: 1.3,
      );
      expect(pumped.changes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
