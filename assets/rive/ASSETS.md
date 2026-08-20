# Mevora Rive assets

Runtime `.riv` files used on real screens. Missing files fall back to Flutter
widgets via `MevoraRiveAnimation`.

| File | Purpose | Notes |
| --- | --- | --- |
| `common/loading.riv` | Shared / discovery loading | liquid download spinner |
| `common/success.riv` | Success states | rating / stars |
| `common/error.riv` | Error states | rating / empty stars |
| `common/empty.riv` | Generic empty (settings) | little machine |
| `common/splash.riv` | Splash brand moment | 2d girl character |
| `authentication/login_ambient.riv` | Login people accent | interactive character follow |
| `onboarding/complete.riv` | Onboarding complete / goal | look character |
| `onboarding/photo_upload.riv` | Photo upload | rocket / press button |
| `onboarding/location.riv` | Location determining | cloudy walk |
| `matching/match.riv` | Match celebration | yippee celebration |
| `matching/empty_profiles.riv` | Discovery empty | 2d girl |
| `matching/empty_matches.riv` | Matches empty | interactive character |
| `chat/empty.riv` | Empty conversation | girl cursor tracking |
| `profile/accent.riv` | Profile tab accent | look character |

## Source inventory (`Riv-files/`)

Community `.riv` sources kept for reference. **Not** registered in `pubspec.yaml`
(avoid shipping duplicates / oversized files).

| File | Size | Classification | Used as |
| --- | --- | --- | --- |
| `9729-18558-2d-girl.riv` | ~44 KB | people / dating | splash, empty_profiles |
| `28334-53514-interactive-character-follow.riv` | ~79 KB | people / follow | login, empty_matches |
| `19397-36522-girl-animation-cursor-tracking.riv` | ~140 KB | people / interactive | chat empty |
| `22487-42095-look.riv` | ~194 KB | people / look | onboarding complete, profile |
| `24966-46592-cloudy-walk.riv` | ~266 KB | walk / search | location locating |
| `27915-52755-yippee.riv` | ~1.2 MB | celebration / love | match |
| `20381-38326-black-cat.riv` | ~4.5 MB | mascot | **unused** (bundle size) |

Promote copies live under feature folders; originals stay in `Riv-files/`.
