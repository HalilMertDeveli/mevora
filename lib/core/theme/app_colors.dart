import 'package:flutter/material.dart';

/// Mevora design tokens. Prefer [ThemeData.colorScheme] in widgets; use these
/// when defining themes or photo overlays that need stable brand values.
abstract final class AppColors {
  // —— Mevora 2.0 core palette ——
  static const Color midnight = Color(0xFF101828);
  static const Color deepNavy = Color(0xFF172033);
  static const Color warmCream = Color(0xFFF8F5EF);
  static const Color amber = Color(0xFFF4B860);
  static const Color softGreen = Color(0xFF5FAF8F);
  static const Color textSecondary = Color(0xFF667085);
  static const Color borderLight = Color(0xFFE4E7EC);

  // —— Light theme (default visual identity) ——
  /// Warm cream scaffold / page background.
  static const Color canvas = warmCream;
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF3F4F6);
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  static const Color ink = midnight;
  static const Color mutedInk = textSecondary;
  static const Color subtleInk = Color(0xFF9CA3AF);
  static const Color outline = borderLight;
  static const Color outlineStrong = Color(0xFFD1D5DB);

  /// Legacy rose aliases — kept for older call sites / gradual migration.
  static const Color rose = Color(0xFFD63384);
  static const Color roseDark = Color(0xFF9D174D);
  static const Color roseSoft = Color(0xFFFCE7F0);
  static const Color peach = Color(0xFFE8A87C);
  static const Color peachSoft = Color(0xFFFFF1E6);
  static const Color moss = softGreen;
  static const Color mossSoft = Color(0xFFE8F5EF);

  // Legacy aliases (kept for older call sites / tests).
  static const Color mulberry = rose;
  static const Color mulberryDark = roseDark;
  static const Color mulberrySoft = roseSoft;
  static const Color apricot = peach;
  static const Color apricotSoft = peachSoft;
  static const Color parchment = canvas;

  // Shared semantic colors.
  static const Color danger = Color(0xFFD64545);

  // —— Dark theme tokens ——
  static const Color background = Color(0xFF08080A);
  static const Color primaryBackground = deepNavy;
  static const Color card = Color(0xFF121216);
  static const Color elevatedCard = Color(0xFF18181E);
  static const Color secondaryCard = Color(0xFF1C1C22);
  static const Color border = Color(0xFF27272D);

  static const Color primaryText = Color(0xFFFFFFFF);
  static const Color secondaryText = Color(0xFFB4B4BC);
  static const Color secondaryTextDark = secondaryText;
  static const Color mutedText = Color(0xFF777780);

  static const Color accentPrimary = amber;
  static const Color accentSecondary = Color(0xFFE8A84A);
  static const Color darkBurgundy = deepNavy;
  static const Color deepWine = Color(0xFF1A2235);
  static const Color softPurple = Color(0xFF8B5CF6);

  static const Color success = softGreen;
  static const Color error = danger;
  static const Color warning = Color(0xFFF59E0B);

  static const Color iconMuted = Color(0xFFA1A1AA);
  static const Color glassFill = Color(0xCC121216);
  static const Color glassBorder = Color(0x14FFFFFF);

  /// Light glass / frosted surfaces for nav and overlays on light theme.
  static const Color lightGlassFill = Color(0xF2FFFFFF);
  static const Color lightGlassBorder = borderLight;

  /// Dark aliases used across existing screens — mapped to the dark palette.
  static const Color night = background;
  static const Color nightSurface = card;
  static const Color blossom = accentPrimary;

  /// Text/icons drawn on top of photos (always light for contrast).
  static const Color onMedia = primaryText;
  static const Color onMediaMuted = secondaryTextDark;

  static const LinearGradient accentGradient = LinearGradient(
    colors: [amber, Color(0xFFE8A84A)],
  );

  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [amber, Color(0xFFE8A84A), deepNavy],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient lightAccentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [amber, Color(0xFFE8C882)],
  );
}
