import 'dart:async';

import 'package:mevora/features/matching/domain/models/match.dart';

extension UnreadableMatch on Stream<Match?> {
  /// Reports a match that cannot be read as `null`, the value `watchMatch`
  /// already uses for "no match".
  ///
  /// firestore.rules (B-07) refuses a listen on a match the viewer is not in,
  /// and refuses it the same way when the match does not exist, so a
  /// permission error is the everyday answer for two members who are not
  /// matched. A failed listener delivers nothing afterwards: dropping the
  /// error would leave every subscriber waiting for a first event that never
  /// comes.
  Stream<Match?> unreadableAsNull() {
    return transform(
      StreamTransformer<Match?, Match?>.fromHandlers(
        handleError: (error, stackTrace, sink) => sink.add(null),
      ),
    );
  }
}
