import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/firebase/firebase_options_resolver.dart';
import 'package:mevora/firebase_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('android/app/google-services.json targets mevora-d6ed0', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final json = _androidJson('android/app/google-services.json');
    final project = json['project_info'] as Map<String, dynamic>;
    const options = DefaultFirebaseOptions.android;
    final client = _androidClient(json, 'com.mevora.app');

    expect(project['project_id'], 'mevora-d6ed0');
    expect(project['project_number'], options.messagingSenderId);
    expect(project['storage_bucket'], options.storageBucket);
    expect(client.appId, options.appId);
    expect(client.apiKey, options.apiKey);
  });

  test('Android flavor google-services.json matches resolver project IDs', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    _expectAndroidFlavor(
      flavor: 'development',
      environment: AppEnvironment.development,
      packageName: 'com.mevora.app',
    );
    _expectAndroidFlavor(
      flavor: 'staging',
      environment: AppEnvironment.staging,
      packageName: 'com.mevora.app.staging',
    );
    _expectAndroidFlavor(
      flavor: 'production',
      environment: AppEnvironment.production,
      packageName: 'com.mevora.app',
    );
  });

  test('ios/Runner/GoogleService-Info.plist targets mevora-d6ed0', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    _expectIosPlist(
      path: 'ios/Runner/GoogleService-Info.plist',
      environment: AppEnvironment.development,
      bundleId: 'com.mevora.app',
    );
  });

  test('iOS flavor plists match resolver project IDs and bundle ids', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    _expectIosPlist(
      path: 'ios/flavors/development/GoogleService-Info.plist',
      environment: AppEnvironment.development,
      bundleId: 'com.mevora.app',
    );
    _expectIosPlist(
      path: 'ios/flavors/staging/GoogleService-Info.plist',
      environment: AppEnvironment.staging,
      bundleId: 'com.mevora.app.staging',
    );
    _expectIosPlist(
      path: 'ios/flavors/production/GoogleService-Info.plist',
      environment: AppEnvironment.production,
      bundleId: 'com.mevora.app',
    );
  });

  test('Xcode PRODUCT_BUNDLE_IDENTIFIER matches flavor plists when flavored', () {
    final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

    expect(pbxproj.contains('name = "Debug-development"'), isTrue);
    expect(
      pbxproj.contains('PRODUCT_BUNDLE_IDENTIFIER = com.mevora.app.dev'),
      isTrue,
    );
    expect(
      pbxproj.contains('PRODUCT_BUNDLE_IDENTIFIER = com.mevora.app.staging'),
      isTrue,
    );
  });
}

void _expectAndroidFlavor({
  required String flavor,
  required AppEnvironment environment,
  required String packageName,
}) {
  final json = _androidJson('android/app/src/$flavor/google-services.json');
  final project = json['project_info'] as Map<String, dynamic>;
  final client = _androidClient(json, packageName);
  final options = FirebaseOptionsResolver.resolve(environment);

  expect(project['project_id'], options.projectId);
  expect(project['project_number'], options.messagingSenderId);
  expect(project['storage_bucket'], options.storageBucket);
  expect(client.appId, options.appId);
  expect(client.apiKey, options.apiKey);
}

void _expectIosPlist({
  required String path,
  required AppEnvironment environment,
  required String bundleId,
}) {
  final plist = File(path).readAsStringSync();
  final options = FirebaseOptionsResolver.resolve(environment);

  expect(_plistString(plist, 'PROJECT_ID'), options.projectId);
  expect(_plistString(plist, 'GOOGLE_APP_ID'), options.appId);
  expect(_plistString(plist, 'GCM_SENDER_ID'), options.messagingSenderId);
  expect(_plistString(plist, 'STORAGE_BUCKET'), options.storageBucket);
  expect(_plistString(plist, 'BUNDLE_ID'), bundleId);
  expect(options.iosBundleId, bundleId);
  expect(_plistString(plist, 'API_KEY'), options.apiKey);
}

Map<String, dynamic> _androidJson(String path) {
  return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
}

({String appId, String apiKey}) _androidClient(
  Map<String, dynamic> json,
  String packageName,
) {
  final clients = json['client'] as List<dynamic>;
  Map<String, dynamic>? matched;
  for (final raw in clients) {
    final client = raw as Map<String, dynamic>;
    final info = client['client_info'] as Map<String, dynamic>;
    final android = info['android_client_info'] as Map<String, dynamic>;
    if (android['package_name'] == packageName) {
      matched = client;
      break;
    }
  }
  expect(matched, isNotNull, reason: 'missing Android client $packageName');
  final info = matched!['client_info'] as Map<String, dynamic>;
  final apiKey = ((matched['api_key'] as List<dynamic>).first
      as Map<String, dynamic>)['current_key'] as String;
  return (
    appId: info['mobilesdk_app_id'] as String,
    apiKey: apiKey,
  );
}

String _plistString(String plist, String key) {
  final match = RegExp(
    '<key>$key</key>\\s*<string>([^<]+)</string>',
  ).firstMatch(plist);
  expect(match, isNotNull, reason: 'missing plist key $key');
  return match!.group(1)!;
}
