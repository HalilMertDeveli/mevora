import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/routing/app_routes.dart';

void main() {
  test('match list → chat path uses stable matchId route', () {
    const matchId = 'CKLxiWTBtoXik888Wzqicqeuj6t2_F7CYZWNik3RGv3xQTZRLKWsMnTd2';
    expect(AppRoutes.chat, '/chat/:matchId');
    expect(AppRoutes.chatPath(matchId), '/chat/$matchId');
    expect(AppRoutes.matches, isNotEmpty);
  });
}
