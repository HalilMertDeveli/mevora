import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';

/// Fullscreen chat photo viewer with pinch-zoom / pan.
///
/// Opened via [open] with a [Navigator] push so the underlying chat route
/// stays mounted and keeps its scroll offset.
class ChatFullscreenImageViewer extends StatefulWidget {
  const ChatFullscreenImageViewer({
    super.key,
    required this.imageProvider,
  });

  final ImageProvider imageProvider;

  /// Resolves an [ImageProvider] from chat media and pushes this viewer on
  /// the root navigator. No-op when there is nothing displayable.
  static Future<void> open(
    BuildContext context, {
    String? url,
    List<int>? bytes,
  }) {
    final provider = resolveProvider(url: url, bytes: bytes);
    if (provider == null) {
      return Future<void>.value();
    }
    if (!context.mounted) {
      return Future<void>.value();
    }
    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, animation, secondaryAnimation) {
          return ChatFullscreenImageViewer(imageProvider: provider);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// Same resolution rules as chat thumbnails ([MevoraNetworkImages] / memory).
  static ImageProvider? resolveProvider({
    String? url,
    List<int>? bytes,
  }) {
    final local = bytes;
    if (local != null && local.isNotEmpty) {
      return MemoryImage(Uint8List.fromList(local));
    }
    return MevoraNetworkImages.provider(url);
  }

  @override
  State<ChatFullscreenImageViewer> createState() =>
      _ChatFullscreenImageViewerState();
}

class _ChatFullscreenImageViewerState extends State<ChatFullscreenImageViewer> {
  final TransformationController _transform = TransformationController();
  int _reloadToken = 0;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _close() {
    if (!mounted) {
      return;
    }
    unawaited(Navigator.of(context).maybePop());
  }

  void _resetZoom() {
    _transform.value = Matrix4.identity();
  }

  Future<void> _retry() async {
    await widget.imageProvider.evict();
    if (!mounted) {
      return;
    }
    setState(() => _reloadToken++);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onDoubleTap: _resetZoom,
              onTap: () {
                // Close only when not zoomed so pinch/pan stays usable.
                if (_transform.value.getMaxScaleOnAxis() <= 1.01) {
                  _close();
                } else {
                  _resetZoom();
                }
              },
              child: InteractiveViewer(
                key: ValueKey<int>(_reloadToken),
                transformationController: _transform,
                minScale: 1,
                maxScale: 4,
                clipBehavior: Clip.none,
                child: SizedBox.expand(
                  child: Center(
                    child: Image(
                      image: widget.imageProvider,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) {
                          return child;
                        }
                        return const Center(
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white70,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return _ErrorBody(
                          message: l10n.unexpectedError,
                          retryLabel: l10n.retry,
                          onRetry: () {
                            unawaited(_retry());
                          },
                          onClose: _close,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: _close,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
    required this.onClose,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 48),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: onRetry,
                child: Text(retryLabel, style: const TextStyle(color: Colors.white)),
              ),
              TextButton(
                onPressed: onClose,
                child: Text(
                  MaterialLocalizations.of(context).closeButtonLabel,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
