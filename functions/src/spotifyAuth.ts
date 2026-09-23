import {createHash, randomBytes} from "node:crypto";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {spotifyClientId, spotifyClientSecret} from "./spotifyConfig.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const auth = getAuth();

type SpotifyProfile = {
  id: string;
  display_name?: string;
  email?: string;
  images?: Array<{url?: string}>;
};

/** Shape of the Spotify index document that maps a Spotify id to a uid. */
export type SpotifyIndexRef = {exists: boolean; uid?: unknown};

/** What a Spotify sign-in resolves to, before any write happens. */
export type SpotifyIdentityPlan = {
  uid: string;
  isNewUser: boolean;
  alreadyLinked: boolean;
  writeIndex: boolean;
  createAuthUser: boolean;
};

/**
 * Decides which Mevora uid a Spotify identity belongs to.
 *
 * A Spotify account is owned by exactly one uid: linking one that another
 * account already claimed is rejected rather than silently re-pointed.
 */
export function resolveSpotifyLoginIdentity(input: {
  spotifyId: string;
  currentUid?: string;
  index: SpotifyIndexRef;
}): SpotifyIdentityPlan {
  const {spotifyId, currentUid, index} = input;
  if (currentUid) {
    if (index.exists && index.uid !== currentUid) {
      throw new HttpsError("failed-precondition", "account-exists", {
        mevoraCode: "account-exists",
      });
    }
    return {
      uid: currentUid,
      isNewUser: false,
      alreadyLinked: true,
      writeIndex: !index.exists,
      createAuthUser: false,
    };
  }
  if (index.exists) {
    return {
      uid: String(index.uid),
      isNewUser: false,
      alreadyLinked: false,
      writeIndex: false,
      createAuthUser: false,
    };
  }
  return {
    uid: `sp_${spotifyId}`,
    isNewUser: true,
    alreadyLinked: false,
    writeIndex: true,
    createAuthUser: true,
  };
}

/**
 * The exact client payload. Spotify access tokens, refresh tokens and the
 * client secret are server-only and never appear here.
 */
export function buildSpotifyAuthResponse(input: {
  customToken: string | null;
  alreadyLinked: boolean;
  isNewUser: boolean;
  profile: SpotifyProfile;
}): Record<string, unknown> {
  return {
    customToken: input.customToken,
    alreadyLinked: input.alreadyLinked,
    isNewUser: input.isNewUser,
    email: input.profile.email ?? null,
    displayName: input.profile.display_name ?? null,
    photoUrl: input.profile.images?.[0]?.url ?? null,
  };
}

export function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", field);
  }
  return value.trim();
}

async function consumeRateLimit(key: string): Promise<void> {
  const ref = db.doc(`authRateLimits/${key}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const windowMs = 10 * 60 * 1000;
    const data = snap.data() ?? {};
    const started = typeof data.windowStart === "number" ? data.windowStart : now;
    const count = typeof data.count === "number" ? data.count : 0;
    if (now - started > windowMs) {
      tx.set(ref, {windowStart: now, count: 1, updatedAt: FieldValue.serverTimestamp()});
      return;
    }
    if (count >= 20) {
      throw new HttpsError("resource-exhausted", "too-many-requests");
    }
    tx.set(ref, {
      windowStart: started,
      count: count + 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";

export const spotifyCompleteAuth = onCall(
  {
    secrets: [spotifyClientSecret],
    enforceAppCheck,
    region: "europe-west1",
  },
  async (request) => {
    const code = requireString(request.data?.code, "code");
    const codeVerifier = requireString(request.data?.codeVerifier, "codeVerifier");
    const redirectUri = requireString(request.data?.redirectUri, "redirectUri");
    const limitKey = request.auth?.uid ??
      createHash("sha256").update(request.rawRequest.ip ?? randomBytes(8)).digest("hex");
    await consumeRateLimit(`spotify_${limitKey}`);

    const clientId = process.env.SPOTIFY_CLIENT_ID || spotifyClientId.value();
    const clientSecret = process.env.SPOTIFY_CLIENT_SECRET || spotifyClientSecret.value();
    if (!clientId || !clientSecret) {
      throw new HttpsError("failed-precondition", "not-configured");
    }

    const body = new URLSearchParams({
      grant_type: "authorization_code",
      code,
      redirect_uri: redirectUri,
      client_id: clientId,
      code_verifier: codeVerifier,
    });
    const tokenResponse = await fetch("https://accounts.spotify.com/api/token", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Authorization: `Basic ${Buffer.from(`${clientId}:${clientSecret}`).toString("base64")}`,
      },
      body,
    });
    if (!tokenResponse.ok) {
      throw new HttpsError("unauthenticated", "oauth");
    }
    const tokenJson = await tokenResponse.json() as {access_token?: string};
    if (!tokenJson.access_token) {
      throw new HttpsError("unauthenticated", "oauth");
    }

    const meResponse = await fetch("https://api.spotify.com/v1/me", {
      headers: {Authorization: `Bearer ${tokenJson.access_token}`},
    });
    if (!meResponse.ok) {
      throw new HttpsError("unauthenticated", "oauth");
    }
    const profile = await meResponse.json() as SpotifyProfile;
    if (!profile.id) {
      throw new HttpsError("unauthenticated", "oauth");
    }

    const indexRef = db.doc(`spotifyIndex/${profile.id}`);
    const indexSnap = await indexRef.get();
    const plan = resolveSpotifyLoginIdentity({
      spotifyId: profile.id,
      currentUid: request.auth?.uid,
      index: {exists: indexSnap.exists, uid: indexSnap.data()?.uid},
    });
    const {uid, isNewUser, alreadyLinked} = plan;

    if (plan.createAuthUser) {
      try {
        await auth.createUser({
          uid,
          displayName: profile.display_name,
          email: profile.email,
          photoURL: profile.images?.[0]?.url,
        });
      } catch (error) {
        const code = (error as {code?: string}).code;
        if (code !== "auth/uid-already-exists") {
          throw new HttpsError("internal", "oauth");
        }
      }
    }
    if (plan.writeIndex) {
      await indexRef.set({uid, createdAt: FieldValue.serverTimestamp()});
    }

    const userRef = db.doc(`users/${uid}`);
    const existing = await userRef.get();
    const now = FieldValue.serverTimestamp();
    if (!existing.exists) {
      await userRef.set({
        id: uid,
        uid,
        displayName: profile.display_name ?? null,
        email: profile.email ?? null,
        photoUrl: profile.images?.[0]?.url ?? null,
        authProviders: {google: false, apple: false, spotify: true, phone: false, email: false},
        createdAt: now,
        lastLoginAt: now,
        lastActiveAt: now,
        profileCompleted: false,
        onboardingCompleted: false,
        isActive: true,
        isBanned: false,
        isVerified: false,
      });
    } else {
      if (existing.data()?.isBanned === true) {
        throw new HttpsError("permission-denied", "banned");
      }
      await userRef.update({
        lastLoginAt: now,
        lastActiveAt: now,
        "authProviders.spotify": true,
        ...(profile.display_name ? {displayName: profile.display_name} : {}),
        ...(profile.email ? {email: profile.email} : {}),
        ...(profile.images?.[0]?.url ? {photoUrl: profile.images[0].url} : {}),
      });
    }

    const customToken = alreadyLinked ? null : await auth.createCustomToken(uid, {
      provider: "spotify",
      spotifyId: profile.id,
    });
    return buildSpotifyAuthResponse({
      customToken,
      alreadyLinked,
      isNewUser,
      profile,
    });
  },
);
