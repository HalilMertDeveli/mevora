import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/features/chat/presentation/chat_strings.dart';
import 'package:mevora/features/calls/presentation/call_strings.dart';

/// Maps backend codes to Turkish copy. Never forwards SDK error strings.
abstract final class SocialErrorMapper {
  static Failure map(Object error, {String? code}) {
    final resolved = (code ?? _codeOf(error) ?? '').toLowerCase();
    return switch (resolved) {
      'unauthenticated' => const AuthzFailure(ChatStrings.needSignIn),
      'self' => const ValidationFailure(ChatStrings.cannotMessageSelf),
      'blocked' => const AuthzFailure(ChatStrings.blockedInteraction),
      'inactive-match' ||
      'unmatched' => const AuthzFailure(ChatStrings.matchInactive),
      'not-matched' => const AuthzFailure(ChatStrings.notMatched),
      'already-swiped' => const ValidationFailure(ChatStrings.alreadySwiped),
      'busy' => const AuthzFailure(CallStrings.userBusy),
      'not-configured' => const UnexpectedFailure(CallStrings.notConfigured),
      'permission-denied' => const PermissionFailure(ChatStrings.notAllowed),
      'not-found' => const AuthzFailure(ChatStrings.notFound),
      'unavailable' ||
      'network' => const NetworkFailure(ChatStrings.network),
      'camera-denied' => const PermissionFailure(CallStrings.cameraDenied),
      'mic-denied' => const PermissionFailure(CallStrings.micDenied),
      'unstable' => const NetworkFailure(CallStrings.unstable),
      _ => _turkishUnknown(error),
    };
  }

  static Failure _turkishUnknown(Object error) {
    final mapped = FailureMapper.from(error);
    if (mapped is AuthzFailure ||
        mapped is ValidationFailure ||
        mapped is PermissionFailure ||
        mapped is NetworkFailure) {
      return mapped;
    }
    return const UnexpectedFailure(ChatStrings.generic);
  }

  static String? _codeOf(Object error) {
    try {
      final dynamic value = error;
      final message = value.message;
      if (message is String && message.isNotEmpty) {
        return message;
      }
      final code = value.code;
      if (code is String) {
        return code;
      }
    } on Object {
      return null;
    }
    return null;
  }
}
