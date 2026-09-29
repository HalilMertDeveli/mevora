# Asset licenses

Every externally sourced asset that ships in the app bundle, where it came
from and under what terms. Original Mevora work is listed at the end. If an
asset's terms are unclear it does not ship — see "Removed".

Access date for entries added by the 2026-09-28 UI redesign: **2026-09-28**.

## Fonts

| Asset | Source | Creator | License | Used in |
|---|---|---|---|---|
| `assets/fonts/Fraunces-SemiBold.ttf` (static wght 600, opsz default) | Google Fonts API — `https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,600` → fonts.gstatic.com | Undercase Type (Phaedra Charles, Flavia Zimbardi) | SIL Open Font License 1.1 — https://openfontlicense.org | Display and headline text roles |
| `assets/fonts/Manrope-Regular.ttf` / `-Medium` / `-SemiBold` / `-Bold` (400/500/600/700) | Google Fonts API — `https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700` → fonts.gstatic.com | Mikhail Sharanda | SIL Open Font License 1.1 | All UI text |

These replace earlier subset copies of the same families that lacked
`ğ Ğ ş Ş İ ₺`, which made every Turkish word render with fallback glyphs.
The OFL permits bundling and embedding in applications; the fonts are not
sold on their own.

## Icons

| Asset | Source | License | Used in |
|---|---|---|---|
| Phosphor Icons via `phosphor_flutter` 2.1.0 | https://pub.dev/packages/phosphor_flutter · https://phosphoricons.com | MIT — Copyright (c) 2020-2021 Phosphor Icons | Every icon in the app (`lib/core/theme/mevora_icons.dart`) |

Brand glyphs from the set (Apple, Google, Spotify) are used only to label the
matching sign-in button and to attribute Spotify-sourced content, which is
how those brands ask to be referenced. Mevora does not use them as its own
marks.

## Photography

| Asset | Source | License | Status |
|---|---|---|---|
| `assets/images/portraits/mock-01.jpg` … `mock-10.jpg` | Code comment says "Unsplash License portraits" | Unsplash License (claimed) | **Pre-existing, provenance incomplete.** Per-photo source URLs and photographers were never recorded. Used only by the demo / mock discovery deck (`MevoraPhotoImages`, `MockDiscoveryDataSource`). Owner action: record the ten Unsplash URLs, or drop the portraits from the release bundle. Not changed by the redesign because removing them changes demo-mode behaviour. |

## Removed

| Asset | Why |
|---|---|
| `assets/rive/**` (15 runtime `.riv` files) and `assets/rive/Riv-files/**` (7 source files, 6.5 MB) | Rive Community downloads with no recorded creator, URL or license (Rive community files are typically CC BY 4.0, which requires attribution that was never given). They were also visually unrelated to one another (a cat, a walking figure, a rating widget). Replaced by original code-drawn Mevora motion. The `rive` runtime dependency was removed with them. |
| `assets/images/login_background.jpg` (+ `LOGIN_BACKGROUND_SOURCE.md`) | Unused since the welcome screen stopped using a photo hero. Removed from the bundle. |
| `cupertino_icons` dependency | Never referenced. |

## Original Mevora work (no third-party rights)

All drawn in Flutter code for this project, no external source:

* The Mevora mark and wordmark treatment — `lib/shared/art/mevora_mark.dart`
* Spot illustrations (halo + satellites; glyphs are Phosphor duotone, MIT) —
  `lib/shared/art/mevora_spot.dart`
* Signature motion: orbit loader, success mark, boost burst, mark intro —
  `lib/shared/art/mevora_motion.dart`
* The match moment — `lib/shared/animations/mevora_match_celebration.dart`
* Music portrait stack and genre composition — `lib/features/music/presentation/widgets/music_ui.dart`

## Not used, on purpose

No Lottie / LottieFiles content, no Figma Community files and no screenshots
from reference products (Mobbin, competitors) are in the repository. Research
references informed principles only.
