import 'package:flutter/material.dart';

/// Mevora colour tokens.
///
/// Widgets read colours from the theme — `Theme.of(context).colorScheme` for
/// the Material roles and `context.palette` ([MevoraPalette]) for Mevora's own
/// semantic roles (like, match, compatibility, music, humor, premium …).
/// The constants below exist to *build* those themes, and for the few places
/// that draw on top of photography, where the colour must not follow the
/// theme ([onMedia], [scrim]).
///
/// See docs/ui/DESIGN_SYSTEM.md for the reasoning behind each value.
abstract final class AppColors {
  // —— Reference palette ——————————————————————————————————————————————
  // Warm, paper-and-ink neutrals with one ember accent. Every text/background
  // pair used by the semantic roles below meets WCAG AA (4.5:1) for body text.

  /// Warm near-black with a hint of aubergine. Primary ink.
  static const Color ink = Color(0xFF1D1A22);
  static const Color ink80 = Color(0xFF3A3540);
  static const Color ink60 = Color(0xFF5E5866);
  static const Color ink45 = Color(0xFF726B79);
  static const Color ink30 = Color(0xFFA59EAB);

  /// Linen — the page. Warmer than white so photography reads as the subject.
  static const Color linen = Color(0xFFFAF6F1);
  static const Color paper = Color(0xFFFFFFFF);
  static const Color sand = Color(0xFFF2ECE4);
  static const Color sandDeep = Color(0xFFE9E1D7);
  static const Color stone = Color(0xFFE5DCD1);
  static const Color stoneDeep = Color(0xFFD3C7B9);

  /// Ember — Mevora's accent: warm, human, deliberately not a dating-app red.
  static const Color ember = Color(0xFFC4513A);
  static const Color emberDeep = Color(0xFFA93F2B);
  static const Color emberSoft = Color(0xFFFBE7E0);
  static const Color emberInk = Color(0xFF6E2717);

  /// Sage — "why you fit". Used for compatibility reasoning only.
  static const Color sage = Color(0xFF2F7A6B);
  static const Color sageSoft = Color(0xFFE2F0EB);
  static const Color sageInk = Color(0xFF173F37);

  /// Dusk — the music signal.
  static const Color dusk = Color(0xFF5B4E9E);
  static const Color duskSoft = Color(0xFFECE9F7);
  static const Color duskInk = Color(0xFF2E2560);

  /// Marigold — the humor signal.
  static const Color marigold = Color(0xFFB7791F);
  static const Color marigoldSoft = Color(0xFFFBF0DA);
  static const Color marigoldInk = Color(0xFF5E3D0B);

  /// Brass — premium. Used as a thin accent on ink, never as a gold wash.
  static const Color brass = Color(0xFFB98B3E);
  static const Color brassSoft = Color(0xFFF6EEDD);
  static const Color brassInk = Color(0xFF6B4E1A);

  /// Rose — the moment two people like each other. Match only.
  static const Color rose = Color(0xFFC8446A);
  static const Color roseSoft = Color(0xFFFBE4EB);

  static const Color success = Color(0xFF2E7D5B);
  static const Color successSoft = Color(0xFFE1F2E9);
  static const Color warning = Color(0xFFA86A12);
  static const Color warningSoft = Color(0xFFFCEFD9);
  static const Color error = Color(0xFFC2362F);
  static const Color errorSoft = Color(0xFFFBE4E2);
  static const Color info = Color(0xFF3B6EA8);
  static const Color infoSoft = Color(0xFFE3ECF7);

  // —— Dark reference values (kept coherent; the app ships light) ————————
  static const Color night = Color(0xFF131116);
  static const Color nightSurface = Color(0xFF1C1A20);
  static const Color nightElevated = Color(0xFF25222A);
  static const Color nightMuted = Color(0xFF2C2931);
  static const Color nightBorder = Color(0xFF3A3640);
  static const Color nightInk = Color(0xFFF5F1EC);
  static const Color nightInkMuted = Color(0xFFBDB6C2);
  static const Color nightInkSubtle = Color(0xFF8D8693);
  static const Color emberNight = Color(0xFFE2735B);

  // —— Media overlays (theme-independent) ——————————————————————————————
  /// Text and icons drawn on photography.
  static const Color onMedia = Color(0xFFFFFFFF);
  static const Color onMediaMuted = Color(0xE6FFFFFF);

  /// Base colour for photo scrims.
  static const Color scrim = Color(0xFF0E0C10);

  /// Translucent fill for controls that sit on photography.
  static const Color mediaControl = Color(0x52000000);
  static const Color mediaControlBorder = Color(0x33FFFFFF);
}

