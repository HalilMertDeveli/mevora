/**
 * Behavioural Firestore security-rules regression suite.
 *
 * Every assertion executes the real rule against the Firestore emulator.
 * Nothing here inspects the text of firestore.rules — the substring contract
 * tests in test/security/*.dart and location.rules.test.mjs remain as a
 * supplemental layer.
 *
 * Run from the repo root:
 *   npm --prefix firebase/tests run test:emulator
 */
import {after, before, beforeEach, describe, it} from "node:test";
import assert from "node:assert/strict";
import {
  MATCH_AB,
  UID,
  actorsFor,
  activeMatchAB,
  allow,
  baseAccount,
  baseProfile,
  canonicalBlockId,
  createSecurityEnv,
  deny,
  encryptedMessage,
  knownFinding,
  resetState,
  seed,
} from "./helpers/securityHarness.mjs";

let env;
let who;

before(async () => {
  env = await createSecurityEnv();
  who = actorsFor(env);
});

after(async () => {
  if (env) {
    await env.cleanup();
  }
});

beforeEach(async () => {
  await resetState(env);
  await seed(env, async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`matches/${MATCH_AB}`).set(activeMatchAB());
    await db.doc(`matches/${MATCH_AB}/messages/m1`).set(
      encryptedMessage({senderId: UID.A, receiverId: UID.B}),
    );
    for (const uid of [UID.A, UID.B, UID.C]) {
      await db.doc(`profiles/${uid}`).set(baseProfile(uid));
      await db.doc(`users/${uid}`).set(baseAccount(uid));
      await db.doc(`users/${uid}/subscription/current`).set({isPremium: false});
      await db.doc(`userPrivacy/${uid}`).set({showOnlineStatus: true});
      await db.doc(`userLocation/${uid}`).set({
        uid,
        latitude: 41.0082,
        longitude: 28.9784,
        geohash: "sxk9",
      });
    }
    await db.doc(`users/${UID.A}/questionAnswers/q1`).set({
      answer: "private answer",
      isVisible: true,
    });
    await db.doc("reports/r1").set({
      reporterId: UID.B,
      reportedUserId: UID.A,
      status: "open",
    });
  });
});

describe("profiles — owner vs unrelated reader", () => {
  it("owner reads and edits presentational fields on own profile", async () => {
    await allow(who.userA.db().doc(`profiles/${UID.A}`).get());
    await allow(who.userA.db().doc(`profiles/${UID.A}`).update({bio: "hello"}));
  });

  it("unrelated authenticated user reads the public dating card", async () => {
    // By product design: profiles/{uid} is the public card.
    await allow(who.userC.db().doc(`profiles/${UID.A}`).get());
  });

  it("unrelated user cannot write another profile", async () => {
    await deny(who.userC.db().doc(`profiles/${UID.A}`).update({displayName: "hijacked"}));
  });

  it("anonymous visitor cannot read any profile", async () => {
    await deny(who.anon.db().doc(`profiles/${UID.A}`).get());
  });

  it("owner cannot self-enable discovery lifecycle flags", async () => {
    await deny(who.userA.db().doc(`profiles/${UID.A}`).update({isDiscoverable: true}));
    await deny(who.userA.db().doc(`profiles/${UID.A}`).update({profileCompleted: true}));
    await deny(who.userA.db().doc(`profiles/${UID.A}`).update({onboardingCompleted: true}));
  });

  it("owner cannot inject auth secrets or GPS into the public card", async () => {
    await deny(who.userA.db().doc(`profiles/${UID.A}`).update({latitude: 41.0}));
    await deny(who.userA.db().doc(`profiles/${UID.A}`).update({geohash: "sxk9"}));
    await deny(who.userA.db().doc(`profiles/${UID.A}`).update({email: "x@y.z"}));
    await deny(who.userA.db().doc(`profiles/${UID.A}`).update({refreshToken: "t"}));
  });

  it("owner cannot flip isVerified or isAdmin on the public card", async () => {
    await deny(who.userA.db().doc(`profiles/${UID.A}`).update({isVerified: true}));
    await deny(who.userA.db().doc(`profiles/${UID.A}`).update({isAdmin: true}));
  });
});

