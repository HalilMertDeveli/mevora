import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/entities/phone_auth_state.dart';
import 'package:mevora/features/authentication/domain/entities/phone_challenge.dart';
import 'package:mevora/features/authentication/domain/usecases/auth_usecases.dart';
import 'package:mevora/features/authentication/presentation/controllers/phone_auth_controller.dart';

import '../../helpers/fake_auth.dart';

void main() {
  const challenge = PhoneChallenge(
    verificationId: 'verification-id',
    e164Phone: '+905551112233',
    maskedPhone: '+90 5•• ••• •• 33',
  );

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
    final controller = PhoneAuthController(
      sendPhoneVerificationCode: SendPhoneVerificationCode(repo),
      verifyPhoneCode: VerifyPhoneCode(repo),
      resendPhoneVerificationCode: ResendPhoneVerificationCode(repo),
      authRepository: repo,
      logger: const AppLogger(environment: AppEnvironment.development),
    );

    expect(await controller.sendCode(), isFalse);
    expect(controller.state, isA<PhoneNumberEntering>());

    controller.updateNationalNumber('5551112233');
    final sent = await controller.sendCode();
    expect(
      sent,
      isTrue,
      reason: 'state=${controller.state.runtimeType}',
    );
    expect(controller.state, isA<OtpSent>());
    expect(repo.lastSmsCode, isNull);

    expect(await controller.verify('123456'), isTrue);
    expect(controller.state, isA<PhoneAuthenticated>());
    expect(repo.lastSmsCode, '123456');
    controller.dispose();
  });
}
