import 'package:flutter/widgets.dart';
import 'package:mevora/features/music/domain/repositories/music_repository.dart';

class MusicScope extends InheritedWidget {
  const MusicScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final MusicRepository repository;

  static MusicRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MusicScope>();
    assert(scope != null, 'MusicScope not found');
    return scope!.repository;
  }

  static MusicRepository? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MusicScope>()?.repository;
  }

  @override
  bool updateShouldNotify(MusicScope oldWidget) {
    return repository != oldWidget.repository;
  }
}
