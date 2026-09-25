# Mevora — Core

Flutter dating app (iOS/Android) + Firebase backend. Monorepo, single Git repo, Windows dev host.
Product hook: compatibility-scored discovery, not proximity-only.

## Source map

```
lib/                 Flutter app (feature-first + clean architecture)
  core/              config, di, routing, theme, errors, services, localization, analytics, geo, session
  features/<f>/      data/ domain/ presentation/  (22 features: authentication, onboarding, profile,
                     discovery, matching, match_score, compatibility, music, chat, calls, video,
                     notifications, safety, settings, subscription, boost, location, permissions,
                     relationship, support, verification)
  shared/            widgets (Mevora* design system), components, models, animations, images
  l10n/              ARB + generated AppLocalizations
  bootstrap.dart     single composition root; app.dart builds the widget/scope tree
  main_{development,staging,production}.dart   entrypoints -> bootstrap(AppEnvironment.x)
functions/           Cloud Functions (TypeScript, Node 20) -> `mem:functions/core`
firebase/            firestore.rules, storage.rules, firestore.indexes.json, tests/ -> `mem:firebase/core`
hosting/public/      static legal/support pages (privacy, terms, guidelines, help)
mevora-support-web/  separate support web surface
test/                Dart unit/widget/security tests
integration_test/    on-device E2E (smoke, matching, spotify)
tool/                one-off Node .cjs / Dart / PowerShell dev+QA scripts (excluded from analyzer)
tools/smoke/         backend production smoke harness (run_smoke_test.mjs, needs service account)
qa/                  captured QA run logs (artifacts, not sources)
docs/ + *.md at root architecture/QA/audit reports
```

## Invariants

- Layering is enforced by convention: Presentation → Controller (`ChangeNotifier`) → Repository (domain
  interface) → DataSource → Firebase. No Firebase types above the data layer.
- No DI container. Dependency injection is manual: `*_services_factory.dart` builds instances in
  `bootstrap.dart`, `*_scope.dart` are `InheritedWidget`s exposing them via `Scope.of(context)`.
- Security-sensitive logic lives in Cloud Functions / rules, never client-side. No secrets in source.
- Three environments via Dart entrypoints + Android product flavors (`development`, `staging` (appId
  suffix `.staging`), `production`).
- Repo is multi-agent: branch/worktree isolation rules are in `CLAUDE.md` at repo root and take
  precedence — not duplicated here.

## Further memories

- Languages, frameworks, dependency pins, package managers: `mem:tech_stack`
- Build / run / test / emulator commands and Windows-specific invocations: `mem:suggested_commands`
- Code style, lint rules, naming, error handling, localization rules: `mem:conventions`
- What must be green before declaring a task done: `mem:task_completion`
- Cloud Functions module layout and its test runner: `mem:functions/core`
- Firestore/Storage rules, indexes, emulator ports, project ids: `mem:firebase/core`
