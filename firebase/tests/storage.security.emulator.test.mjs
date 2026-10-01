/**
 * Behavioural Storage security-rules regression suite.
 *
 * Executes the real storage.rules against the Storage emulator. The chat-media
 * rules call firestore.get(), so the Firestore emulator must run too and the
 * match fixture is seeded before each case.
 *
 * Run from the repo root:
 *   npm --prefix firebase/tests run test:emulator
 */
import {after, before, beforeEach, describe, it} from "node:test";
import {
  MATCH_AB,
  UID,
  actorsFor,
  activeMatchAB,
  allow,
  bytes,
  createSecurityEnv,
  deny,
  knownFinding,
  resetState,
  seed,
} from "./helpers/securityHarness.mjs";

const PENDING_A = `users/${UID.A}/profile/pending/p1.jpg`;
const PHOTOS_A = `users/${UID.A}/profile/photos/approved.jpg`;
const THUMBS_A = `users/${UID.A}/profile/thumbs/t1.jpg`;
const CHAT_A = `users/${UID.A}/chat/${MATCH_AB}/m1.enc`;
const SUPPORT_A = `users/${UID.A}/support/ticket-1/a1.jpg`;

const JPEG = {contentType: "image/jpeg"};
const ENCRYPTED = {contentType: "application/octet-stream"};

let env;
let who;

const read = (actor, path) => actor.bucket().ref(path).getDownloadURL();
const write = (actor, path, data, meta) => actor.bucket().ref(path).put(data, meta);

before(async () => {
  env = await createSecurityEnv({storage: true});
  who = actorsFor(env);
});

after(async () => {
  if (env) {
    await env.cleanup();
  }
});

beforeEach(async () => {
  await resetState(env, {storage: true});
  await seed(env, async (ctx) => {
    // The chat-media rule resolves match membership through Firestore.
    await ctx.firestore().doc(`matches/${MATCH_AB}`).set(activeMatchAB());
    const bucket = ctx.storage();
    await bucket.ref(PENDING_A).put(bytes(64), JPEG);
    await bucket.ref(PHOTOS_A).put(bytes(64), JPEG);
    await bucket.ref(THUMBS_A).put(bytes(64), JPEG);
    await bucket.ref(CHAT_A).put(bytes(64), ENCRYPTED);
    await bucket.ref(SUPPORT_A).put(bytes(64), JPEG);
  });
});

describe("pending profile photos — owner-private until moderation publishes", () => {
  it("owner reads, uploads and deletes their own pending photo", async () => {
    await allow(read(who.userA, PENDING_A));
    await allow(write(who.userA, `users/${UID.A}/profile/pending/p2.jpg`, bytes(64), JPEG));
    await allow(who.userA.bucket().ref(PENDING_A).delete());
  });

  it("an unrelated authenticated user cannot read a pending photo", async () => {
    await deny(read(who.userC, PENDING_A));
  });

  it("an anonymous visitor cannot read a pending photo", async () => {
    await deny(read(who.anon, PENDING_A));
  });

  it("an unrelated user cannot upload into another user's pending folder", async () => {
    await deny(write(who.userC, `users/${UID.A}/profile/pending/evil.jpg`, bytes(64), JPEG));
  });
});

describe("upload validation", () => {
  it("rejects a non-image content type", async () => {
    await deny(write(who.userA, `users/${UID.A}/profile/pending/x.exe`, bytes(64), {
      contentType: "application/x-msdownload",
    }));
  });

  it("rejects SVG, which is script-bearing", async () => {
    await deny(write(who.userA, `users/${UID.A}/profile/pending/x.svg`, bytes(64), {
      contentType: "image/svg+xml",
    }));
  });

  it("rejects a file over the 5 MB profile limit", async () => {
    await deny(write(who.userA, `users/${UID.A}/profile/pending/big.jpg`, bytes(6 * 1024 * 1024), JPEG));
  });

  it("accepts each allowed image type", async () => {
    for (const contentType of ["image/jpeg", "image/png", "image/webp"]) {
      await allow(write(who.userA, `users/${UID.A}/profile/pending/ok-${contentType.split("/")[1]}`, bytes(64), {
        contentType,
      }));
    }
  });
});

