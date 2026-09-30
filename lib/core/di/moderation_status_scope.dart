import 'package:flutter/widgets.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/moderation_status/data/callable_moderation_status_repository.dart';
import 'package:mevora/features/moderation_status/domain/repositories/moderation_status_repository.dart';

/// Access to the member's own moderation record and the appeal path.
class ModerationStatusScope extends InheritedWidget {
  const ModerationStatusScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final ModerationStatusRepository repository;

  /// Null when moderation status is not wired (tests, previews).
  static ModerationStatusRepository? maybeRepositoryOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ModerationStatusScope>()
        ?.repository;
  }

  @override
  bool updateShouldNotify(ModerationStatusScope oldWidget) {
    return oldWidget.repository != repository;
  }
}

ModerationStatusRepository createModerationStatusRepository({
  BackendCallable? backend,
}) {
  return CallableModerationStatusRepository(
    backend: backend ?? FirebaseFunctionsCallable(),
  );
}