/// Mevora's semantic colour roles that Material's [ColorScheme] has no slot
/// for. Read with `context.palette`.
@immutable
class MevoraPalette extends ThemeExtension<MevoraPalette> {
  const MevoraPalette({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.borderStrong,
    required this.divider,
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.error,
    required this.errorContainer,
    required this.info,
    required this.infoContainer,
    required this.like,
    required this.match,
    required this.matchContainer,
    required this.compatibility,
    required this.compatibilityContainer,
    required this.onCompatibilityContainer,
    required this.music,
    required this.musicContainer,
    required this.onMusicContainer,
    required this.humor,
    required this.humorContainer,
    required this.onHumorContainer,
    required this.premium,
    required this.premiumSurface,
    required this.onPremiumSurface,
    required this.premiumContainer,
    required this.onPremiumContainer,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceMuted;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color border;
  final Color borderStrong;
  final Color divider;
  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color error;
  final Color errorContainer;
  final Color info;
  final Color infoContainer;
  final Color like;
  final Color match;
  final Color matchContainer;
  final Color compatibility;
  final Color compatibilityContainer;
  final Color onCompatibilityContainer;
  final Color music;
  final Color musicContainer;
  final Color onMusicContainer;
  final Color humor;
  final Color humorContainer;
  final Color onHumorContainer;

  /// Premium accent (brass) — thin rules, icons, a single highlight.
  final Color premium;

  /// The ink surface premium content sits on.
  final Color premiumSurface;
  final Color onPremiumSurface;
  final Color premiumContainer;
  final Color onPremiumContainer;

  static const MevoraPalette light = MevoraPalette(
    background: AppColors.linen,
    surface: AppColors.paper,
    surfaceElevated: AppColors.paper,
    surfaceMuted: AppColors.sand,
    textPrimary: AppColors.ink,
    textSecondary: AppColors.ink60,
    textTertiary: AppColors.ink45,
    border: AppColors.stone,
    borderStrong: AppColors.stoneDeep,
    divider: AppColors.sandDeep,
    success: AppColors.success,
    successContainer: AppColors.successSoft,
    warning: AppColors.warning,
    warningContainer: AppColors.warningSoft,
    error: AppColors.error,
    errorContainer: AppColors.errorSoft,
    info: AppColors.info,
    infoContainer: AppColors.infoSoft,
    like: AppColors.ember,
    match: AppColors.rose,
    matchContainer: AppColors.roseSoft,
    compatibility: AppColors.sage,
    compatibilityContainer: AppColors.sageSoft,
    onCompatibilityContainer: AppColors.sageInk,
    music: AppColors.dusk,
    musicContainer: AppColors.duskSoft,
    onMusicContainer: AppColors.duskInk,
    humor: AppColors.marigold,
    humorContainer: AppColors.marigoldSoft,
    onHumorContainer: AppColors.marigoldInk,
    premium: AppColors.brass,
    premiumSurface: AppColors.ink,
    onPremiumSurface: AppColors.linen,
    premiumContainer: AppColors.brassSoft,
    onPremiumContainer: AppColors.brassInk,
  );

  static const MevoraPalette dark = MevoraPalette(
    background: AppColors.night,
    surface: AppColors.nightSurface,
    surfaceElevated: AppColors.nightElevated,
    surfaceMuted: AppColors.nightMuted,
    textPrimary: AppColors.nightInk,
    textSecondary: AppColors.nightInkMuted,
    textTertiary: AppColors.nightInkSubtle,
    border: AppColors.nightBorder,
    borderStrong: Color(0xFF4A4550),
    divider: AppColors.nightMuted,
    success: Color(0xFF6BBF96),
    successContainer: Color(0xFF1C3328),
    warning: Color(0xFFE0A24A),
    warningContainer: Color(0xFF3A2A12),
    error: Color(0xFFEF7A72),
    errorContainer: Color(0xFF3D1B19),
    info: Color(0xFF86A9D6),
    infoContainer: Color(0xFF1B2A3D),
    like: AppColors.emberNight,
    match: Color(0xFFE27A97),
    matchContainer: Color(0xFF3D1C27),
    compatibility: Color(0xFF6FB8A7),
    compatibilityContainer: Color(0xFF1A322C),
    onCompatibilityContainer: Color(0xFFCBE8DF),
    music: Color(0xFFA599E0),
    musicContainer: Color(0xFF262143),
    onMusicContainer: Color(0xFFDCD6F7),
    humor: Color(0xFFE0A850),
    humorContainer: Color(0xFF382A12),
    onHumorContainer: Color(0xFFF6E2BD),
    premium: Color(0xFFD9B26C),
    premiumSurface: AppColors.nightElevated,
    onPremiumSurface: AppColors.nightInk,
    premiumContainer: Color(0xFF34291A),
    onPremiumContainer: Color(0xFFF1DDB5),
  );

  @override
  MevoraPalette copyWith() => this;

  @override
  MevoraPalette lerp(ThemeExtension<MevoraPalette>? other, double t) {
    if (other is! MevoraPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return MevoraPalette(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceElevated: l(surfaceElevated, other.surfaceElevated),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      divider: l(divider, other.divider),
      success: l(success, other.success),
      successContainer: l(successContainer, other.successContainer),
      warning: l(warning, other.warning),
      warningContainer: l(warningContainer, other.warningContainer),
      error: l(error, other.error),
      errorContainer: l(errorContainer, other.errorContainer),
      info: l(info, other.info),
      infoContainer: l(infoContainer, other.infoContainer),
      like: l(like, other.like),
      match: l(match, other.match),
      matchContainer: l(matchContainer, other.matchContainer),
      compatibility: l(compatibility, other.compatibility),
      compatibilityContainer: l(
        compatibilityContainer,
        other.compatibilityContainer,
      ),
      onCompatibilityContainer: l(
        onCompatibilityContainer,
        other.onCompatibilityContainer,
      ),
      music: l(music, other.music),
      musicContainer: l(musicContainer, other.musicContainer),
      onMusicContainer: l(onMusicContainer, other.onMusicContainer),
      humor: l(humor, other.humor),
      humorContainer: l(humorContainer, other.humorContainer),
      onHumorContainer: l(onHumorContainer, other.onHumorContainer),
      premium: l(premium, other.premium),
      premiumSurface: l(premiumSurface, other.premiumSurface),
      onPremiumSurface: l(onPremiumSurface, other.onPremiumSurface),
      premiumContainer: l(premiumContainer, other.premiumContainer),
      onPremiumContainer: l(onPremiumContainer, other.onPremiumContainer),
    );
  }
}

extension MevoraPaletteContext on BuildContext {
  /// Mevora's semantic colours for the current theme.
  MevoraPalette get palette =>
      Theme.of(this).extension<MevoraPalette>() ?? MevoraPalette.light;
}