describe("users/{uid} — private account isolation", () => {
  it("owner reads own account, nobody else can", async () => {
    await allow(who.userA.db().doc(`users/${UID.A}`).get());
    await deny(who.userC.db().doc(`users/${UID.A}`).get());
    await deny(who.anon.db().doc(`users/${UID.A}`).get());
  });

  it("moderation and billing state is locked against the owner", async () => {
    const db = who.userA.db();
    await deny(db.doc(`users/${UID.A}`).update({isBanned: true}));
    await deny(db.doc(`users/${UID.A}`).update({isSuspended: true}));
    await deny(db.doc(`users/${UID.A}`).update({isVerified: true}));
    await deny(db.doc(`users/${UID.A}`).update({accountStatus: "banned"}));
    await deny(db.doc(`users/${UID.A}`).update({boostBalance: 9999}));
    await deny(db.doc(`users/${UID.A}`).update({isSmokeTestUser: true}));
  });

  it("server-owned subcollections reject every client write", async () => {
    const db = who.userA.db();
    await deny(db.doc(`users/${UID.A}/subscription/current`).set({isPremium: true}));
    await deny(db.doc(`users/${UID.A}/verification/sumsub`).set({status: "approved"}));
    await deny(db.doc(`users/${UID.A}/boostWallet/current`).set({balance: 9999}));
    await deny(db.doc(`users/${UID.A}/matchScoreHistory/e1`).set({points: 9999}));
    await deny(db.doc(`users/${UID.A}/rateLimits/messages`).set({count: 0}));
  });

  it("private key material is rejected from the published identity doc", async () => {
    await deny(
      who.userA.db().doc(`users/${UID.A}/crypto/identity`).set({
        publicKey: "cHVibGlj",
        algorithm: "x25519",
        privateKey: "must-never-persist",
      }),
    );
  });

  it("unrelated user cannot read another user's private answers or location", async () => {
    await deny(who.userC.db().doc(`users/${UID.A}/questionAnswers/q1`).get());
    await deny(who.userC.db().doc(`userLocation/${UID.A}`).get());
    await deny(who.userC.db().doc(`users/${UID.A}/subscription/current`).get());
  });

  it("owner cannot write another user's location", async () => {
    await deny(
      who.userA.db().doc(`userLocation/${UID.C}`).set({
        uid: UID.C,
        latitude: 41.0,
        longitude: 29.0,
        geohash: "sxk9",
      }),
    );
  });
});

