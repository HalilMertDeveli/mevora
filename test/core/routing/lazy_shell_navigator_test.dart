import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/routing/lazy_shell_navigator.dart';

void main() {
  testWidgets('LazyShellNavigator mounts only the active branch first', (
    tester,
  ) async {
    final mounts = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LazyShellNavigator(
          currentIndex: 0,
          children: [
            for (var i = 0; i < 4; i++)
              _MountProbe(index: i, onMount: mounts.add),
          ],
        ),
      ),
    );

    expect(mounts, [0]);
    final state = tester.state<LazyShellNavigatorState>(
      find.byType(LazyShellNavigator),
    );
    expect(state.debugLoadedBranches, [true, false, false, false]);
  });

  testWidgets('LazyShellNavigator keeps visited branches alive across switches', (
    tester,
  ) async {
    final mounts = <int>[];
    var index = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              children: [
                Expanded(
                  child: LazyShellNavigator(
                    currentIndex: index,
                    children: [
                      for (var i = 0; i < 4; i++)
                        _MountProbe(index: i, onMount: mounts.add),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => index = (index + 1) % 4),
                  child: const Text('next'),
                ),
              ],
            );
          },
        ),
      ),
    );

    expect(mounts, [0]);

    // Visit all tabs once.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('next'));
      await tester.pump();
    }
    expect(mounts, [0, 1, 2, 3]);

    // Fast switching must not remount already-visited branches.
    mounts.clear();
    for (var i = 0; i < 20; i++) {
      await tester.tap(find.text('next'));
      await tester.pump();
    }
    expect(mounts, isEmpty);
  });

  testWidgets('offstage branch disables TickerMode', (tester) async {
    var index = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              children: [
                Expanded(
                  child: LazyShellNavigator(
                    currentIndex: index,
                    children: const [
                      _TickerProbe(key: Key('a')),
                      _TickerProbe(key: Key('b')),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => index = 1),
                  child: const Text('to-b'),
                ),
              ],
            );
          },
        ),
      ),
    );

    expect(find.text('ticker:true'), findsOneWidget);
    await tester.tap(find.text('to-b'));
    await tester.pump();
    // Both branches stay mounted; only the active one enables tickers.
    expect(find.text('ticker:true'), findsOneWidget);
    expect(
      find.text('ticker:false', skipOffstage: false),
      findsOneWidget,
    );
  });
}

class _MountProbe extends StatefulWidget {
  const _MountProbe({required this.index, required this.onMount});

  final int index;
  final ValueChanged<int> onMount;

  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount(widget.index);
  }

  @override
  Widget build(BuildContext context) => Text('tab-${widget.index}');
}

class _TickerProbe extends StatelessWidget {
  const _TickerProbe({super.key});

  @override
  Widget build(BuildContext context) {
    return Text('ticker:${TickerMode.valuesOf(context).enabled}');
  }
}
