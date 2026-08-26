package com.mevora.app

import io.flutter.embedding.android.FlutterFragmentActivity

/// FragmentActivity is required so Firebase Phone Auth can host the reCAPTCHA
/// WebView fallback when Play Integrity cannot verify a sideloaded/debug build.
class MainActivity : FlutterFragmentActivity()