describe("privileged field mutation probes", () => {
  // These fields are not consumed for authorization today (admin is an Auth
  // custom claim, premium comes from subscription/current). The probes exist so
  // that stays true: the day something reads them, this suite goes red.
  const OPEN_ON_USERS = ["isPremium", "isAdmin", "isModerator", "role", "trustScore", "entitlement", "verificationStatus"];
  for (const field of OPEN_ON_USERS) {
    it(
      `users/{uid}.${field} is not client-writable`,
      knownFinding("B-04", `users/{uid}.${field} accepts a client write (denylist rule, no hasOnly)`),
      async () => {
        await deny(who.userA.db().doc(`users/${UID.A}`).update({[field]: field === "role" ? "admin" : true}));
      },
    );
  }

  const OPEN_ON_PROFILES = ["isPremium", "isModerator", "verificationStatus", "trustScore", "isBoosted"];
  for (const field of OPEN_ON_PROFILES) {
    it(
      `profiles/{uid}.${field} is not client-writable`,
      knownFinding("B-04", `profiles/{uid}.${field} accepts a client write (denylist rule, no hasOnly)`),
      async () => {
        await deny(who.userA.db().doc(`profiles/${UID.A}`).update({[field]: field === "verificationStatus" ? "approved" : true}));
      },
    );
  }

  // B-02. profiles.photos stays client-writable on purpose: Firestore rules
  // cannot validate the fields of array elements, and add/delete/reorder write
  // the whole array. Authority lives in the server-owned ledger below, which
  // enforceProfilePhotoModeration reconciles the array against — see
  // functions/test/photoModerationAuthority.test.cjs for that half.
  it("the client may still write photos[] — the array is a projection, not the authority", async () => {
    await allow(
      who.userA.db().doc(`profiles/${UID.A}`).update({
        photos: [{id: "p1", order: 0, isPrimary: true, moderationStatus: "pending"}],
      }),
    );
  });

  it("the moderation ledger is readable only by its owner and writable by nobody", async () => {
    await seed(env, async (ctx) => {
      await ctx.firestore().doc(`users/${UID.A}/photoModeration/p1`).set({
        imageId: "p1",
        status: "approved",
        moderatedBy: "system",
      });
    });
    await allow(who.userA.db().doc(`users/${UID.A}/photoModeration/p1`).get());
    await deny(who.userC.db().doc(`users/${UID.A}/photoModeration/p1`).get());
    await deny(who.anon.db().doc(`users/${UID.A}/photoModeration/p1`).get());

    await deny(
      who.userA.db().doc(`users/${UID.A}/photoModeration/p1`).set({status: "approved"}),
    );
    await deny(
      who.userA.db().doc(`users/${UID.A}/photoModeration/p1`).update({status: "approved"}),
    );
    await deny(who.userA.db().doc(`users/${UID.A}/photoModeration/p1`).delete());
    await deny(
      who.userA.db().doc(`users/${UID.A}/photoModeration/forged`).set({
        status: "approved",
        moderatedBy: "system",
      }),
    );
    await deny(
      who.userC.db().doc(`users/${UID.A}/photoModeration/p1`).set({status: "approved"}),
    );
  });
});

describe("likes — client writes are denied outright", () => {
  it("owner cannot create their own like document", async () => {
    await deny(
      who.userA.db().doc(`likes/${UID.A}_${UID.B}`).set({
        fromUserId: UID.A,
        toUserId: UID.B,
        action: "like",
      }),
    );
  });

  it("owner cannot forge a like from somebody else", async () => {
    await deny(
      who.userA.db().doc(`likes/${UID.B}_${UID.A}`).set({
        fromUserId: UID.B,
        toUserId: UID.A,
        action: "like",
      }),
    );
  });

  it("recipient cannot read incoming likes directly", async () => {
    await seed(env, async (ctx) => {
      await ctx.firestore().doc(`likes/${UID.C}_${UID.A}`).set({
        fromUserId: UID.C,
        toUserId: UID.A,
        action: "like",
      });
    });
    // Incoming likes are premium-gated through the getIncomingLikes callable.
    await deny(who.userA.db().doc(`likes/${UID.C}_${UID.A}`).get());
  });

  it("sender can read a like they sent", async () => {
    await seed(env, async (ctx) => {
      await ctx.firestore().doc(`likes/${UID.A}_${UID.C}`).set({
        fromUserId: UID.A,
        toUserId: UID.C,
        action: "like",
      });
    });
    await allow(who.userA.db().doc(`likes/${UID.A}_${UID.C}`).get());
  });
});

