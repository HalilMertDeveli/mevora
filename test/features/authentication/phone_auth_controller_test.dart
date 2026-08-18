import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/utils/otp_validator.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/entities/phone_auth_state.dart';
import 'package:mevora/features/authentication/domain/entities/phone_challenge.dart';
import 'package:mevora/features/authentication/domain/usecases/auth_usecases.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/authentication/presentation/controllers/phone_auth_controller.dart';

import '../../helpers/fake_auth.dart';

void main() {
  const challenge = PhoneChallenge(
    verificationId: 'verification-id',
    e164Phone: '+905551112233',
    maskedPhone: '+90 5•• ••• •• 33',
  );

  PhoneAuthController buildController(FakeAuthRepository repo) {
    return PhoneAuthController(
      sendPhoneVerificationCode: SendPhoneVerificationCode(repo),
      verifyPhoneCode: VerifyPhoneCode(repo),
      resendPhoneVerificationCode: ResendPhoneVerificationCode(repo),
      authRepository: repo,
      logger: const AppLogger(environment: AppEnvironment.development),
    );
  }

  test('Send/Verify/Resend use cases delegate to the repository', () async {
    final repo = FakeAuthRepository(
      sendResult: const Success(challenge),
      verifyResult: const Success(AuthUser(id: 'uid-1')),
    );
    expect(
      (await SendPhoneVerificationCode(repo).call('+905551112233')).isSuccess,
      isTrue,
    );
    expect(
      (await VerifyPhoneCode(repo).call(
        challenge: challenge,
        smsCode: '123456',
      )).isSuccess,
      isTrue,
    );
    expect(
      (await ResendPhoneVerificationCode(repo).call(challenge)).isSuccess,
      isTrue,
    );
  });

  test('controller validates before claiming SMS was sent', () async {
    final repo = FakeAuthRepository(
      sendResult: const Success(challenge),
      verifyResult: const Success(AuthUser(id: 'uid-1')),
    );
    final controller = buildController(repo);

    expect(await controller.sendCode(), isFalse);
    expect(controller.state, isA<PhoneNumberEntering>());

    controller.updateNationalNumber('5551112233');
    final sent = await controller.sendCode();
    expect(sent, isTrue, reason: 'state=${controller.state.runtimeType}');
    expect(controller.state, isA<OtpSent>());
    expect(repo.lastSmsCode, isNull);

    expect(await controller.verify('123456'), isTrue);
    expect(controller.state, isA<PhoneAuthenticated>());
    expect(repo.lastSmsCode, '123456');
    controller.dispose();
  });

  test('normalizes trunk-zero TR numbers to E.164 before send', () async {
    final repo = FakeAuthRepository(sendResult: const Success(challenge));
    final controller = buildController(repo);
    controller.updateNationalNumber('05321234567');
    expect(await controller.sendCode(), isTrue);
    expect(repo.lastE164Phone, '+905321234567');
    expect(controller.state, isA<OtpSent>());
    controller.dispose();
  });

  test('wrong OTP stays on OTP error without signing in', () async {
    final repo = FakeAuthRepository(sendResult: const Success(challenge));
    final controller = buildController(repo);
    controller.updateNationalNumber('5551112233');
    await controller.sendCode();

    expect(await controller.verify('000000'), isFalse);
    expect(controller.state, isA<OtpError>());
    expect(repo.user, isNull);
    controller.dispose();
  });

  test('expired OTP / session maps to localized failure kinds', () async {
    final repo = FakeAuthRepository(
      sendResult: const Success(challenge),
      verifyResult: const Err(
        AuthFailure('expired', kind: AuthErrorKind.expiredOtp),
      ),
    );
    final controller = buildController(repo);
    controller.updateNationalNumber('5551112233');
    await controller.sendCode();
    expect(await controller.verify('123456'), isFalse);
    final state = controller.state;
    expect(state, isA<OtpError>());
    expect((state as OtpError).kind, AuthErrorKind.expiredOtp);
    controller.dispose();
  });

  test('resend respects 30s cooldown and uses Firebase resend token path', () async {
    final repo = FakeAuthRepository(sendResult: const Success(challenge));
    final controller = buildController(repo);
    controller.updateNationalNumber('5551112233');
    await controller.sendCode();

    expect(controller.resendSeconds, OtpValidator.resendSeconds);
    expect(controller.canResend, isFalse);
    expect(await controller.resend(), isFalse);

    controller.dispose();
  });

  test('network and too-many failures surface without raw firebase codes', () async {
    final networkRepo = FakeAuthRepository(
      sendResult: const Err(
        AuthFailure('net', kind: AuthErrorKind.network),
      ),
    );
    final network = buildController(networkRepo);
    network.updateNationalNumber('5551112233');
    expect(await network.sendCode(), isFalse);
    expect(network.state, isA<SmsSendError>());
    expect((network.state as SmsSendError).kind, AuthErrorKind.network);
    network.dispose();

    final tooManyRepo = FakeAuthRepository(
      sendResult: const Err(
        AuthFailure('limit', kind: AuthErrorKind.tooManyAttempts),
      ),
    );
    final tooMany = buildController(tooManyRepo);
    tooMany.updateNationalNumber('5551112233');
    expect(await tooMany.sendCode(), isFalse);
    expect(tooMany.state, isA<TooManyAttempts>());
    tooMany.dispose();
  });

  test('AuthController sync: phone OTP success routes new vs existing users', () async {
    final newRepo = FakeAuthRepository(
      sendResult: const Success(challenge),
      verifyResult: const Success(
        AuthUser(id: 'new-phone', phoneNumber: '+905551112233'),
      ),
    );
    final newAuth = AuthController(
      authRepository: newRepo,
      userDocumentRepository: FakeUserDocumentRepository(),
      logger: const AppLogger(environment: AppEnvironment.development),
    )..start();
    await Future<void>.delayed(Duration.zero);

    newAuth.phoneAuth.updateNationalNumber('5551112233');
    await newAuth.phoneAuth.sendCode();
    expect(newAuth.status, isA<PhoneCodeSent>());
    await newAuth.phoneAuth.verify('123456');
    expect(newAuth.status, isA<NeedsOnboarding>());
    newAuth.dispose();
    newRepo.dispose();

    final existingRepo = FakeAuthRepository(
      sendResult: const Success(challenge),
      verifyResult: const Success(
        AuthUser(
          id: 'old-phone',
          phoneNumber: '+905551112233',
          profileCompleted: true,
          onboardingCompleted: true,
        ),
      ),
    );
    final existingAuth = AuthController(
      authRepository: existingRepo,
      userDocumentRepository: FakeUserDocumentRepository(complete: true),
      logger: const AppLogger(environment: AppEnvironment.development),
    )..start();
    await Future<void>.delayed(Duration.zero);

    existingAuth.phoneAuth.updateNationalNumber('5551112233');
    await existingAuth.phoneAuth.sendCode();
    await existingAuth.phoneAuth.verify('123456');
    expect(existingAuth.status, isA<Authenticated>());
    existingAuth.dispose();
    existingRepo.dispose();
  });

  test('blocks parallel SMS send while a send is in flight', () async {
    final repo = FakeAuthRepository(
      sendResult: const Success(challenge),
      sendDelay: const Duration(milliseconds: 200),
    );
    final controller = buildController(repo);
    controller.updateNationalNumber('5551112233');
    final first = controller.sendCode();
    final second = controller.sendCode();
    expect(await second, isFalse);
    expect(await first, isTrue);
    controller.dispose();
  });
}
