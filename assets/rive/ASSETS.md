# Mevora Rive assets

Runtime `.riv` files used on real screens. Missing files fall back to Flutter
widgets via `MevoraRiveAnimation` (CircularProgressIndicator / icons — never a
blank or broken blue box). Animations stay **compact** in a small region.
Full-screen overlays are not used for loading or route transitions.

| File | Purpose | Notes |
| --- | --- | --- |
| `common/searching.riv` | Discovery / generic / call connecting | cloudy-walk |
| `common/loading.riv` | Music analysis + Spotify connecting | liquid download / sync |
| `common/success.riv` | Success / call ended | rating / stars |
| `common/error.riv` | Error states | rating / empty stars |
| `common/empty.riv` | Generic empty | little machine |
| `common/splash.riv` | Splash brand (hidden on launch) | 2d girl |
| `authentication/login_ambient.riv` | Login + Spotify idle | interactive character |
| `onboarding/complete.riv` | Onboarding goal + relationship result | look |
| `onboarding/photo_upload.riv` | Photo upload | rocket / press |
| `onboarding/location.riv` | Location determining | cloudy walk |
| `matching/match.riv` | Mutual match celebration | yippee |
| `matching/empty_profiles.riv` | Discovery / music empty | 2d girl |
| `matching/empty_matches.riv` | Matches empty | interactive character |
| `chat/empty.riv` | Empty conversation | girl cursor tracking |
| `profile/accent.riv` | Profile hydrate accent | look |

## Semantic aliases (`MevoraRiveAssets`)

| Alias | Resolves to | Use |
| --- | --- | --- |
| `loading` / `callConnecting` / `pageAccent` | `searching.riv` | Compact loaders |
| `musicAnalyzing` / `spotifyConnecting` | `loading.riv` | Sync / analysis |
| `spotifyIdle` | `login_ambient.riv` | Spotify connect screen |
| `relationshipResult` / `profileLoading` | look character | Relationship + profile |
| `match` | `matching/match.riv` | It's a match |

## Source inventory (`Riv-files/`)

Community `.riv` sources kept for reference. **Not** registered in `pubspec.yaml`
(avoid shipping duplicates / oversized files).

| File | Size | Classification | Used as |
| --- | --- | --- | --- |
| `9729-18558-2d-girl.riv` | ~44 KB | people / dating | splash, empty_profiles |
| `28334-53514-interactive-character-follow.riv` | ~79 KB | people / follow | login, Spotify idle, empty_matches |
| `19397-36522-girl-animation-cursor-tracking.riv` | ~140 KB | people / interactive | chat empty |
| `22487-42095-look.riv` | ~194 KB | people / look | onboarding complete, profile, relationship result |
| `24966-46592-cloudy-walk.riv` | ~266 KB | walk / search | location, discovery loading |
| `27915-52755-yippee.riv` | ~1.2 MB | celebration / love | match |
| `20381-38326-black-cat.riv` | ~4.5 MB | mascot | **unused** (bundle size) |

Promote copies live under feature folders; originals stay in `Riv-files/`.