describe("matches — participant vs non-participant", () => {
  it("both participants read the match", async () => {
    await allow(who.userA.db().doc(`matches/${MATCH_AB}`).get());
    await allow(who.userB.db().doc(`matches/${MATCH_AB}`).get());
  });

  it("unrelated user and anonymous visitor cannot read the match", async () => {
    await deny(who.userC.db().doc(`matches/${MATCH_AB}`).get());
    await deny(who.anon.db().doc(`matches/${MATCH_AB}`).get());
  });

  it("clients cannot create a match at any document ID", async () => {
    await deny(who.userC.db().doc("matches/forged_pair").set({userIds: [UID.A, UID.B], isActive: true}));
    await deny(
      who.userA.db().doc(`matches/${UID.A}_${UID.C}`).set({userIds: [UID.A, UID.C], isActive: true}),
    );
  });

  it("participants cannot rewrite match authority fields", async () => {
    const db = who.userA.db();
    await deny(db.doc(`matches/${MATCH_AB}`).update({userIds: [UID.A, UID.C]}));
    await deny(db.doc(`matches/${MATCH_AB}`).update({isActive: false}));
    await deny(db.doc(`matches/${MATCH_AB}`).update({compatibilityScore: 100}));
    await deny(db.doc(`matches/${MATCH_AB}`).update({compatibilitySnapshots: {[UID.A]: {compatibilityScore: 1}}}));
    await deny(db.doc(`matches/${MATCH_AB}`).update({unmatchedBy: UID.B}));
  });

  it("non-participant cannot mutate the match", async () => {
    await deny(who.userC.db().doc(`matches/${MATCH_AB}`).update({lastMessage: "x"}));
  });

  it(
    "participants cannot forge the verified badge shown to the other side",
    knownFinding("B-09", "matches update freeze-list is not hasOnly; participantVerified/Names/Photos are writable"),
    async () => {
      await deny(
        who.userA.db().doc(`matches/${MATCH_AB}`).update({
          participantVerified: {[UID.A]: true, [UID.B]: false},
        }),
      );
    },
  );

  it(
    "non-participant cannot distinguish an existing match from a missing one",
    knownFinding("B-07", "get on a missing match is allowed while an existing one denies — existence oracle"),
    async () => {
      // Both probes must behave identically for a non-participant.
      await deny(who.userC.db().doc(`matches/${MATCH_AB}`).get());
      await deny(who.userC.db().doc("matches/user-x_user-y").get());
    },
  );
});

describe("messages — participant authorization and E2EE enforcement", () => {
  it("participants read the thread", async () => {
    await allow(who.userA.db().doc(`matches/${MATCH_AB}/messages/m1`).get());
    await allow(who.userB.db().doc(`matches/${MATCH_AB}/messages/m1`).get());
  });

  it("non-participant and anonymous cannot read or send", async () => {
    await deny(who.userC.db().doc(`matches/${MATCH_AB}/messages/m1`).get());
    await deny(who.anon.db().doc(`matches/${MATCH_AB}/messages/m1`).get());
    await deny(
      who.userC.db().doc(`matches/${MATCH_AB}/messages/intruder`).set(
        encryptedMessage({senderId: UID.C, receiverId: UID.B}),
      ),
    );
  });

  it("participant sends a well-formed encrypted message", async () => {
    await allow(
      who.userA.db().doc(`matches/${MATCH_AB}/messages/m2`).set(
        encryptedMessage({senderId: UID.A, receiverId: UID.B}),
      ),
    );
  });

  it("plaintext messages are rejected", async () => {
    await deny(
      who.userA.db().doc(`matches/${MATCH_AB}/messages/p1`).set({
        senderId: UID.A,
        receiverId: UID.B,
        type: "text",
        text: "plaintext must never persist",
        encrypted: false,
        createdAt: new Date(),
      }),
    );
  });

  it("an encrypted envelope carrying a non-empty text field is rejected", async () => {
    await deny(
      who.userA.db().doc(`matches/${MATCH_AB}/messages/p2`).set(
        encryptedMessage({
          senderId: UID.A,
          receiverId: UID.B,
          overrides: {text: "leaked plaintext"},
        }),
      ),
    );
  });

  it("a message missing ciphertext/nonce/mac is rejected", async () => {
    await deny(
      who.userA.db().doc(`matches/${MATCH_AB}/messages/p3`).set({
        senderId: UID.A,
        receiverId: UID.B,
        type: "text",
        encrypted: true,
        text: "",
        createdAt: new Date(),
      }),
    );
  });

  it("forged senderId is rejected", async () => {
    await deny(
      who.userA.db().doc(`matches/${MATCH_AB}/messages/p4`).set(
        encryptedMessage({senderId: UID.B, receiverId: UID.A}),
      ),
    );
  });

  it("receiverId outside the match is rejected", async () => {
    await deny(
      who.userA.db().doc(`matches/${MATCH_AB}/messages/p5`).set(
        encryptedMessage({senderId: UID.A, receiverId: UID.C}),
      ),
    );
  });

  it("media paths must live under the sender's own storage prefix", async () => {
    await deny(
      who.userA.db().doc(`matches/${MATCH_AB}/messages/p6`).set(
        encryptedMessage({
          senderId: UID.A,
          receiverId: UID.B,
          overrides: {
            type: "image",
            imageStoragePath: `users/${UID.B}/chat/${MATCH_AB}/stolen.enc`,
          },
        }),
      ),
    );
  });

  it("only the receiver may set read receipts", async () => {
    await allow(
      who.userB.db().doc(`matches/${MATCH_AB}/messages/m1`).update({isRead: true, status: "read"}),
    );
    await deny(
      who.userA.db().doc(`matches/${MATCH_AB}/messages/m1`).update({isRead: true, status: "read"}),
    );
  });

  it("messages cannot be sent into an inactive match", async () => {
    await seed(env, async (ctx) => {
      await ctx.firestore().doc(`matches/${MATCH_AB}`).set({isActive: false}, {merge: true});
    });
    await deny(
      who.userA.db().doc(`matches/${MATCH_AB}/messages/afterUnmatch`).set(
        encryptedMessage({senderId: UID.A, receiverId: UID.B}),
      ),
    );
  });
});

