import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/presentation/widgets/chat_fullscreen_image_viewer.dart';
import 'package:mevora/features/chat/presentation/widgets/chat_widgets.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// 1x1 PNG (black pixel).
final Uint8List _tinyPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB4, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Widget _app(Widget home) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('tr'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: home,
  );
}

void main() {
  test('resolveProvider prefers memory bytes over url', () {
    final provider = ChatFullscreenImageViewer.resolveProvider(
      url: 'https://example.com/x.jpg',
      bytes: _tinyPng,
    );
    expect(provider, isA<MemoryImage>());
  });

  test('resolveProvider returns null for empty sources', () {
    expect(
      ChatFullscreenImageViewer.resolveProvider(url: null, bytes: null),
      isNull,
    );
    expect(
      ChatFullscreenImageViewer.resolveProvider(url: '', bytes: const []),
      isNull,
    );
    expect(
      ChatFullscreenImageViewer.resolveProvider(url: 'mock://demo', bytes: null),
      isNull,
    );
  });

  test('resolveProvider accepts https urls', () {
    final provider = ChatFullscreenImageViewer.resolveProvider(
      url: 'https://example.com/photo.jpg',
    );
    expect(provider, isA<NetworkImage>());
  });

  testWidgets('tapping image bubble opens fullscreen viewer', (tester) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ChatBubble(
            isMine: true,
            message: ChatMessage(
              id: 'img-1',
              senderId: 'a',
              receiverId: 'b',
              text: '',
              type: MessageType.image,
              createdAt: DateTime(2026),
              status: MessageStatus.sent,
              localMediaBytes: _tinyPng,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ChatFullscreenImageViewer), findsNothing);
    await tester.tap(find.byType(ChatImageBody));
    await tester.pumpAndSettle();

    expect(find.byType(ChatFullscreenImageViewer), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('incoming image also opens viewer', (tester) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ChatBubble(
            isMine: false,
            message: ChatMessage(
              id: 'img-2',
              senderId: 'b',
              receiverId: 'a',
              text: '',
              type: MessageType.image,
              createdAt: DateTime(2026),
              status: MessageStatus.delivered,
              localMediaBytes: _tinyPng,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(ChatImageBody));
    await tester.pumpAndSettle();
    expect(find.byType(ChatFullscreenImageViewer), findsOneWidget);
  });

  testWidgets('close button pops viewer and leaves chat mounted', (tester) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ChatBubble(
            isMine: true,
            message: ChatMessage(
              id: 'img-3',
              senderId: 'a',
              receiverId: 'b',
              text: '',
              type: MessageType.image,
              createdAt: DateTime(2026),
              status: MessageStatus.sent,
              localMediaBytes: _tinyPng,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(ChatImageBody));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(ChatFullscreenImageViewer), findsNothing);
    expect(find.byType(ChatBubble), findsOneWidget);
  });

  testWidgets('system back closes viewer', (tester) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ChatBubble(
            isMine: true,
            message: ChatMessage(
              id: 'img-4',
              senderId: 'a',
              receiverId: 'b',
              text: '',
              type: MessageType.image,
              createdAt: DateTime(2026),
              status: MessageStatus.sent,
              localMediaBytes: _tinyPng,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(ChatImageBody));
    await tester.pumpAndSettle();

    final popped = await tester.binding.handlePopRoute();
    expect(popped, isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(ChatFullscreenImageViewer), findsNothing);
  });

  testWidgets('missing media does not open viewer', (tester) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ChatBubble(
            isMine: true,
            message: ChatMessage(
              id: 'img-5',
              senderId: 'a',
              receiverId: 'b',
              text: '',
              type: MessageType.image,
              createdAt: DateTime(2026),
              status: MessageStatus.sent,
              isEncrypted: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.image_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(ChatFullscreenImageViewer), findsNothing);
  });

  testWidgets('viewer shows error UI for invalid image bytes', (tester) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ChatFullscreenImageViewer(
            imageProvider: MemoryImage(Uint8List.fromList(const [1, 2, 3, 4])),
          ),
        ),
      ),
    );
    await tester.pump();
    // Decode failure is async; drain frames and ignore reported image errors.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException();
    }

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(
      find.text(lookupAppLocalizations(const Locale('tr')).retry),
      findsOneWidget,
    );
  });
}
