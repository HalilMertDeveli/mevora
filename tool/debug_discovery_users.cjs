/**
 * Dump discovery-relevant fields for recent profiles + locations + prefs.
 * Usage: node tool/debug_discovery_users.cjs
 */
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp({projectId: "mevora-d6ed0"});
}
const db = admin.firestore();

function photoSummary(photos) {
  const list = Array.isArray(photos) ? photos : [];
  const statuses = list.map((p) => String(p.moderationStatus ?? "missing"));
  return {
    photoCount: list.length,
    photoStatuses: statuses,
    approved: statuses.filter((s) => s === "approved").length,
    pending: statuses.filter((s) => s === "pending" || s === "processing").length,
    rejected: statuses.filter((s) => s === "rejected").length,
  };
}

async function main() {
  const snap = await db.collection("profiles").limit(80).get();
  console.log("profiles_count", snap.size);

  for (const doc of snap.docs) {
    const d = doc.data() || {};
    const [loc, prefs, user, relSummary] = await Promise.all([
      db.doc(`userLocation/${doc.id}`).get(),
      db.doc(`userPreferences/${doc.id}`).get(),
      db.doc(`users/${doc.id}`).get(),
      db.doc(`users/${doc.id}/relationshipMatch/summary`).get(),
    ]);
    const locData = loc.data() || {};
    const prefsData = prefs.data() || {};
    const userData = user.data() || {};
    const rel = relSummary.data() || {};
    const photos = photoSummary(d.photos);

    console.log(
      JSON.stringify({
        uid: doc.id,
        displayName: d.displayName ?? null,
        gender: d.gender ?? null,
        interestedIn: d.interestedIn ?? null,
        age: d.age ?? null,
        isDiscoverable: d.isDiscoverable ?? null,
        profileCompleted: d.profileCompleted ?? null,
        onboardingCompleted: d.onboardingCompleted ?? null,
        profileModerationStatus: d.profileModerationStatus ?? null,
        ...photos,
        city: d.city ?? null,
        prefs: {
          preferredGender: prefsData.preferredGender ?? null,
          showMe: prefsData.showMe ?? null,
          interestedIn: prefsData.interestedIn ?? null,
          minAge: prefsData.minAge ?? null,
          maxAge: prefsData.maxAge ?? null,
          maxDistance: prefsData.maxDistance ?? null,
          discoveryEnabled: prefsData.discoveryEnabled ?? null,
        },
        location: {
          hasDoc: loc.exists,
          latitude: locData.latitude ?? null,
          longitude: locData.longitude ?? null,
          updatedAt: locData.updatedAt?.toDate?.()?.toISOString?.() ?? null,
        },
        account: {
          lastActiveAt: userData.lastActiveAt?.toDate?.()?.toISOString?.() ?? null,
          accountStatus: userData.accountStatus ?? null,
          isBanned: userData.isBanned ?? null,
          isSmokeTestUser: userData.isSmokeTestUser ?? null,
          onboardingCompleted: userData.onboardingCompleted ?? null,
        },
        relationship: {
          hasSummary: relSummary.exists,
          answerCount: Object.keys(rel.answers || {}).length,
          compatibilityKey: rel.compatibilityKey ?? null,
          setId: rel.setId ?? null,
        },
        updatedAt: d.updatedAt?.toDate?.()?.toISOString?.() ?? null,
      }),
    );
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