describe("typing indicators", () => {
  it("participant may only write their own key", async () => {
    await allow(
      who.userB.db().doc(`matches/${MATCH_AB}/meta/typing`).set({[UID.B]: new Date()}),
    );
    await deny(
      who.userB.db().doc(`matches/${MATCH_AB}/meta/typing`).set({[UID.A]: new Date()}),
    );
  });

  it("non-participant cannot read or write typing state", async () => {
    await deny(who.userC.db().doc(`matches/${MATCH_AB}/meta/typing`).get());
    await deny(who.userC.db().doc(`matches/${MATCH_AB}/meta/typing`).set({[UID.C]: new Date()}));
  });
});

describe("blocks — document identity", () => {
  it("a user creates their own canonical block", async () => {
    await allow(
      who.userA.db().doc(`blocks/${canonicalBlockId(UID.A, UID.C)}`).set({
        blockerId: UID.A,
        blockedUserId: UID.C,
        createdAt: new Date(),
      }),
    );
  });

  it("a user can remove a block they created", async () => {
    await allow(
      who.userA.db().doc(`blocks/${canonicalBlockId(UID.A, UID.C)}`).set({
        blockerId: UID.A,
        blockedUserId: UID.C,
        createdAt: new Date(),
      }),
    );
    await allow(who.userA.db().doc(`blocks/${canonicalBlockId(UID.A, UID.C)}`).delete());
  });

  it("blockerId must equal the authenticated caller", async () => {
    await deny(
      who.userC.db().doc(`blocks/${canonicalBlockId(UID.A, UID.B)}`).set({
        blockerId: UID.A,
        blockedUserId: UID.B,
        createdAt: new Date(),
      }),
    );
  });

  // B-01 regression. isBlockedPair() keys off document existence, so the
  // document ID is the authorization token and must be bound to the caller.
  it("a third party cannot create a block document naming two other users", async () => {
    await deny(
      who.userC.db().doc(`blocks/${canonicalBlockId(UID.A, UID.B)}`).set({
        blockerId: UID.C,
        blockedUserId: "someone-else",
        createdAt: new Date(),
      }),
    );
  });

  it("a caller cannot pick a document ID unrelated to the pair they are blocking", async () => {
    // Correct blockerId, but the ID names a different pair.
    await deny(
      who.userC.db().doc(`blocks/${canonicalBlockId(UID.A, UID.B)}`).set({
        blockerId: UID.C,
        blockedUserId: UID.A,
        createdAt: new Date(),
      }),
    );
    // Correct blockerId and blockedUserId, but an arbitrary ID.
    await deny(
      who.userC.db().doc("blocks/arbitrary-id").set({
        blockerId: UID.C,
        blockedUserId: UID.A,
        createdAt: new Date(),
      }),
    );
    // Canonical characters, wrong order (blocked_blocker).
    await deny(
      who.userC.db().doc(`blocks/${UID.A}_${UID.C}`).set({
        blockerId: UID.C,
        blockedUserId: UID.A,
        createdAt: new Date(),
      }),
    );
  });

  it("a top-level self-block is rejected", async () => {
    await deny(
      who.userA.db().doc(`blocks/${canonicalBlockId(UID.A, UID.A)}`).set({
        blockerId: UID.A,
        blockedUserId: UID.A,
        createdAt: new Date(),
      }),
    );
  });

  it("a malformed blockedUserId is rejected", async () => {
    await deny(
      who.userA.db().doc(`blocks/${UID.A}_`).set({
        blockerId: UID.A,
        blockedUserId: "",
        createdAt: new Date(),
      }),
    );
    await deny(
      who.userA.db().doc(`blocks/${UID.A}_123`).set({
        blockerId: UID.A,
        blockedUserId: 123,
        createdAt: new Date(),
      }),
    );
  });

  it("blocks are immutable once created", async () => {
    await allow(
      who.userA.db().doc(`blocks/${canonicalBlockId(UID.A, UID.C)}`).set({
        blockerId: UID.A,
        blockedUserId: UID.C,
        createdAt: new Date(),
      }),
    );
    await deny(
      who.userA.db().doc(`blocks/${canonicalBlockId(UID.A, UID.C)}`).update({
        blockedUserId: UID.B,
      }),
    );
  });

  it("a failed forgery attempt leaves A<->B messaging intact", async () => {
    await deny(
      who.userC.db().doc(`blocks/${canonicalBlockId(UID.A, UID.B)}`).set({
        blockerId: UID.C,
        blockedUserId: "someone-else",
        createdAt: new Date(),
      }),
    );
    await allow(
      who.userA.db().doc(`matches/${MATCH_AB}/messages/afterForgeryAttempt`).set(
        encryptedMessage({senderId: UID.A, receiverId: UID.B}),
      ),
    );
  });

  it("a legitimate block still severs messaging, and unblocking restores it", async () => {
    const blockRef = who.userA.db().doc(`blocks/${canonicalBlockId(UID.A, UID.B)}`);

    await allow(
      who.userA.db().doc(`matches/${MATCH_AB}/messages/beforeBlock`).set(
        encryptedMessage({senderId: UID.A, receiverId: UID.B}),
      ),
    );

    // A blocks B at the canonical ID the blockUser callable writes.
    await allow(blockRef.set({
      blockerId: UID.A,
      blockedUserId: UID.B,
      createdAt: new Date(),
    }));

    // Enforcement holds in both directions.
    await deny(
      who.userA.db().doc(`matches/${MATCH_AB}/messages/duringBlockAtoB`).set(
        encryptedMessage({senderId: UID.A, receiverId: UID.B}),
      ),
    );
    await deny(
      who.userB.db().doc(`matches/${MATCH_AB}/messages/duringBlockBtoA`).set(
        encryptedMessage({senderId: UID.B, receiverId: UID.A}),
      ),
    );

    // Unblock is the client-side delete settings_hub_repository performs.
    await allow(blockRef.delete());
    await allow(
      who.userA.db().doc(`matches/${MATCH_AB}/messages/afterUnblock`).set(
        encryptedMessage({senderId: UID.A, receiverId: UID.B}),
      ),
    );
  });

  it("the blocked side cannot delete the block that restrains them", async () => {
    await allow(
      who.userA.db().doc(`blocks/${canonicalBlockId(UID.A, UID.B)}`).set({
        blockerId: UID.A,
        blockedUserId: UID.B,
        createdAt: new Date(),
      }),
    );
    await deny(who.userB.db().doc(`blocks/${canonicalBlockId(UID.A, UID.B)}`).delete());
    await deny(who.userC.db().doc(`blocks/${canonicalBlockId(UID.A, UID.B)}`).delete());
  });

  it("blocked user may check that they are blocked, but cannot list", async () => {
    await seed(env, async (ctx) => {
      await ctx.firestore().doc(`users/${UID.A}/blockedUsers/${UID.C}`).set({
        blockedUserId: UID.C,
        createdAt: new Date(),
      });
    });
    await allow(who.userC.db().doc(`users/${UID.A}/blockedUsers/${UID.C}`).get());
    await deny(who.userC.db().collection(`users/${UID.A}/blockedUsers`).get());
  });

  it("self-block is rejected in the owner subcollection", async () => {
    await deny(
      who.userA.db().doc(`users/${UID.A}/blockedUsers/${UID.A}`).set({
        blockedUserId: UID.A,
        createdAt: new Date(),
      }),
    );
  });
});

