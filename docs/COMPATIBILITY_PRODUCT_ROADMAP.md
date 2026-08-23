# Compatibility Product Roadmap

## Live now

- Unified compatibility breakdown (0–100 overall + categories)
- Server-side discovery scoring fix (viewer profile used, not preferences doc)
- Why You Match on mutual match
- Discover “Why?” breakdown sheet
- Hidden compatibility card (real question alignment only)
- Compatibility-first discover tiebreak
- EN/TR localization for compatibility copy
- Unit tests (Flutter + Functions)

## Ready for future

- Premium gating via `CompatibilityFeatureGate`
- Analytics wiring through app-level analytics scope
- Push notification when hidden compatibility insight appears (real data only)
- Admin-tunable weights via Remote Config
- Optional Firestore cache for hot pairs (not enabled — cost control)
- AI-generated conversation starters (explanations stay deterministic)

## Explicitly not planned as fake features

- “Someone liked you” without a real like
- “Someone nearby is waiting” without real proximity logic
- Humor/personality scores without profile fields
- AI core scoring in v1
