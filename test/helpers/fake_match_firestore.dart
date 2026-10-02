import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

typedef _MatchSnapshot = DocumentSnapshot<Map<String, dynamic>>;

/// What Firestore answers when a member listens to a match they are not in.
///
/// firestore.rules (B-07) refuses that listen the same way whether the match
/// exists or not, so this is the everyday answer for two unmatched members.
FirebaseException matchReadDenied() => FirebaseException(
  plugin: 'cloud_firestore',
  code: 'permission-denied',
  message: 'Missing or insufficient permissions.',
);

/// Just enough [FirebaseFirestore] to drive `doc(path).snapshots()`.
///
/// Like the real SDK, a refused listen delivers one error and then nothing —
/// the stream stays open and silent.
class FakeMatchFirestore implements FirebaseFirestore {
  final _documents = <String, StreamController<_MatchSnapshot>>{};

  StreamController<_MatchSnapshot> _document(String path) {
    return _documents.putIfAbsent(path, StreamController<_MatchSnapshot>.new);
  }

  /// Delivers a snapshot of [path]; null [data] is a document that is missing.
  void emit(String path, Map<String, dynamic>? data) {
    _document(path).add(_FakeMatchSnapshot(path.split('/').last, data));
  }

  void deny(String path) => _document(path).addError(matchReadDenied());

  @override
  DocumentReference<Map<String, dynamic>> doc(String documentPath) {
    return _FakeMatchReference(_document(documentPath).stream);
  }

  Future<void> dispose() async {
    for (final document in _documents.values) {
      unawaited(document.close());
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _FakeMatchReference implements DocumentReference<Map<String, dynamic>> {
  const _FakeMatchReference(this._snapshots);

  final Stream<_MatchSnapshot> _snapshots;

  @override
  Stream<_MatchSnapshot> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => _snapshots;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _FakeMatchSnapshot implements _MatchSnapshot {
  const _FakeMatchSnapshot(this.id, this._data);

  @override
  final String id;

  final Map<String, dynamic>? _data;

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