describe("support, reports and notifications", () => {
  it("a user creates only their own support ticket", async () => {
    await allow(
      who.userA.db().doc("supportTickets/t1").set({
        userId: UID.A,
        status: "open",
        category: "account",
        subject: "Help",
        message: "Something is wrong",
        attachments: [],
      }),
    );
    await deny(
      who.userC.db().doc("supportTickets/t2").set({
        userId: UID.A,
        status: "open",
        category: "account",
        subject: "Impersonation",
        message: "Filed as someone else",
        attachments: [],
      }),
    );
  });

  it("guessing a ticket ID does not disclose another user's ticket", async () => {
    await seed(env, async (ctx) => {
      await ctx.firestore().doc("supportTickets/secret").set({
        userId: UID.A,
        status: "open",
        subject: "private",
        message: "private",
      });
    });
    await allow(who.userA.db().doc("supportTickets/secret").get());
    await deny(who.userC.db().doc("supportTickets/secret").get());
  });

  it("tickets are immutable to clients once filed", async () => {
    await seed(env, async (ctx) => {
      await ctx.firestore().doc("supportTickets/t3").set({userId: UID.A, status: "open"});
    });
    await deny(who.userA.db().doc("supportTickets/t3").update({status: "resolved"}));
  });

  it("the reported user cannot read or alter the report", async () => {
    await allow(who.userB.db().doc("reports/r1").get());
    await deny(who.userA.db().doc("reports/r1").get());
    await deny(who.userA.db().doc("reports/r1").update({status: "dismissed"}));
    await deny(who.userB.db().doc("reports/r1").update({status: "dismissed"}));
  });

  it("clients cannot mint notifications, only mark them read", async () => {
    await deny(who.userA.db().doc("notifications/n1").set({userId: UID.A, type: "match"}));
    await seed(env, async (ctx) => {
      await ctx.firestore().doc("notifications/n2").set({userId: UID.A, type: "match", isRead: false});
    });
    await allow(who.userA.db().doc("notifications/n2").update({isRead: true}));
    await deny(who.userA.db().doc("notifications/n2").update({type: "escalated"}));
    await deny(who.userC.db().doc("notifications/n2").get());
  });
});

