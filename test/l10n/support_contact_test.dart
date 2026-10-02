import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// The address members are told to write to — in the app and on the public
/// pages Google Play links to (privacy, account deletion, child safety). It
/// used to be the owner's personal mailbox; a banned member's sign-in error
/// showed it. All of these must name the same support address.
const _supportEmail = 'destek@mevora.com';

void main() {
  for (final code in ['tr', 'en']) {
    test('in-app contact texts name the support address ($code)', () {
      final l10n = lookupAppLocalizations(Locale(code));

      for (final text in [
        l10n.authDisabled,
        l10n.authBanned,
        l10n.termsContactBody,
        l10n.privacyContactBody,
      ]) {
        expect(text, contains(_supportEmail));
        expect(text, isNot(contains('gmail.com')));
      }
    });
  }

  test('the public pages write to the support address and nowhere else', () {
    final pages = Directory('hosting/public')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.html'))
        .toList();
    expect(pages, isNotEmpty);

    final mailto = RegExp(r'mailto:([^"?]+)');
    var links = 0;
    for (final page in pages) {
      final html = page.readAsStringSync();
      expect(html, isNot(contains('gmail.com')), reason: page.path);
      for (final match in mailto.allMatches(html)) {
        links += 1;
        expect(match.group(1), _supportEmail, reason: page.path);
      }
    }
    // The pages that must carry a contact do: privacy, terms, deletion,
    // child safety, guidelines, help and the landing page.
    expect(links, greaterThanOrEqualTo(7));
  });

  test('the strings the merge tool writes back agree with the app', () {
    // tool/merge_support_l10n.dart copies these files over the ARB entries; a
    // stale address here would come back on the next merge.
    for (final name in ['tool/support_l10n_tr.json', 'tool/support_l10n_en.json']) {
      final source = File(name).readAsStringSync();
      expect(source, contains(_supportEmail), reason: name);
      expect(source, isNot(contains('gmail.com')), reason: name);
    }
  });
}
