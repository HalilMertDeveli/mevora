import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/shared/widgets/mevora_widgets.dart';
import 'package:mevora/shared/widgets/mevora_context_row.dart';
import 'package:mevora/shared/widgets/mevora_selectable_tile.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('MevoraButton', () {
    testWidgets('every variant renders a pill at least 48dp tall', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithApp(
          Column(
            children: [
              for (final variant in MevoraButtonVariant.values)
                MevoraButton(
                  key: ValueKey(variant),
                  label: variant.name,
                  variant: variant,
                  onPressed: () {},
                ),
            ],
          ),
        ),
      );

      for (final variant in MevoraButtonVariant.values) {
        final size = tester.getSize(find.byKey(ValueKey(variant)));
        expect(size.height, greaterThanOrEqualTo(48), reason: variant.name);
      }
    });

    testWidgets('primary uses the ember accent and destructive the error', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithApp(
          Column(
            children: [
              MevoraButton(label: 'Go', onPressed: () {}),
              MevoraButton(
                label: 'Delete',
                variant: MevoraButtonVariant.destructive,
                onPressed: () {},
              ),
            ],
          ),
        ),
      );

      Color? bgOf(String label) {
        final button = tester.widget<TextButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(TextButton),
          ),
        );
        return button.style?.backgroundColor?.resolve({});
      }

      expect(bgOf('Go'), AppColors.ember);
      expect(bgOf('Delete'), MevoraPalette.light.error);
    });

    testWidgets('a disabled button announces itself as disabled', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrapWithApp(const MevoraButton(label: 'Save')));

      expect(
        tester.getSemantics(find.byType(MevoraButton)),
        matchesSemantics(label: 'Save', isButton: true, hasEnabledState: true),
      );
      handle.dispose();
    });
  });

  testWidgets('icon button requires and exposes a tooltip', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        MevoraIconButton(
          icon: MevoraIcons.filters,
          tooltip: 'Filters',
          onPressed: () {},
        ),
      ),
    );

    expect(find.byTooltip('Filters'), findsOneWidget);
    expect(
      tester.getSize(find.byType(MevoraIconButton)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('pill resolves its tone from the palette', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        const MevoraPill(
          label: 'Music',
          icon: MevoraIcons.track,
          tone: MevoraTone.music,
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(MevoraIcons.track));
    expect(icon.color, MevoraPalette.light.music);
    expect(find.text('Music'), findsOneWidget);
  });

  testWidgets('list group separates rows and the switch row toggles', (
    tester,
  ) async {
    var value = false;
    await tester.pumpWidget(
      wrapWithApp(
        StatefulBuilder(
          builder: (context, setState) => MevoraListGroup(
            title: 'Privacy',
            children: [
              const MevoraListRow(title: 'Row one'),
              MevoraSwitchRow(
                title: 'Show age',
                value: value,
                onChanged: (next) => setState(() => value = next),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('PRIVACY'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    await tester.tap(find.text('Show age'));
    await tester.pump();
    expect(value, isTrue);
  });

  testWidgets('destructive rows are drawn in the error colour', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        MevoraListRow(title: 'Delete account', destructive: true, onTap: () {}),
      ),
    );

    final text = tester.widget<Text>(find.text('Delete account'));
    expect(text.style?.color, MevoraPalette.light.error);
  });

  testWidgets('banner shows its action only when wired', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      wrapWithApp(
        Column(
          children: [
            const MevoraBanner(message: 'Saved', tone: MevoraTone.success),
            MevoraBanner(
              message: 'Failed',
              tone: MevoraTone.error,
              actionLabel: 'Retry',
              onAction: () => tapped = true,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(tapped, isTrue);
  });

  testWidgets('meter reports its value to assistive technology', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      wrapWithApp(const MevoraMeter(value: 0.62, semanticLabel: 'Progress')),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byType(MevoraMeter)),
      matchesSemantics(label: 'Progress', value: '62%'),
    );
    handle.dispose();
  });

  testWidgets('selectable tile marks the selected option', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      wrapWithApp(
        MevoraSelectableTile(
          title: 'Monthly',
          trailing: '₺199',
          selected: true,
          onTap: () {},
        ),
      ),
    );

    expect(find.text('₺199'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(MevoraSelectableTile)),
      isSemantics(
        label: 'Monthly, ₺199',
        isButton: true,
        isSelected: true,
        isInMutuallyExclusiveGroup: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('context row opens on tap', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      wrapWithApp(
        MevoraContextRow(
          icon: MevoraIcons.questions,
          title: 'See their answers',
          onTap: () => opened = true,
        ),
      ),
    );

    await tester.tap(find.text('See their answers'));
    expect(opened, isTrue);
  });

  testWidgets('dialog stacks the confirm action above cancel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => MevoraDialog.show(
              context,
              title: 'Log out?',
              message: 'You can sign back in any time.',
              confirmLabel: 'Log out',
              cancelLabel: 'Stay',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    final confirm = tester.getTopLeft(find.text('Log out'));
    final cancel = tester.getTopLeft(find.text('Stay'));
    expect(confirm.dy, lessThan(cancel.dy));
  });

  testWidgets('avatar falls back to serif initials', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(const MevoraAvatar(name: 'Deniz Kaya', size: 64)),
    );

    final initials = tester.widget<Text>(find.text('DK'));
    expect(initials.style?.fontFamily, 'Fraunces');
  });
}
