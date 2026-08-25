# Automated Tests

## Flutter unit/widget

| Suite | Result |
|-------|--------|
| Full `flutter test` | **654 PASS** |
| New `test/features/chat/chat_peer_name_source_test.dart` | **2 PASS** |
| Prior QA fixes (account settings, voice rules, profile answers) | PASS |

## Functions

| Suite | Result |
|-------|--------|
| `functions` `npm test` | **78 PASS** |

## Integration

| Test | Result |
|------|--------|
| `integration_test/smoke/app_launch_test.dart` | Unstable under multi-emu |
| `integration_test/smoke/multi_user_email_auth_test.dart` | Added; hung — **FAIL/BLOCKED** this run |

## Emulator backend scripts

| Script | Result |
|--------|--------|
| `tool/qa_multi_user_seed_admin.cjs` | PASS |
| `tool/qa_multi_user_verify.cjs` | **14/14 PASS** |
| Auth REST login A/B/C + invalid | PASS |

## Static analysis

`flutter analyze` → 2 prefer_single_quotes infos only.

## Coverage

`flutter test --coverage` not completed in this window (full suite green without coverage HTML generation).

## Inventory (code)

- Routes in `app_routes.dart`: **43** named routes
- Dart files with `onPressed`/`onTap`: **77** files under `lib/`
