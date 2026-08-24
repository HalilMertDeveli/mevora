# Turkish Encoding Fix Report

**Date:** 2026-08-23

## Root cause

Support/legal localization keys were merged into `app_tr.arb` / `app_en.arb` with **PowerShell `ConvertTo-Json` + `Set-Content`**, which re-encoded UTF-8 Turkish text as Windows-1252-style mojibake (e.g. `ş` → `ÅŸ`, `ı` → `Ä±`).

`flutter gen-l10n` then generated corrupted `app_localizations_tr.dart` (and EN doc comments with `â€”`).

This was **not** a Firebase, messaging, or font bug.

## Files with corruption (before fix)

| File | Status |
|------|--------|
| `lib/l10n/app_tr.arb` | Corrupted (mojibake) |
| `lib/l10n/app_en.arb` | Partially corrupted (em dashes) |
| `lib/l10n/app_localizations_tr.dart` | Regenerated from bad ARB |
| `lib/l10n/app_localizations_en.dart` | Regenerated from bad ARB |
| `lib/l10n/app_localizations.dart` | Doc comments corrupted |

## Fix applied

1. Restored clean ARB files from git `HEAD`
2. Re-merged support strings with **Dart UTF-8** (`tool/merge_support_l10n.dart`) — no PowerShell JSON rewrite
3. Regenerated l10n with `flutter gen-l10n`
4. Project-wide mojibake scan: **no hits** in `lib/`, `hosting/` (only scanner tool strings)

## Control results

| Check | Result |
|-------|--------|
| UTF-8 ARB / generated TR | **PASS** — ç ğ ı İ ö ş ü present, no Ã/Ä/Å mojibake |
| English localization | **PASS** — no `â€` corruption |
| Firebase | **N/A / OK** — Firestore stores Unicode; no client encode layer corrupting strings |
| Messaging | **OK by architecture** — strings stored/read as UTF-8; no encoding transform found |
| Localization architecture | **Unchanged** — same ARB → gen-l10n flow |
| Font (Manrope / Fraunces) | **OK** — Manrope Latin Extended covers Turkish glyphs; glyphs were correct once strings were fixed |
| Support FAQ / legal TR | **PASS** — e.g. `Yardım ve Destek`, `Gizlilik Politikası`, `Kullanım Koşulları` |
| Hardcoded `SafetyStrings` | **PASS** — already valid UTF-8 Turkish |

## Prevention

- Use `dart run tool/merge_support_l10n.dart` for ARB merges
- Never merge ARB with PowerShell `ConvertTo-Json` / default `Set-Content`
- Regression test: `test/features/localization/turkish_encoding_test.dart`

## Not changed

Auth, matching, discover, messaging pipelines, Firebase rules — encoding-only fix.
