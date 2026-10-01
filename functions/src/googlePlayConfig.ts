import {defineSecret} from "firebase-functions/params";

/**
 * The Google Play Developer API service account (the whole JSON key file).
 *
 *   firebase functions:secrets:set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON \
 *     --project <project> --data-file <path to the key file>
 *
 * Must exist before any function that binds it is deployed, and must not also
 * be set in a `functions/.env*` file — a deploy refuses a name that is both.
 */
export const googlePlayServiceAccount = defineSecret(
  "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON",
);

/**
 * `secrets:` for the functions that call the Play Developer API: Boost
 * purchase verification, Premium purchase verification and the Premium RTDN
 * trigger. Binding is what puts the secret in `process.env` for those
 * functions and for no others, so the verifiers go on reading
 * `process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`. Missing in a deployment, it
 * fails closed: the verifiers report the store as unavailable and grant
 * nothing.
 *
 * Not bound under the Functions emulator, and that is what keeps the emulator
 * behaving as it did. The emulator fills a bound secret from Secret Manager
 * whenever the developer's credentials can read it, and the emulator test
 * stores answer only while no Play credential is present — so binding it there
 * would silently switch a local run to real Google the day the secret is
 * created. A developer who wants that still sets the variable in
 * `functions/.env.local`, as before.
 */
export const googlePlaySecrets = [googlePlayServiceAccount].filter(
  () => process.env.FUNCTIONS_EMULATOR !== "true",
);
