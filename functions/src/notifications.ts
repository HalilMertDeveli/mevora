import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {onDocumentWritten} from "firebase-functions/v2/firestore";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();

/** Canonical FCM `data.type` values. Clients must not send FCM. */
export const FcmTypes = {
  newMatch: "newMatch",
  newMessage: "newMessage",
  newPhoto: "newPhoto",
  newVoice: "newVoice",
  incomingCall: "incomingCall",
  missedCall: "missedCall",
  boostActivated: "boostActivated",
  boostExpired: "boostExpired",
  streakReminder: "streakReminder",
  incomingLike: "incomingLike",
} as const;

export type FcmType = (typeof FcmTypes)[keyof typeof FcmTypes];

export type PushPrefKey =
  | "messageNotifications"
  | "matchNotifications"
  | "callNotifications"
  | "streakNotifications"
  | "likeNotifications"
  | "notificationsEnabled";

const copy: Record<FcmType, {tr: {title: string; body: string}; en: {title: string; body: string}}> = {
  newMatch: {
    tr: {title: "Mevora", body: "Yeni bir eşleşmen var!"},
    en: {title: "Mevora", body: "You have a new match!"},
  },
  newMessage: {
    tr: {title: "Mevora", body: "Yeni mesaj"},
    en: {title: "Mevora", body: "New message"},
  },
  newPhoto: {
    tr: {title: "Mevora", body: "Yeni fotoğraf"},
    en: {title: "Mevora", body: "New photo"},
  },
  newVoice: {
    tr: {title: "Mevora", body: "Yeni sesli mesaj"},
    en: {title: "Mevora", body: "New voice message"},
  },
  incomingCall: {
    tr: {title: "Mevora", body: "Gelen görüntülü arama"},
    en: {title: "Mevora", body: "Incoming video call"},
  },
  missedCall: {
    tr: {title: "Mevora", body: "Cevapsız görüntülü arama"},
    en: {title: "Mevora", body: "Missed video call"},
  },
  boostActivated: {
    tr: {title: "Mevora", body: "Boost aktif"},
    en: {title: "Mevora", body: "Boost is on"},
  },
  boostExpired: {
    tr: {title: "Mevora", body: "Boost süresi doldu"},
    en: {title: "Mevora", body: "Your Boost has ended"},
  },
  streakReminder: {
    tr: {title: "Mevora", body: "🔥 Streak'ini korumayı unutma."},
    en: {title: "Mevora", body: "🔥 Don't forget to keep your streak."},
  },
  incomingLike: {
    tr: {title: "Mevora", body: "Yeni bir beğeni"},
    en: {title: "Mevora", body: "You have a new like"},
  },
};

export async function collectDeviceTokens(uid: string): Promise<string[]> {
  const [devices, legacy] = await Promise.all([
    db.collection(`users/${uid}/devices`).get(),
    db.collection(`users/${uid}/fcmTokens`).get(),
  ]);
  const tokens = new Set<string>();
  for (const doc of [...devices.docs, ...legacy.docs]) {
    const token = String(doc.data().token ?? "");
    if (token.length > 0) {
      tokens.add(token);
    }
  }
  return [...tokens];
}

export async function sendUserPush(options: {
  uid: string;
  type: FcmType;
  data: Record<string, string>;
  prefKey: PushPrefKey;
  bodyOverride?: string;
}): Promise<void> {
  const [legacyPref, settings] = await Promise.all([
    db.doc(`users/${options.uid}/settings/notifications`).get(),
    db.doc(`userSettings/${options.uid}`).get(),
  ]);
  const prefs = {...(settings.data() ?? {}), ...(legacyPref.data() ?? {})};
  if (prefs.notificationsEnabled === false) {
    return;
  }
  if (prefs[options.prefKey] === false) {
    return;
  }
  const lang = String(prefs.languageCode ?? prefs.language ?? "en").toLowerCase().startsWith("tr")
    ? "tr"
    : "en";
  const localized = copy[options.type][lang];
  const title = localized.title;
  const body = options.bodyOverride ?? localized.body;
  const payload: Record<string, string> = {type: options.type, ...options.data};


  await db.collection("notifications").add({
    userId: options.uid,
    type: options.type,
    title,
    body,
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
    matchId: payload.matchId ?? null,
    callId: payload.callId ?? null,
    route: routeFor(options.type, payload),
  });

  const tokens = await collectDeviceTokens(options.uid);
  if (tokens.length === 0) {
    return;
  }
  try {
    await getMessaging().sendEachForMulticast({
      tokens,
      notification: {title, body},
      data: payload,
      android: {priority: "high"},
      apns: {payload: {aps: {sound: "default"}}},
    });
  } catch {
    // Push is best-effort; Firestore writes must still succeed.
  }
}

function routeFor(type: FcmType, data: Record<string, string>): string | null {
  if (type === "incomingCall" && data.callId) {
    return `/call/incoming/${data.callId}`;
  }
  if ((type === "boostActivated" || type === "boostExpired")) {
    return "/boost";
  }
  if (type === "streakReminder") {
    return "/matches";
  }
  if (data.matchId) {
    return `/chat/${data.matchId}`;
  }
  return null;
}

export const sendCallNotification = onDocumentWritten(
  {document: "calls/{callId}", region: "europe-west1"},
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after) {
      return;
    }
    const callId = event.params.callId;
    const matchId = String(after.matchId ?? "");
    const receiverId = String(after.receiverId ?? "");
    if (!receiverId) {
      return;
    }
    if (after.status === "ringing" && before?.status !== "ringing") {
      await sendUserPush({
        uid: receiverId,
        type: FcmTypes.incomingCall,
        data: {callId, matchId},
        prefKey: "callNotifications",
      });
    }
    if (after.status === "missed" && before?.status !== "missed") {
      await sendUserPush({
        uid: receiverId,
        type: FcmTypes.missedCall,
        data: {callId, matchId},
        prefKey: "callNotifications",
      });
    }
  },
);
