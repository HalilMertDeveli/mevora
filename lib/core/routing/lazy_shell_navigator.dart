import 'package:flutter/widgets.dart';

/// Builds only the visited shell branches. IndexedStack otherwise mounts every
/// tab (discovery, matches, music, profile) on first login and can ANR.
class LazyShellNavigator extends StatefulWidget {
  const LazyShellNavigator({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  State<LazyShellNavigator> createState() => _LazyShellNavigatorState();
}

class _LazyShellNavigatorState extends State<LazyShellNavigator> {
  late List<bool> _loaded;

  @override
  void initState() {
    super.initState();
    _loaded = List<bool>.generate(
      widget.children.length,
      (index) => index == widget.currentIndex,
    );
  }

  @override
  void didUpdateWidget(LazyShellNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_loaded.length != widget.children.length) {
      _loaded = List<bool>.generate(
        widget.children.length,
        (index) =>
            index == widget.currentIndex ||
            (index < _loaded.length && _loaded[index]),
      );
    } else if (!_loaded[widget.currentIndex]) {
      _loaded[widget.currentIndex] = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.currentIndex,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          Offstage(
            offstage: i != widget.currentIndex,
            child: TickerMode(
              enabled: i == widget.currentIndex,
              child: _loaded[i] ? widget.children[i] : const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }
}
