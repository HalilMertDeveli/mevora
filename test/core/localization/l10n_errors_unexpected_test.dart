import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Seen on a Turkish phone with no connection: "Picks'ini yükleyemedik." and,
/// under it, "An unexpected error occurred." — the generic failure's English
/// text shown as it was.
void main() {
  final tr = lookupAppLocalizations(const Locale('tr'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('a failure nothing is known about is said in the app language', () {
    final failure = FailureMapper.from(StateError('socket closed'));

    expect(failure.message, FailureMapper.unexpectedMessage);
    expect(L10nErrors.message(tr, failure.message), tr.somethingWentWrong);
    expect(L10nErrors.message(tr, failure.message), 'Bir şeyler ters gitti');
    expect(L10nErrors.message(en, failure.message), en.somethingWentWrong);
  });

  test('messages that are already copy still pass through', () {
    expect(L10nErrors.message(tr, 'Özel bir mesaj'), 'Özel bir mesaj');
    expect(L10nErrors.message(tr, null), tr.somethingWentWrong);
  });
}
