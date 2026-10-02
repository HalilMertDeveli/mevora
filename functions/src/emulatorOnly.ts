/**
 * Callables that exist for the Functions emulator and nowhere else.
 *
 * `index.ts` loads this module only when the process is the emulator, so a
 * deploy never sees these names: Firebase works out what to deploy by loading
 * `lib/index.js` without `FUNCTIONS_EMULATOR`, and what is not exported there
 * is not deployed. The smoke module, and the secret it declares, are therefore
 * not even loaded in a deployed backend.
 *
 * Each of these also refuses at call time outside the emulator process. That
 * second check covers a function left live by an earlier deploy until the
 * owner deletes it.
 *
 * To add a QA or debugging callable: export it from here, never from
 * `index.ts`, and give it the same call-time refusal.
 */
// Creates and removes the two smoke accounts; hands back their passwords.
export {prepareSmokeTestUsers, cleanupSmokeTestUsers} from "./smoke/smokeTestUsers.js";
// Curator tool: searches GIPHY for catalogue candidates. Writes nothing.
export {searchHumorProviderCandidates} from "./humor/index.js";
// Shows how the personalization ranker scores a viewer's candidates.
export {debugPersonalizationRanking} from "./personalization/functions.js";
