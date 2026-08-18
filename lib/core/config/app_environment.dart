/// Runtime environment for Mevora.
///
/// Dedicated Dart entrypoints select the environment. Android product
/// flavors and separate Firebase projects keep development, staging, and
/// production backends isolated.
enum AppEnvironment {
  development,
  staging,
  production,
}

extension AppEnvironmentX on AppEnvironment {
  bool get isProduction => this == AppEnvironment.production;

  bool get isDevelopment => this == AppEnvironment.development;
}
