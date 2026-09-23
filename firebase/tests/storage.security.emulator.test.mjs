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
