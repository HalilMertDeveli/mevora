import {defineSecret, defineString} from "firebase-functions/params";

/** Public Spotify OAuth client ID. The client secret is never stored here. */
export const spotifyClientId = defineString("SPOTIFY_CLIENT_ID", {
  default: "a937aa81f01645f78c5ba8c174c800d1",
});
export const spotifyClientSecret = defineSecret("SPOTIFY_CLIENT_SECRET");
