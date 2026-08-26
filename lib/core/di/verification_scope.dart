import 'package:flutter/widgets.dart';
import 'package:mevora/features/verification/domain/repositories/verification_repository.dart';

class VerificationScope extends InheritedWidget {
  const VerificationScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final VerificationRepository repository;

  static VerificationRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<VerificationScope>();
    assert(scope != null, 'VerificationScope not found');
    return scope!.repository;
  }

  static VerificationRepository? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<VerificationScope>()
        ?.repository;
  }

  @override
  bool updateShouldNotify(VerificationScope oldWidget) {
    return repository != oldWidget.repository;
  }
}
