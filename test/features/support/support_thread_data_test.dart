import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/support/data/datasources/firebase_support_data_source.dart';
import 'package:mevora/features/support/domain/models/support_message.dart';

void main() {
  group('thread mapping', () {
    test('orders replies oldest first; a pending timestamp goes last', () {
      final messages = FirebaseSupportDataSource.messagesFromDocs([
        (
          id: 'late',
          data: {
            'visibility': 'user',
            'text': 'Second',
            'authorLabel': 'Mevora Support',
            'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 3)),
          },
        ),
        (
          id: 'pending',
          data: {'visibility': 'user', 'text': 'Just sent', 'authorLabel': ''},
        ),
        (
          id: 'early',
          data: {
            'visibility': 'user',
            'text': 'First',
            'authorLabel': 'Mevora Support',
            'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
          },
        ),
      ]);

      expect(messages.map((m) => m.id), ['early', 'late', 'pending']);
      expect(messages.first.text, 'First');
      expect(messages.first.authorLabel, SupportMessage.defaultAuthorLabel);
      expect(
        messages.first.createdAt!.isAtSameMomentAs(DateTime.utc(2026, 1, 2)),
        isTrue,
      );
      expect(messages.last.createdAt, isNull);
    });

    test('drops anything not marked for the member, and empty replies', () {
      final messages = FirebaseSupportDataSource.messagesFromDocs([
        (id: 'note', data: {'visibility': 'internal', 'text': 'Staff only'}),
        (id: 'unmarked', data: {'text': 'No visibility'}),
        (id: 'blank', data: {'visibility': 'user', 'text': '   '}),
        (id: 'ok', data: {'visibility': 'user', 'text': 'Visible'}),
      ]);

      expect(messages.map((m) => m.id), ['ok']);
    });
  });

  group('ticket reply bookkeeping', () {
    test('reads the server-owned reply fields', () {
      final ticket = FirebaseSupportDataSource.ticketFromMap('t1', {
        'userId': 'u1',
        'subject': 'Help',
        'message': 'Details',
        'status': 'in_progress',
        'supportReplyCount': 2,
        'hasUnreadSupportReply': true,
        'lastSupportReplyAt': Timestamp.fromDate(DateTime.utc(2026, 1, 3)),
      });

      expect(ticket.supportReplyCount, 2);
      expect(ticket.hasUnreadSupportReply, isTrue);
      expect(
        ticket.lastSupportReplyAt!.isAtSameMomentAs(DateTime.utc(2026, 1, 3)),
        isTrue,
      );
      expect(ticket.hasSupportReply, isTrue);
    });

    test('tolerates a request nobody has answered yet', () {
      final ticket = FirebaseSupportDataSource.ticketFromMap('t1', {
        'userId': 'u1',
        'subject': 'Help',
        'message': 'Details',
        'status': 'open',
      });

      expect(ticket.supportReplyCount, 0);
      expect(ticket.hasUnreadSupportReply, isFalse);
      expect(ticket.lastSupportReplyAt, isNull);
      expect(ticket.hasSupportReply, isFalse);
    });

    test('any one reply signal is enough to count as answered', () {
      expect(
        FirebaseSupportDataSource.ticketFromMap('t', {
          'supportReplyCount': 1,
        }).hasSupportReply,
        isTrue,
      );
      expect(
        FirebaseSupportDataSource.ticketFromMap('t', {
          'hasUnreadSupportReply': true,
        }).hasSupportReply,
        isTrue,
      );
    });
  });

  group('thread query', () {
    // The rules only allow the owner to read `visibility == 'user'` thread
    // messages, and reject any query that could match other documents. The
    // query shape is therefore part of the contract.
    final source = File(
      'lib/features/support/data/datasources/firebase_support_data_source.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    test('reads the messages subcollection with the visibility filter', () {
      expect(FirebaseSupportDataSource.supportMessagesCollection, 'messages');
      expect(FirebaseSupportDataSource.userVisibility, 'user');
      expect(
        source.contains(
          '.collection(supportMessagesCollection)\n'
          "        .where('visibility', isEqualTo: userVisibility)\n"
          '        .snapshots()',
        ),
        isTrue,
      );
    });

    test('never orders server-side (there is no composite index)', () {
      final watch = source.substring(
        source.indexOf('Stream<List<SupportMessage>> watchMessages'),
        source.indexOf('static const String supportMessagesCollection'),
      );
      expect(watch.contains('orderBy'), isFalse);
    });

    test('the app never touches staff-only internal notes', () {
      final offenders = <String>[
        for (final file in Directory('lib').listSync(recursive: true))
          if (file is File &&
              file.path.endsWith('.dart') &&
              file.readAsStringSync().contains('internalNotes'))
            file.path,
      ];
      expect(offenders, isEmpty);
    });
  });
}
