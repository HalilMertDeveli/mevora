/**
 * Static Firestore rules contract for exact GPS.
 * Emulator suite (requires Java):
 *   npx.cmd firebase emulators:exec --only firestore --project mevora-dev "npm --prefix firebase/tests test"
 */
import {readFileSync} from "node:fs";
import {assert} from "node:console";

const rules = readFileSync(new URL("../firestore.rules", import.meta.url), "utf8");

if (rules.includes("allow read, write: if true")) {
  throw new Error("Open rules are forbidden.");
}
if (!rules.includes("match /userLocation/{userId}")) {
  throw new Error("userLocation rules missing.");
}
if (!rules.includes("allow read, delete: if isOwner(userId)")) {
  throw new Error("Other users must not read exact GPS.");
}
if (!rules.includes("allow read, write: if false")) {
  throw new Error("Default deny missing.");
}

console.log("location.rules.contract.ok");
