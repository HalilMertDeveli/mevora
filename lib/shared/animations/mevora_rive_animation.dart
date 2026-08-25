import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart' as rive;

/// Loads a Rive graphic with a Flutter fallback.
///
/// Rive is **off by default** so physical devices match the emulator: on many
/// x86 emulators `RiveNative.init` fails and the Flutter fallback is shown,
/// while arm64 phones successfully play `.riv` files and look different.
///
/// Opt in only when you explicitly want Rive:
/// `--dart-define=ENABLE_RIVE=true`
///
/// Also skips Rive in widget tests, when the user prefers reduced motion, or
/// when the asset cannot be decoded. The app never depends on a `.riv` file to
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

  /// When false (default), always render [fallback] / Flutter motion — never
  /// native Rive. Keeps emulator and real-device UI identical.
  static bool get riveEnabled {
    if (isTestBinding) {
      return false;
    }
    return const bool.fromEnvironment('ENABLE_RIVE', defaultValue: false);
  }

  @override
  State<MevoraRiveAnimation> createState() => _MevoraRiveAnimationState();
}

class _MevoraRiveAnimationState extends State<MevoraRiveAnimation> {
  static final Set<String> _missingAssets = <String>{};
  static final Set<String> _availableAssets = <String>{};
  static Future<bool>? _nativeInit;

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
    // Default path: Flutter fallback only (parity with emulator / no Rive UI).
    if (!MevoraRiveAnimation.riveEnabled) {
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

    _nativeInit ??= () async {
      try {
        await rive.RiveNative.init();
        return true;
      } on Object {
        return false;
      }
    }();
    if (!await _nativeInit!) {
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
        SizedBox(
          width: (widget.height ?? widget.width ?? 40).clamp(18, 40),
          height: (widget.height ?? widget.width ?? 40).clamp(18, 40),
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: Theme.of(context).colorScheme.primary,
          ),
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

  Iterable<rive.ArtboardSelector> get _artboardSelectors {
    final name = widget.artboardName;
    if (name != null) {
      return [rive.ArtboardNamed(name)];
    }
    return const [rive.ArtboardDefault(), rive.ArtboardAtIndex(0)];
  }

  Iterable<rive.StateMachineSelector> get _stateMachineSelectors {
    final name = widget.stateMachineName;
    if (name != null) {
      return [rive.StateMachineNamed(name)];
    }
    return const [rive.StateMachineDefault(), rive.StateMachineAtIndex(0)];
  }

  rive.RiveWidgetController _createController(rive.File file) {
    Object? lastError;
    for (final artboardSelector in _artboardSelectors) {
      for (final stateMachineSelector in _stateMachineSelectors) {
        try {
          final controller = rive.RiveWidgetController(
            file,
            artboardSelector: artboardSelector,
            stateMachineSelector: stateMachineSelector,
          );
          _kickPlayback(controller.stateMachine);
          return controller;
        } on rive.RiveArtboardException catch (error) {
          lastError = error;
          break;
        } on Object catch (error) {
          lastError = error;
        }
      }
    }
    throw lastError ??
        rive.RiveStateMachineException(
          'No playable artboard or state machine in ${widget.asset}.',
        );
  }

  void _kickPlayback(rive.StateMachine machine) {
    // Some .riv files (e.g. leftover liquid download) stay static unless
    // Downloading/Indeterminate inputs are driven. Harmless for autoplay
    // walk/search machines.
    for (var i = 0; ; i++) {
      // ignore: deprecated_member_use
      final input = machine.inputAt(i);
      if (input == null) {
        break;
      }
      final name = input.name.toLowerCase();
      if (input is rive.BooleanInput) {
        if (name.contains('indeterminate') ||
            name.contains('download') ||
            name == 'loop' ||
            name == 'play') {
          input.value = true;
        }
      } else if (input is rive.TriggerInput) {
        if (name.contains('indeterminate') || name == 'start') {
          input.fire();
        }
      } else if (input is rive.NumberInput) {
        if (name.contains('progress') && input.value >= 99) {
          input.value = 0;
        }
      }
    }
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
        controller: _createController,
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
