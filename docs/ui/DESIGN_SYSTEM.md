# Mevora Design System

Mevora should feel like a thoughtful introduction, not a slot machine. Every
screen answers one question for the person using it; the one screen that
matters most — Discover — answers *"why is Mevora showing me this person?"*.

The system lives in code. The living style guide is the debug route
`/debug/design-system` (`lib/core/presentation/pages/design_system_page.dart`):
every token and component rendered by the real theme on one scrolling page.

## Principles

1. **The person is the subject.** Photography is full-bleed and unobstructed;
   UI steps back (linen page, one accent) so faces carry the colour.
2. **Reasoning before scoring.** Compatibility is shown as words and signals
   first; the number is a quiet ring beside them, never a headline.
3. **One primary action per view.** Ember is spent on exactly one thing.
4. **Warm, not loud.** Paper-and-ink neutrals, a serif for human moments,
   no neon, no gradient washes, no glass stacks.
5. **Motion explains.** Things move to show state, hierarchy, feedback or
   completion. Nothing loops for decoration; reduced-motion is honoured.
6. **Utility screens are calmer.** Settings, privacy and account screens use
   plain grouped lists; expressive treatment is reserved for discovery,
   profiles, matches and moments.

## Colour

Defined in `lib/core/theme/app_colors.dart`. Widgets never use raw hex: they
read `Theme.of(context).colorScheme` for Material roles and
`context.palette` (`MevoraPalette`, a `ThemeExtension`) for Mevora's roles.

| Role | Light | Use |
|---|---|---|
| `background` | Linen `#FAF6F1` | The page |
| `surface` / `surfaceElevated` | Paper `#FFFFFF` | Cards, groups, sheets |
| `surfaceMuted` | Sand `#F2ECE4` | Quiet containers, tracks, placeholders |
| `textPrimary` | Ink `#1D1A22` | Body text, icons (15.9:1 on linen) |
| `textSecondary` | `#5E5866` | Supporting text (6.4:1) |
| `textTertiary` | `#726B79` | Captions, meta (4.8:1) |
| `border` / `borderStrong` / `divider` | Stone `#E5DCD1` / `#D3C7B9` / `#E9E1D7` | Hairlines |
| `primary` (like) | Ember `#C4513A` | The one primary action; connect (white text 4.6:1) |
| `compatibility` | Sage `#2F7A6B` | "Why you fit" — reasons, rings, verified |
| `music` | Dusk `#5B4E9E` | The music signal |
| `humor` | Marigold `#B7791F` | The humor signal |
| `match` | Rose `#C8446A` | The mutual-like moment and likes only |
| `premium` | Brass `#B98B3E` on `premiumSurface` Ink | Premium, as a thin accent — never a gold wash |
| `success` / `warning` / `error` / `info` | `#2E7D5B` / `#A86A12` / `#C2362F` / `#3B6EA8` | Status, each with a `…Container` |

Each signal colour has a soft container and an on-container ink
(`compatibilityContainer` / `onCompatibilityContainer`, …). `MevoraTone`
(`lib/shared/widgets/mevora_pill.dart`) resolves a tone to all three, so pills,
badges, banners and meters speak the same colour language.

**Why ember, not red or yellow:** dating apps own red-pink (Tinder) and yellow
(Bumble). Ember is warm and human without borrowing either, and pairs with a
serif for an editorial feel that is not Hinge's black-and-white.

A dark palette is defined and kept coherent (`MevoraPalette.dark`), but the
app ships `ThemeMode.light`.

## Typography

`lib/core/theme/app_typography.dart`. Two families, both SIL OFL, shipped as
full Latin-Extended static files so Turkish glyphs never fall back:

* **Fraunces SemiBold** — display and headline roles: names, page titles, the
  match moment, prices, pull-quoted answers.
* **Manrope 400/500/600/700** — everything the user reads to operate the app.

| Role | Family | Size / line | Use |
|---|---|---|---|
| display L/M/S | Fraunces | 44/50 · 36/42 · 32/38 | Welcome, profile name, Premium |
| headline L/M/S | Fraunces | 30/36 · 26/32 · 22/28 | Page titles, empty-state titles, card names |
| title L/M/S | Manrope 700/600/600 | 20/26 · 17/24 · 15/20 | Section headers, row titles |
| body L/M/S | Manrope 400 | 16/24 · 15/22 · 13/18 | Reading text (M = secondary, S = tertiary) |
| label L/M/S | Manrope 600 | 15/20 · 13/18 · 12/16 | Buttons, pills, meta |

Small-caps eyebrows (`labelSmall`, +1 letter-spacing, uppercased with
`LocaleCasing` where Turkish matters) introduce reasoning blocks.

## Spacing

`lib/core/constants/app_spacings.dart` — a 4-pt scale:
`xxs 2 · xs 4 · sm 8 · s12 12 · md 16 · s20 20 · lg 24 · xl 32 · s40 40 · xxl 48`.
Page gutter is `screenPadding` (20). Touch targets are at least
`minTouchTarget` (48); visually compact controls pad their hit area.

## Radii

`lib/core/theme/app_radii.dart` — chosen by role:
`sm 8` (badges, thumbnails) · `md 14` (inputs, banners) · `lg 20` (cards,
groups) · `card 24` (photos, the Discover card, hero cards) · `xl 28`
(sheets, dialogs) · `pill` (buttons, chips, pills).

