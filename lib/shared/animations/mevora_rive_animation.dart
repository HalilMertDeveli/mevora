import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart' as rive;

/// Loads a Rive graphic with a Flutter fallback.
///
/// Skips Rive in widget tests, when the user prefers reduced motion, or when
/// the asset cannot be decoded. The app never depends on a `.riv` file to
/// remain usable.
class MevoraRiveAnimation extends StatefulWidget {
  const MevoraRiveAnimation({
    super.key,
    required this.asset,
    this.autoplay = true,
    this.loop = true,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.artboardName,
    this.stateMachineName,
    this.animationName,
    this.fallback,
    this.semanticsLabel,
  });

  final String asset;
  final bool autoplay;
  final bool loop;
  final double? width;
  final double? height;
  final BoxFit fit;
  final String? artboardName;
  final String? stateMachineName;
  final String? animationName;
  final Widget? fallback;
  final String? semanticsLabel;

  static bool get isTestBinding =>
      WidgetsBinding.instance.runtimeType.toString().contains(
        'TestWidgetsFlutterBinding',
      );

  @override
  State<MevoraRiveAnimation> createState() => _MevoraRiveAnimationState();
}

class _MevoraRiveAnimationState extends State<MevoraRiveAnimation> {
  static final Set<String> _missingAssets = <String>{};
  static final Set<String> _availableAssets = <String>{};

  rive.FileLoader? _loader;
  bool _assetReady = false;
  bool _assetMissing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareLoader());
  }

  @override
  void didUpdateWidget(MevoraRiveAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset ||
        oldWidget.artboardName != widget.artboardName ||
        oldWidget.stateMachineName != widget.stateMachineName) {
      _disposeLoader();
      _assetReady = false;
      _assetMissing = false;
      unawaited(_prepareLoader());
    }
  }

  @override
  void dispose() {
    _disposeLoader();
    super.dispose();
  }

  Future<void> _prepareLoader() async {
    if (MevoraRiveAnimation.isTestBinding) {
      return;
    }

    final asset = widget.asset;
    if (_missingAssets.contains(asset)) {
      if (!mounted) {
        return;
      }
      setState(() {
        _assetMissing = true;
        _assetReady = true;
      });
      return;
    }

    if (!_availableAssets.contains(asset)) {
      try {
        await rootBundle.load(asset);
        _availableAssets.add(asset);
      } on Object {
        _missingAssets.add(asset);
        if (!mounted) {
          return;
        }
        setState(() {
          _loader = null;
          _assetMissing = true;
          _assetReady = true;
        });
        return;
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _loader = rive.FileLoader.fromAsset(
        asset,
        riveFactory: rive.Factory.rive,
      );
      _assetMissing = false;
      _assetReady = true;
    });
  }

  void _disposeLoader() {
    _loader?.dispose();
    _loader = null;
  }

  Widget _fallback(BuildContext context) {
    return widget.fallback ??
        Icon(
          Icons.auto_awesome_outlined,
          size: (widget.height ?? widget.width ?? 40).clamp(18, 56),
          color: Theme.of(context).colorScheme.primary,
        );
  }

  rive.Fit _riveFit() {
    return switch (widget.fit) {
      BoxFit.cover => rive.Fit.cover,
      BoxFit.fill => rive.Fit.fill,
      BoxFit.fitWidth => rive.Fit.fitWidth,
      BoxFit.fitHeight => rive.Fit.fitHeight,
      BoxFit.none => rive.Fit.none,
      BoxFit.scaleDown => rive.Fit.scaleDown,
      _ => rive.Fit.contain,
    };
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final allowPlayback = widget.autoplay && !reduceMotion;
    final loader = _loader;

    Widget child;
    if (!_assetReady || _assetMissing || loader == null || !allowPlayback) {
      child = _fallback(context);
    } else {
      child = rive.RiveWidgetBuilder(
        fileLoader: loader,
        artboardSelector: widget.artboardName == null
            ? const rive.ArtboardDefault()
            : rive.ArtboardNamed(widget.artboardName!),
        stateMachineSelector: widget.stateMachineName == null
            ? const rive.StateMachineDefault()
            : rive.StateMachineNamed(widget.stateMachineName!),
        builder: (context, state) {
          if (state is rive.RiveLoaded) {
            return rive.RiveWidget(
              controller: state.controller,
              fit: _riveFit(),
              hitTestBehavior: rive.RiveHitTestBehavior.transparent,
            );
          }
          return _fallback(context);
        },
      );
    }

    return Semantics(
      label: widget.semanticsLabel,
      image: true,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: child,
      ),
    );
  }
}