describe("preferences and privacy", () => {
  it("age preference floor of 18 is enforced", async () => {
    await deny(
      who.userA.db().doc(`userPreferences/${UID.A}`).set({minAge: 16, maxAge: 40, maxDistance: 50}),
    );
    await allow(
      who.userA.db().doc(`userPreferences/${UID.A}`).set({minAge: 18, maxAge: 40, maxDistance: 50}),
    );
  });

  it("distance preference bounds are enforced", async () => {
    await deny(
      who.userA.db().doc(`userPreferences/${UID.A}`).set({minAge: 18, maxAge: 40, maxDistance: 5000}),
    );
  });

  it("preferences are private to the owner", async () => {
    await deny(who.userC.db().doc(`userPreferences/${UID.A}`).get());
  });

  // B-10 regression. The narrow documented exception is active matches: chat
  // and the match list render the peer's presence from these flags.
  it("privacy settings are not readable by unrelated users", async () => {
    await deny(who.userC.db().doc(`userPrivacy/${UID.A}`).get());
    await deny(who.anon.db().doc(`userPrivacy/${UID.A}`).get());
  });

  it("the owner still reads and updates their own privacy document", async () => {
    await allow(who.userA.db().doc(`userPrivacy/${UID.A}`).get());
    await allow(
      who.userA.db().doc(`userPrivacy/${UID.A}`).set({showOnlineStatus: false}, {merge: true}),
    );
  });

  it("an active match partner may read the peer's flags — the documented exception", async () => {
    await allow(who.userB.db().doc(`userPrivacy/${UID.A}`).get());
    await allow(who.userA.db().doc(`userPrivacy/${UID.B}`).get());
  });

  it("the exception ends when the match does", async () => {
    await seed(env, async (ctx) => {
      await ctx.firestore().doc(`matches/${MATCH_AB}`).set({isActive: false}, {merge: true});
    });
    await deny(who.userB.db().doc(`userPrivacy/${UID.A}`).get());
  });

  it("the exception does not survive a block", async () => {
    await seed(env, async (ctx) => {
      await ctx.firestore().doc(`users/${UID.A}/blockedUsers/${UID.B}`).set({
        blockedUserId: UID.B,
        createdAt: new Date(),
      });
    });
    await deny(who.userB.db().doc(`userPrivacy/${UID.A}`).get());
  });

  it("nobody can enumerate the collection or write another user's document", async () => {
    await deny(who.userC.db().collection("userPrivacy").get());
    await deny(who.userB.db().collection("userPrivacy").get());
    await deny(who.userC.db().doc(`userPrivacy/${UID.A}`).set({showOnlineStatus: true}));
    await deny(who.userB.db().doc(`userPrivacy/${UID.A}`).set({showOnlineStatus: true}));
  });

  // The rules read this document through a privileged get(), which does not
  // consult the client read rules above. Presence visibility must therefore be
  // unchanged for a non-participant.
  it("rule-internal privacy checks still drive presence visibility", async () => {
    await seed(env, async (ctx) => {
      await ctx.firestore().doc(`users/${UID.A}/presence/current`).set({
        isOnline: true,
        updatedAt: new Date(),
      });
      await ctx.firestore().doc(`userPrivacy/${UID.A}`).set({showOnlineStatus: true});
    });
    // C cannot read A's privacy document, but canReadPresence() still resolves
    // it internally and grants the presence read.
    await deny(who.userC.db().doc(`userPrivacy/${UID.A}`).get());
    await allow(who.userC.db().doc(`users/${UID.A}/presence/current`).get());

    // Flip the flags: the same internal check must now deny presence.
    await seed(env, async (ctx) => {
      await ctx.firestore().doc(`userPrivacy/${UID.A}`).set({
        showOnlineStatus: false,
        showLastSeen: false,
        showActivity: false,
      });
    });
    await deny(who.userC.db().doc(`users/${UID.A}/presence/current`).get());
    await allow(who.userA.db().doc(`users/${UID.A}/presence/current`).get());
  });
});

