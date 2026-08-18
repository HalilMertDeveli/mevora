import {setGlobalOptions} from "firebase-functions/v2";
import {onCall} from "firebase-functions/v2/https";

setGlobalOptions({region: "europe-west1", maxInstances: 10});

/// Infrastructure probe used by the emulator. Business callables are added
/// in later phases and must not live in the client.
export const health = onCall({enforceAppCheck: false}, () => {
  return {status: "ok", service: "mevora"};
});