describe("published profile photos", () => {
  it("approved photos are readable by authenticated users but not anonymously", async () => {
    await allow(read(who.userC, PHOTOS_A));
    await deny(read(who.anon, PHOTOS_A));
  });

  it("nobody — not even the owner — can publish straight into photos/", async () => {
    await deny(write(who.userA, `users/${UID.A}/profile/photos/self.jpg`, bytes(64), JPEG));
    await deny(write(who.userC, `users/${UID.A}/profile/photos/evil.jpg`, bytes(64), JPEG));
    await deny(who.userA.bucket().ref(PHOTOS_A).delete());
  });

  // B-11 regression. No legitimate writer exists: the client's
  // uploadProfileImage(thumbnail: true) is never invoked and no Cloud Function
  // generates profile thumbnails, so the prefix is server-only like photos/.
  it("nobody can publish a thumbnail, including the owner", async () => {
    await deny(write(who.userA, `users/${UID.A}/profile/thumbs/self.jpg`, bytes(64), JPEG));
    await deny(write(who.userC, `users/${UID.A}/profile/thumbs/evil.jpg`, bytes(64), JPEG));
    await deny(write(who.anon, `users/${UID.A}/profile/thumbs/anon.jpg`, bytes(64), JPEG));
  });

  it("a nested path cannot slip past the thumbnail rule", async () => {
    // A deeper path falls through to the {allPaths=**} catch-all, which denies.
    await deny(write(who.userA, `users/${UID.A}/profile/thumbs/sub/self.jpg`, bytes(64), JPEG));
    await deny(write(who.userA, `users/${UID.A}/profile/thumbs/a/b/c/self.jpg`, bytes(64), JPEG));
    await deny(write(who.userC, `users/${UID.A}/profile/thumbs/sub/evil.jpg`, bytes(64), JPEG));
  });

  it("the owner cannot delete or overwrite a server-published thumbnail", async () => {
    await deny(who.userA.bucket().ref(THUMBS_A).delete());
    await deny(write(who.userA, THUMBS_A, bytes(64), JPEG));
  });

  it("reads are unchanged — discovery may still resolve existing thumbnails", async () => {
    await allow(read(who.userA, THUMBS_A));
    await allow(read(who.userC, THUMBS_A));
    await deny(read(who.anon, THUMBS_A));
  });
});

describe("chat media — participants only", () => {
  it("the owner and the other participant can read the blob", async () => {
    await allow(read(who.userA, CHAT_A));
    await allow(read(who.userB, CHAT_A));
  });

  it("an unrelated user cannot read the blob", async () => {
    await deny(read(who.userC, CHAT_A));
  });

  it("an anonymous visitor cannot read the blob", async () => {
    await deny(read(who.anon, CHAT_A));
  });

  it("a participant uploads an encrypted blob under their own prefix", async () => {
    await allow(write(who.userA, `users/${UID.A}/chat/${MATCH_AB}/m2.enc`, bytes(64), ENCRYPTED));
  });

  it("plaintext media is rejected — chat uploads must be client-encrypted", async () => {
    await deny(write(who.userA, `users/${UID.A}/chat/${MATCH_AB}/plain.jpg`, bytes(64), JPEG));
  });

  it("a user cannot upload into another user's chat prefix", async () => {
    await deny(write(who.userB, `users/${UID.A}/chat/${MATCH_AB}/evil.enc`, bytes(64), ENCRYPTED));
    await deny(write(who.userC, `users/${UID.A}/chat/${MATCH_AB}/evil.enc`, bytes(64), ENCRYPTED));
  });

  it("uploads into an inactive match are rejected", async () => {
    await seed(env, async (ctx) => {
      await ctx.firestore().doc(`matches/${MATCH_AB}`).set({isActive: false}, {merge: true});
    });
    await deny(write(who.userA, `users/${UID.A}/chat/${MATCH_AB}/afterUnmatch.enc`, bytes(64), ENCRYPTED));
  });

  it("uploads into a match the caller does not belong to are rejected", async () => {
    await deny(write(who.userC, `users/${UID.C}/chat/${MATCH_AB}/evil.enc`, bytes(64), ENCRYPTED));
  });
});