## Elevation

Surface colour carries hierarchy; shadows are only for things that float
(`lib/core/theme/app_shadows.dart`): `card` (barely-there lift for one hero
card), `floating` (action discs), `discoveryCard`.

## Icons

One family: **Phosphor** (MIT, `phosphor_flutter`), mapped semantically in
`lib/core/theme/mevora_icons.dart`. Rule: **Regular** at rest, **Fill** for
the selected / active / affirmed state of the same concept (selected tab,
liked heart, verified seal). Never reference `Icons.*` or another set. Name
icons by meaning (`MevoraIcons.compatibility`), not by picture
(`intersect`). Brand glyphs (Apple, Google, Spotify) are only used on sign-in
and attribution. Duotone glyphs appear only inside spot illustrations.

## Motion

`lib/core/constants/app_durations.dart`: `fast 150` (press, toggles),
`normal 250` (most transitions), `slow 400` (large surfaces). Curves:
`AppCurves.enter` (decelerate), `exit` (accelerate), `standard`, and
`emphasized` (soft overshoot, for delight only).

Signature motion (`lib/shared/art/`), all code-drawn, theme-aware, zero asset
weight, and static under reduced-motion:

| Motion | Where | What it says |
|---|---|---|
| `MevoraMarkIntro` | Splash, welcome | Two circles settle into their overlap — the brand |
| `MevoraOrbitLoader` | Any wait | The mark's circles drift apart and find each other |
| Match moment (`MevoraMatchCelebration`) | Mutual like | Two portraits converge; a lens seal lands where they meet |
| `MevoraSuccessMark` | Verified, Premium, onboarding complete | A circle closes, then a check |
| `MevoraBoostBurst` | Boost screen, activation | The bolt lands; rings travel outward |
| `MevoraSpot(animate: true)` | Searching, analysing | Satellites drift around a subject glyph |

Card swipes, press-scale and photo fades are short and directional.

## The Mevora mark

Two circles and the space they share (`MevoraMark`), the lens always ember.
It is the product in one shape — Mevora shows the overlap between two people —
and it recurs on purpose: the loader, the match seal, the music portrait stack.

## Components

`lib/shared/widgets/` (export barrel `mevora_widgets.dart`):

| Component | Purpose |
|---|---|
| `MevoraButton` | `primary` · `secondary` · `tonal` · `ghost` · `inverse` · `destructive`; pill; S 40 / M 52 / L 56 |
| `MevoraIconButton` | Circular; `plain` · `tonal` · `surface` · `onMedia` · `primary`; tooltip required |
| `MevoraCard` | `standard` · `quiet` · `elevated` · `outline`, or a tinted `color` |
| `MevoraChip` | Selectable choice (interests, answers) |
| `MevoraPill` / `MevoraIconBadge` / `MevoraCountBadge` | Read-only labels and glyph badges in a `MevoraTone` |
| `MevoraSectionHeader` | Section title, optional eyebrow, icon, action |
| `MevoraListGroup` / `MevoraListRow` / `MevoraSwitchRow` | Grouped rows for profile, settings, privacy |
| `MevoraBanner` | Inline status that persists until the state changes |
| `MevoraMeter` | Rounded 0–1 bar, toned |
| `MevoraSelectableTile` | Single-choice option (plans, packs) |
| `MevoraContextRow` | One-line context above a conversation |
| `MevoraEmptyState` / `MevoraErrorView` / `MevoraLoading` | States, with a `MevoraArt` spot |
| `MevoraDialog` / `MevoraBottomSheet` | Stacked full-width actions; sheets with `showActions` |
| `MevoraAvatar` | Portrait with serif-initial fallback, verified seal, presence dot |

Compatibility components (`lib/features/compatibility/presentation/widgets/`):
`CompatibilityRing`, `CompatibilitySignalPills`, `CompatibilitySignalBar`,
`CompatibilityRevealSection`, and the Discover strip
`DiscoveryCompatibilityScore`. Music components:
`lib/features/music/presentation/widgets/music_ui.dart`.

### Conventions

* Import tokens; never write a colour, radius or font size inline. A
  one-off value is a missing token — add it here first.
* Photography overlays use `AppDecorations.photoScrim()` and
  `AppColors.onMedia`; they are the only theme-independent colours.
* Use `MevoraDialog` / `MevoraBottomSheet`, not raw `AlertDialog` /
  `showModalBottomSheet` (the theme covers the rest when unavoidable).
* Sheets open on the root navigator, above the tab bar. Close them with the
  sheet's own context, never the page's.
* Every icon-only control has a tooltip / semantic label.
* Long Turkish labels wrap; do not shrink text to fit.
* No emoji in UI copy — meaning is carried by `MevoraIcons`. Server-side
  preview sentinels (`🔒` `📷` `🎤` in `lastMessage`) are mapped to an icon and
  a localized label before display.
* Dates that identify a person (birthdate) always show the year:
  `L10nFormat.mediumDate`, not `MaterialLocalizations.formatMediumDate`.

## States

Empty, loading and error states use `MevoraArt` spot illustrations
(`lib/shared/art/mevora_spot.dart`): a soft halo in the subject's signal
colour, the subject's duotone glyph, three satellites. One subject, one glyph,
one tone — an empty inbox always looks like an empty inbox.