describe("server-owned and unknown paths", () => {
  it("third-party token stores are unreachable from any client", async () => {
    await deny(who.userA.db().doc(`spotifySecrets/${UID.A}`).get());
    await deny(who.userA.db().doc(`spotifySecrets/${UID.A}`).set({accessToken: "x"}));
    await deny(who.userA.db().doc("musicSpotifyIndex/abc").get());
    await deny(who.userA.db().doc("failedNotifications/f1").get());
  });

  it("admin surfaces reject non-admin reads", async () => {
    await deny(who.userA.db().doc("auditLogs/l1").get());
    await deny(who.userA.db().doc("automationJobs/j1").get());
    await deny(who.userA.db().doc("adminReviewQueue/i1").get());
    await deny(who.userA.db().doc("humorModerationQueue/c1").get());
  });

  it("unknown collections fall through to default deny", async () => {
    await deny(who.userA.db().doc("someUnknownCollection/x").get());
    await deny(who.userA.db().doc("someUnknownCollection/x").set({a: 1}));
    await deny(who.anon.db().doc("someUnknownCollection/x").get());
    await deny(who.userA.db().doc("users/other/unknownSub/x").get());
  });

  it("the rules file never ships an open-database clause", async () => {
    // Behavioural equivalent: an unauthenticated write anywhere must fail.
    await deny(who.anon.db().doc("profiles/anything").set({uid: "anything"}));
    await deny(who.anon.db().doc("matches/anything").set({userIds: []}));
    assert.ok(true);
  });
});
