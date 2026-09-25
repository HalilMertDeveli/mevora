# Conventions

## Structure
- Feature-first: `lib/features/<feature>/{data,domain,presentation}`.
  - `domain/`: entities, repository interfaces, pure services (no Firebase imports).
  - `data/`: `datasources/` (Firebase-facing) + `repositories/` (`*RepositoryImpl`).
  - `presentation/`: `controllers/` (`ChangeNotifier`), `pages/`, `widgets/`.
- Cross-feature/shared infrastructure goes to `lib/core/`; reusable UI to `lib/shared/`.
- Wiring: add a `lib/core/di/<feature>_services_factory.dart` (construction) plus
  `<feature>_scope.dart` (`InheritedWidget` with `of`/`maybeOf` + `updateShouldNotify`), then mount in
  `lib/bootstrap.dart` / `lib/app.dart`. Never introduce a service locator or global singleton.
- Imports are absolute `package:mevora/...`, not relative.

## Error handling
- `lib/core/errors/`: sealed `Result<T>` (`Success` / `Err`) with `when`/`valueOrNull`/`failureOrNull`,
  `Failure` hierarchy, `failure_mapper.dart` (exception → Failure), `failure_messages.dart`
  (Failure → localized text), `AppException`, `ErrorHandler`.
- Repositories return `Result<T>`; controllers translate failures into state, not thrown exceptions.

## Style (enforced by analysis_options.yaml, on top of flutter_lints)
- Single quotes, trailing commas required, const constructors/declarations/literals preferred,
  `prefer_final_locals`, explicit return types, no `print` (use `AppLogger`), no unawaited futures or
  `discarded_futures`, `avoid_void_async`, `use_super_parameters`.
- Analyzer runs in strict mode (`strict-casts`, `strict-inference`, `strict-raw-types`).
- `analysis_options.yaml` EXCLUDES several later-phase feature trees (chat, calls, matching, safety,
  notifications, video, onboarding, settings, boost, parts of profile/di) plus `tool/**` and the
  matching test dirs. Code there is not analyzed — do not assume it is lint-clean, and do not silently
  remove exclusions.

## UI / design system
- Shared widgets are `Mevora*` (`lib/shared/widgets/mevora_*.dart`, barrel `mevora_widgets.dart`):
  MevoraButton/TextField/Card/Avatar/Chip/Dialog/BottomSheet/Loading/ErrorView/EmptyState.
- Theme tokens live in `lib/core/theme/` (`app_colors`, `app_typography`, `app_radii`, `app_shadows`,
  `app_elevation`, `app_decorations`); use tokens, not literal colors/sizes.

## Localization
- Every user-facing string goes through ARB (`lib/l10n/app_en.arb` + `app_tr.arb`); en is the template.
- Turkish text has a history of mojibake on this Windows host — ARB/i18n helper scripts exist in
  `tool/` (`verify_tr_strings.dart`, `scan_mojibake.dart`, `check_utf8.dart`, `verify_generated_l10n.dart`,
  `merge_*_l10n.dart`). Write ARB files as UTF-8 and verify Turkish strings after bulk edits.
- Untranslated keys are reported to `lib/l10n/untranslated.txt`.

## Security
- Never `allow read, write: if true;`. Client is untrusted: scoring, matching, moderation, premium
  entitlement and rate limiting are server-side.
- No secrets, service accounts or private keys in the repo; local-only files use the `.local` suffix.
