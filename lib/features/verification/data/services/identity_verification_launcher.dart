import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the provider's hosted verification flow and notices when the user
/// comes back.
///
/// Modelled on `SpotifyAuthService`: `app_links` owns the return link, and
/// `uriLinkStream` already delivers the cold-start link, so there is no second
/// initial-link path.
///
/// The return link is a *hint*, nothing more. It carries no verdict, is not
/// authenticated, and anyone can open it. All it does is tell the app to go
/// and re-read MEVORA's own state — which is why this class exposes a bare
/// notification rather than any kind of result.
class IdentityVerificationLauncher {
  IdentityVerificationLauncher({
    Stream<Uri>? returnLinks,
    Future<bool> Function(Uri uri, {LaunchMode mode})? launch,
  }) : _launch = launch ?? launchUrl {
    _subscription = (returnLinks ?? AppLinks().uriLinkStream).listen(_onUri);
  }

  /// The deep link the backend registers with the provider as its callback.
  static const returnHost = 'verify';
  static const returnPathPrefix = '/identity';

  final Future<bool> Function(Uri uri, {LaunchMode mode}) _launch;
  StreamSubscription<Uri>? _subscription;
  final _returns = StreamController<void>.broadcast();

  /// Fires whenever the user comes back from the provider flow, however they
  /// got there. Listeners should refresh backend state; they must not treat
  /// this as success.
  Stream<void> get returns => _returns.stream;

  static bool isReturnLink(Uri uri) {
    return uri.host == returnHost && uri.path.startsWith(returnPathPrefix);
  }

  /// Opens the hosted flow in an external browser.
  ///
  /// External rather than in-app: the provider's flow needs camera access and
  /// a stable origin, and an external browser is also what lets the user
  /// finish if they background MEVORA halfway through.
  Future<bool> open(Uri verificationUrl) {
    return _launch(verificationUrl, mode: LaunchMode.externalApplication);
  }

  void _onUri(Uri uri) {
    if (isReturnLink(uri) && !_returns.isClosed) {
      _returns.add(null);
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _returns.close();
  }
}
