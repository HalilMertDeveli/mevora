package com.mevora.app

import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

/// FragmentActivity is required so Firebase Phone Auth can host the reCAPTCHA
/// WebView fallback when Play Integrity cannot verify a sideloaded/debug build.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            requestLocalNetworkAccessIfDeclared()
        }
    }

    /// Android 16+ keeps the app sandbox off local addresses such as the
    /// Firebase Emulator Suite at 10.0.2.2 until ACCESS_LOCAL_NETWORK is
    /// granted, and a fresh install or `pm clear` starts with it denied. That
    /// surfaces as firebase_auth/network-request-failed ("check your internet
    /// connection"), never as a permission error.
    ///
    /// tool/flutter_prepare.ps1 grants it on F5, but it runs before flutter
    /// installs the APK, so the first launch after an install always missed it.
    /// Only the debug manifest declares the permission, so release and profile
    /// builds never ask.
    private fun requestLocalNetworkAccessIfDeclared() {
        if (Build.VERSION.SDK_INT < 36) return
        if (checkSelfPermission(LOCAL_NETWORK) == PackageManager.PERMISSION_GRANTED) return
        val declared = packageManager
            .getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()),
            )
            .requestedPermissions
            ?.contains(LOCAL_NETWORK) == true
        if (!declared) return
        requestPermissions(arrayOf(LOCAL_NETWORK), LOCAL_NETWORK_REQUEST_CODE)
    }

    private companion object {
        const val LOCAL_NETWORK = "android.permission.ACCESS_LOCAL_NETWORK"
        const val LOCAL_NETWORK_REQUEST_CODE = 4610
    }
}
