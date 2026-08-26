import 'package:flutter/material.dart';

/// Mevora design tokens. Prefer [ThemeData.colorScheme] in widgets; use these
/// when defining themes or photo overlays that need stable brand values.
abstract final class AppColors {
  // —— Light theme (default visual identity) ——
  /// Warm off-white scaffold / page background.
  static const Color canvas = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF3F4F6);
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  static const Color ink = Color(0xFF1F1F1F);
  static const Color mutedInk = Color(0xFF6B7280);
  static const Color subtleInk = Color(0xFF9CA3AF);
  static const Color outline = Color(0xFFE5E7EB);
  static const Color outlineStrong = Color(0xFFD1D5DB);

  /// Soft rose primary for light surfaces (accessible on white).
  static const Color rose = Color(0xFFD63384);
  static const Color roseDark = Color(0xFF9D174D);
  static const Color roseSoft = Color(0xFFFCE7F0);
  static const Color peach = Color(0xFFE8A87C);
  static const Color peachSoft = Color(0xFFFFF1E6);
  static const Color moss = Color(0xFF2F6F56);
  static const Color mossSoft = Color(0xFFD1FAE5);

  // Legacy aliases (kept for older call sites / tests).
  static const Color mulberry = rose;
  static const Color mulberryDark = roseDark;
  static const Color mulberrySoft = roseSoft;
  static const Color apricot = peach;
  static const Color apricotSoft = peachSoft;
  static const Color parchment = canvas;

  // Shared semantic colors.
  static const Color danger = Color(0xFFEF4444);

  // —— Dark theme tokens (preserved) ——
  static const Color background = Color(0xFF08080A);
  static const Color primaryBackground = Color(0xFF0B0B0F);
  static const Color card = Color(0xFF121216);
  static const Color elevatedCard = Color(0xFF18181E);
  static const Color secondaryCard = Color(0xFF1C1C22);
  static const Color border = Color(0xFF27272D);

  static const Color primaryText = Color(0xFFFFFFFF);
  static const Color secondaryText = Color(0xFFB4B4BC);
  static const Color mutedText = Color(0xFF777780);

  static const Color accentPrimary = Color(0xFFFF2D8D);
  static const Color accentSecondary = Color(0xFFE91E73);
  static const Color darkBurgundy = Color(0xFF260813);
  static const Color deepWine = Color(0xFF350A1C);
  static const Color softPurple = Color(0xFF8B5CF6);

  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

  static const Color iconMuted = Color(0xFFA1A1AA);
  static const Color glassFill = Color(0xCC121216);
  static const Color glassBorder = Color(0x14FFFFFF);

  /// Light glass / frosted surfaces for nav and overlays on light theme.
  static const Color lightGlassFill = Color(0xF2FFFFFF);
  static const Color lightGlassBorder = Color(0xFFE5E7EB);

  /// Dark aliases used across existing screens — mapped to the dark palette.
  static const Color night = background;
  static const Color nightSurface = card;
  static const Color blossom = accentPrimary;

  /// Text/icons drawn on top of photos (always light for contrast).
  static const Color onMedia = primaryText;
  static const Color onMediaMuted = secondaryText;

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accentPrimary, Color(0xFFC026D3)],
  );

  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentPrimary, accentSecondary, softPurple],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient lightAccentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [rose, softPurple],
  );
}
