import 'package:flutter/material.dart';

/// Mevora design tokens. Prefer [ThemeData.colorScheme] in widgets; use these
/// when defining themes or photo overlays that need stable brand values.
abstract final class AppColors {
  // Legacy light palette (unchanged semantics for light theme).
  static const Color mulberry = Color(0xFF5C2E62);
  static const Color mulberryDark = Color(0xFF3D1844);
  static const Color mulberrySoft = Color(0xFFEBD6EF);
  static const Color apricot = Color(0xFFC47B3A);
  static const Color apricotSoft = Color(0xFFF6E1CC);
  static const Color moss = Color(0xFF2F6F56);
  static const Color parchment = Color(0xFFF7F3F0);
  static const Color ink = Color(0xFF1C1420);
  static const Color mutedInk = Color(0xFF6E6572);
  static const Color outline = Color(0xFFD9CFC8);

  // Shared semantic colors.
  static const Color danger = Color(0xFFEF4444);

  // Mevora Dark — primary visual identity.
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

  /// Dark aliases used across existing screens — mapped to the new palette.
  static const Color night = background;
  static const Color nightSurface = card;
  static const Color blossom = accentPrimary;

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accentPrimary, Color(0xFFC026D3)],
  );

  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentPrimary, accentSecondary, softPurple],
    stops: [0.0, 0.55, 1.0],
  );
}
