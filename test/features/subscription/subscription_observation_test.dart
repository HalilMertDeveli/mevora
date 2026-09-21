import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/subscription_scope.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/subscription/data/repositories/firestore_subscription_repository.dart';
import 'package:mevora/features/subscription/domain/entities/subscription_lifecycle.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';
import 'package:mevora/features/subscription/presentation/controllers/subscription_controller.dart';

class FakeUidSource implements AuthUidSource {
  final StreamController<String?> _uids = StreamController<String?>.broadcast();
  String? _current;

  @override
  String? get currentUid => _current;

  @override
  Stream<String?> watchUid() => _uids.stream;

  void emit(String? uid) {
    _current = uid;
    _uids.add(uid);
  }

  Future<void> close() => _uids.close();
}

class FakeSubscriptionRepository implements SubscriptionRepository {
  final StreamController<PremiumStatus> _controller =
      StreamController<PremiumStatus>.broadcast();

  @override
  Stream<PremiumStatus> watch() => _controller.stream;

  void emit(PremiumStatus status) => _controller.add(status);

  void fail() => _controller.addError(StateError('stream broke'));

  Future<void> close() => _controller.close();
}

void main() {
  final now = DateTime.utc(2026, 9, 22, 12);
  final future = DateTime.utc(2026, 10, 22, 12);

  group('FirestoreSubscriptionRepository', () {
    late FakeUidSource uidSource;
    late Map<String, StreamController<Map<String, dynamic>?>> documents;

    FirestoreSubscriptionRepository buildRepository() {
      return FirestoreSubscriptionRepository(
        uidSource: uidSource,
        clock: () => now,
        documentStream: (uid) {
          final controller = documents.putIfAbsent(
            uid,
            () => StreamController<Map<String, dynamic>?>.broadcast(),
          );
          return controller.stream;
        },
      );
    }

    setUp(() {
      uidSource = FakeUidSource();
      documents = <String, StreamController<Map<String, dynamic>?>>{};
    });

    tearDown(() async {
      for (final controller in documents.values) {
        await controller.close();
      }
      await uidSource.close();
    });

    test('observes the signed-in user subscription document', () async {
      final emitted = <PremiumStatus>[];
      final subscription = buildRepository().watch().listen(emitted.add);

      uidSource.emit('user-a');
      await pumpEventQueue();
      documents['user-a']!.add(<String, dynamic>{
        'status': 'active',
        'entitlement': 'premium',
        'expiresAt': future,
      });
      await pumpEventQueue();

      expect(emitted.first.isPremium, isFalse, reason: 'starts free');
      expect(emitted.last.isPremium, isTrue);
      expect(emitted.last.lifecycle, SubscriptionLifecycle.active);
      await subscription.cancel();
    });

    test('missing document resolves to the free state', () async {
      final emitted = <PremiumStatus>[];
      final subscription = buildRepository().watch().listen(emitted.add);

      uidSource.emit('user-a');
      await pumpEventQueue();
      documents['user-a']!.add(null);
      await pumpEventQueue();

      expect(emitted.last.isPremium, isFalse);
      expect(emitted.last.lifecycle, SubscriptionLifecycle.none);
      await subscription.cancel();
    });

    test('a partial document fails safe instead of throwing', () async {
      final emitted = <PremiumStatus>[];
      final subscription = buildRepository().watch().listen(emitted.add);

      uidSource.emit('user-a');
      await pumpEventQueue();
      documents['user-a']!.add(<String, dynamic>{'entitlement': 'premium'});
      await pumpEventQueue();

      expect(emitted.last.isPremium, isFalse);
      await subscription.cancel();
    });

    test('entitlement does not leak across a user switch', () async {
      final emitted = <PremiumStatus>[];
      final subscription = buildRepository().watch().listen(emitted.add);

      uidSource.emit('user-a');
      await pumpEventQueue();
      documents['user-a']!.add(<String, dynamic>{
        'status': 'active',
        'entitlement': 'premium',
        'expiresAt': future,
      });
      await pumpEventQueue();
      expect(emitted.last.isPremium, isTrue);

      // Second account signs in; its document has not arrived yet.
      uidSource.emit('user-b');
      await pumpEventQueue();
      expect(
        emitted.last.isPremium,
        isFalse,
        reason: 'the previous account entitlement must be dropped at once',
      );

      // Late snapshot from the signed-out account must not reach the stream.
      documents['user-a']!.add(<String, dynamic>{
        'status': 'active',
        'entitlement': 'premium',
        'expiresAt': future,
      });
      await pumpEventQueue();
      expect(emitted.last.isPremium, isFalse);
      await subscription.cancel();
    });

    test('sign-out clears entitlement', () async {
      final emitted = <PremiumStatus>[];
      final subscription = buildRepository().watch().listen(emitted.add);

      uidSource.emit('user-a');
      await pumpEventQueue();
      documents['user-a']!.add(<String, dynamic>{
        'status': 'active',
        'entitlement': 'premium',
        'expiresAt': future,
      });
      await pumpEventQueue();
      expect(emitted.last.isPremium, isTrue);

      uidSource.emit(null);
      await pumpEventQueue();
      expect(emitted.last.isPremium, isFalse);
      await subscription.cancel();
    });
  });

  group('SubscriptionController', () {
    test('starts free and follows the repository', () async {
      final repository = FakeSubscriptionRepository();
      final controller = SubscriptionController(repository: repository)
        ..start();
      addTearDown(controller.dispose);
      addTearDown(repository.close);

      expect(controller.isPremium, isFalse);

      repository.emit(
        PremiumStatus(
          isPremium: true,
          lifecycle: SubscriptionLifecycle.active,
          expiresAt: future,
        ),
      );
      await pumpEventQueue();
      expect(controller.isPremium, isTrue);

      repository.emit(PremiumStatus.free);
      await pumpEventQueue();
      expect(controller.isPremium, isFalse);
    });

    test('a stream error falls back to the free state', () async {
      final repository = FakeSubscriptionRepository();
      final controller = SubscriptionController(repository: repository)
        ..start();
      addTearDown(controller.dispose);
      addTearDown(repository.close);

      repository.emit(
        const PremiumStatus(
          isPremium: true,
          lifecycle: SubscriptionLifecycle.active,
        ),
      );
      await pumpEventQueue();
      expect(controller.isPremium, isTrue);

      repository.fail();
      await pumpEventQueue();
      expect(controller.isPremium, isFalse);
    });

    test('start is idempotent', () async {
      final repository = FakeSubscriptionRepository();
      final controller = SubscriptionController(repository: repository)
        ..start()
        ..start();
      addTearDown(controller.dispose);
      addTearDown(repository.close);

      var notifications = 0;
      controller.addListener(() => notifications += 1);
      repository.emit(
        const PremiumStatus(
          isPremium: true,
          lifecycle: SubscriptionLifecycle.active,
        ),
      );
      await pumpEventQueue();
      expect(notifications, 1);
    });

    test('disabled repository resolves to free', () async {
      const repository = DisabledSubscriptionRepository();
      final controller = SubscriptionController(repository: repository)
        ..start();
      addTearDown(controller.dispose);

      await pumpEventQueue();
      expect(controller.isPremium, isFalse);
    });
  });

  group('SubscriptionScope', () {
    testWidgets('propagates entitlement changes to consumers', (tester) async {
      final repository = FakeSubscriptionRepository();
      final controller = SubscriptionController(repository: repository)
        ..start();
      addTearDown(controller.dispose);
      addTearDown(repository.close);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SubscriptionScope(
            controller: controller,
            repository: repository,
            child: Builder(
              builder: (context) {
                final status = SubscriptionScope.statusOf(context);
                return Text(status.isPremium ? 'premium' : 'free');
              },
            ),
          ),
        ),
      );

      expect(find.text('free'), findsOneWidget);

      repository.emit(
        PremiumStatus(
          isPremium: true,
          lifecycle: SubscriptionLifecycle.active,
          expiresAt: future,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('premium'), findsOneWidget);

      repository.emit(PremiumStatus.free);
      await tester.pumpAndSettle();
      expect(find.text('free'), findsOneWidget);
    });

    testWidgets('a tree without the scope is never premium', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              return Text(
                SubscriptionScope.isPremiumOf(context) ? 'premium' : 'free',
              );
            },
          ),
        ),
      );
      expect(find.text('free'), findsOneWidget);
    });
  });
}
