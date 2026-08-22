import 'package:flutter/widgets.dart';

/// Optional video surfaces. Domain [VideoCallProvider] stays SDK-agnostic.
abstract class VideoCallSurface {
  Widget? remoteVideo();

  Widget? localVideo();
}
