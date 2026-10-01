import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/face_anchor/data/datasources/firebase_face_anchor_data_source.dart';
import 'package:mevora/features/face_anchor/data/repositories/face_anchor_repository_impl.dart';
import 'package:mevora/features/face_anchor/data/services/image_picker_live_selfie_capture.dart';
import 'package:mevora/features/face_anchor/domain/repositories/face_anchor_repository.dart';
import 'package:mevora/features/face_anchor/domain/services/live_selfie_capture.dart';
import 'package:mevora/features/face_anchor/presentation/controllers/face_anchor_controller.dart';

class FaceAnchorServices {
  const FaceAnchorServices({required this.repository, required this.capture});

  final FaceAnchorRepository repository;
  final LiveSelfieCapture capture;

  /// One controller per screen that shows verification state; the screen
  /// binds it to the signed-in member and disposes it.
  FaceAnchorController createController() =>
      FaceAnchorController(repository: repository, capture: capture);
}

FaceAnchorServices createFaceAnchorServices({
  BackendCallable? backend,
  LiveSelfieCapture? capture,
}) {
  return FaceAnchorServices(
    repository: FaceAnchorRepositoryImpl(
      remote: FirebaseFaceAnchorDataSource(
        backend: backend ?? FirebaseFunctionsCallable(),
      ),
    ),
    capture: capture ?? ImagePickerLiveSelfieCapture(),
  );
}
