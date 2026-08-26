// Device/emulator smoke for chat fullscreen image viewer.
// flutter test integration_test/chat_image_viewer_smoke_test.dart -d emulator-5554

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/presentation/widgets/chat_fullscreen_image_viewer.dart';
import 'package:mevora/features/chat/presentation/widgets/chat_widgets.dart';
import 'package:mevora/l10n/app_localizations.dart';

final Uint8List _tinyPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB4, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tap chat photo opens and closes fullscreen viewer on device', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('tr'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: ListView(
            children: [
              ChatBubble(
                isMine: true,
                message: ChatMessage(
                  id: 'out',
                  senderId: 'a',
                  receiverId: 'b',
                  text: '',
                  type: MessageType.image,
                  createdAt: DateTime(2026),
                  status: MessageStatus.sent,
                  localMediaBytes: _tinyPng,
                ),
              ),
              ChatBubble(
                isMine: false,
                message: ChatMessage(
                  id: 'in',
                  senderId: 'b',
                  receiverId: 'a',
                  text: '',
                  type: MessageType.image,
                  createdAt: DateTime(2026),
                  status: MessageStatus.delivered,
                  localMediaBytes: _tinyPng,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ChatImageBody).first);
    await tester.pumpAndSettle();
    expect(find.byType(ChatFullscreenImageViewer), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(ChatFullscreenImageViewer), findsNothing);
    expect(find.byType(ChatBubble), findsNWidgets(2));

    await tester.tap(find.byType(ChatImageBody).last);
    await tester.pumpAndSettle();
    expect(find.byType(ChatFullscreenImageViewer), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ChatFullscreenImageViewer), findsNothing);
  });
}