describe("support attachments", () => {
  it("only the owner can read their support attachment", async () => {
    await allow(read(who.userA, SUPPORT_A));
    await deny(read(who.userC, SUPPORT_A));
    await deny(read(who.anon, SUPPORT_A));
  });

  it("an unrelated user cannot attach to another user's ticket", async () => {
    await deny(write(who.userC, `users/${UID.A}/support/ticket-1/evil.jpg`, bytes(64), JPEG));
  });
});

describe("Face Anchor verification selfie — write-once, unreadable, tied to an open attempt", () => {
  const HOUR = 60 * 60 * 1000;
  const STATE_A = `users/${UID.A}/faceAnchor/state`;
  const selfieOf = (uid, attemptId) => `face-anchor/pending/${uid}/${attemptId}`;

  // Every case gets its own attempt id, and so its own object path. A selfie
  // can never be deleted or replaced, and the emulator keeps Storage objects
  // across cases — with a shared path, a "denied" case could be denied only
  // because an earlier case had already put an object there.
  let sequence = 0;
  let attempt;
  let selfie;
  beforeEach(() => {
    sequence += 1;
    attempt = `attempt-${sequence}`;
    selfie = selfieOf(UID.A, attempt);
  });

  /** What startFaceAnchorVerification writes, through the Admin SDK. */
  const openAttempt = (overrides = {}) => seed(env, async (ctx) => {
    await ctx.firestore().doc(STATE_A).set({
      attemptId: attempt,
      photoId: "p1",
      status: "awaiting_selfie",
      expiresAtMs: Date.now() + HOUR,
      ...overrides,
    });
  });
  const placeSelfie = (path = selfie) => seed(env, async (ctx) => {
    await ctx.storage().ref(path).put(bytes(64), JPEG);
  });

  it("the owner uploads the selfie for the attempt the server opened", async () => {
    await openAttempt();
    await allow(write(who.userA, selfie, bytes(64), JPEG));
  });

  it("a camera-sized selfie, sent as a resumable upload, is accepted too", async () => {
    // The mobile SDKs upload in several requests; the object must still count
    // as new on the request that finishes it.
    await openAttempt();
    await allow(write(who.userA, selfie, bytes(600 * 1024), JPEG));
  });

  it("no attempt, no upload", async () => {
    await deny(write(who.userA, selfie, bytes(64), JPEG));
  });

  it("an attempt id the server did not issue is refused", async () => {
    await openAttempt();
    await deny(write(who.userA, selfieOf(UID.A, `${attempt}-other`), bytes(64), JPEG));
    await deny(write(who.userA, selfieOf(UID.A, "anything-else"), bytes(64), JPEG));
    // The same member, the issued id: allowed. So the denials above are about the id.
    await allow(write(who.userA, selfie, bytes(64), JPEG));
  });

  it("an expired attempt takes no upload", async () => {
    await openAttempt({expiresAtMs: Date.now() - 1000});
    await deny(write(who.userA, selfie, bytes(64), JPEG));
  });

  it("an attempt that is processing or finished takes no upload", async () => {
    for (const status of ["processing", "verified", "failed", "expired", "error"]) {
      await openAttempt({status});
      await deny(write(who.userA, selfie, bytes(64), JPEG));
    }
    // Back to waiting: the same path is accepted, so nothing else was in the way.
    await openAttempt();
    await allow(write(who.userA, selfie, bytes(64), JPEG));
  });

  it("nobody uploads into another member's attempt", async () => {
    await openAttempt();
    await deny(write(who.userB, selfie, bytes(64), JPEG));
    await deny(write(who.userC, selfie, bytes(64), JPEG));
    await deny(write(who.anon, selfie, bytes(64), JPEG));
    await allow(write(who.userA, selfie, bytes(64), JPEG));
  });

  it("a member's own open attempt does not let them write under someone else's uid", async () => {
    await seed(env, async (ctx) => {
      await ctx.firestore().doc(`users/${UID.C}/faceAnchor/state`).set({
        attemptId: attempt,
        status: "awaiting_selfie",
        expiresAtMs: Date.now() + HOUR,
      });
    });
    await deny(write(who.userC, selfie, bytes(64), JPEG));
    await allow(write(who.userC, selfieOf(UID.C, attempt), bytes(64), JPEG));
  });

  it("only images, and only under 5 MB", async () => {
    await openAttempt();
    await deny(write(who.userA, selfie, bytes(64), {contentType: "application/octet-stream"}));
    await deny(write(who.userA, selfie, bytes(64), {contentType: "video/mp4"}));
    await deny(write(who.userA, selfie, bytes(5 * 1024 * 1024 + 1), JPEG));
    await allow(write(who.userA, selfie, bytes(64), {contentType: "image/png"}));
  });

  it("nobody can read a selfie — not other members, not its owner", async () => {
    await openAttempt();
    await placeSelfie();
    await deny(read(who.userA, selfie));
    await deny(read(who.userB, selfie));
    await deny(read(who.userC, selfie));
    await deny(read(who.anon, selfie));
    await deny(who.userA.bucket().ref(selfie).getMetadata());
    await deny(who.userC.bucket().ref(`face-anchor/pending/${UID.A}`).listAll());
    await deny(who.userA.bucket().ref(`face-anchor/pending/${UID.A}`).listAll());
  });

  it("a selfie cannot be replaced or deleted from a client", async () => {
    await openAttempt();
    await allow(write(who.userA, selfie, bytes(64), JPEG));
    // The attempt is still open; only the existing object stands in the way.
    await deny(write(who.userA, selfie, bytes(64, 2), JPEG));
    await deny(who.userA.bucket().ref(selfie).updateMetadata({contentType: "image/png"}));
    await deny(who.userA.bucket().ref(selfie).delete());
    await deny(who.userC.bucket().ref(selfie).delete());
  });

  it("the selfie prefix is not a second way to publish profile photos", async () => {
    await openAttempt();
    await deny(write(who.userA, `${selfie}/nested.jpg`, bytes(64), JPEG));
    await deny(write(who.userA, `face-anchor/${UID.A}.jpg`, bytes(64), JPEG));
    await deny(write(who.userA, `face-anchor/verified/${UID.A}/x.jpg`, bytes(64), JPEG));
  });

  it("profile photo rules are unchanged by an open attempt", async () => {
    await openAttempt();
    await allow(write(who.userA, `users/${UID.A}/profile/pending/p9-${sequence}.jpg`, bytes(64), JPEG));
    await allow(read(who.userB, PHOTOS_A));
    await deny(write(who.userA, PHOTOS_A, bytes(64), JPEG));
    await deny(write(who.userA, THUMBS_A, bytes(64), JPEG));
  });
});

describe("unknown paths", () => {
  it("writes outside the declared prefixes are denied", async () => {
    await deny(write(who.userA, "random/anything.jpg", bytes(64), JPEG));
    await deny(write(who.userA, `users/${UID.A}/unknown/anything.jpg`, bytes(64), JPEG));
    await deny(write(who.anon, "public/anything.jpg", bytes(64), JPEG));
  });

  it("reads outside the declared prefixes are denied", async () => {
    await deny(read(who.userA, "random/anything.jpg"));
    await deny(read(who.anon, "random/anything.jpg"));
  });
});
