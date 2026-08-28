import {defineSecret, defineString} from "firebase-functions/params";

/** Public Spotify OAuth client ID. The client secret is never stored here. */
export const spotifyClientId = defineString("SPOTIFY_CLIENT_ID", {
  default: "b0a808c4c2264b0ba179c2045a8d3445",
});
export const spotifyClientSecret = defineSecret("SPOTIFY_CLIENT_SECRET");
