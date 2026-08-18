import {getFirestore} from "firebase-admin/firestore";

export type AppLanguage = "tr" | "en";

/** UI languages only. Missing / unknown → English. */
export function languageFromCode(raw: unknown): AppLanguage {
  const code = String(raw ?? "").trim().toLowerCase();
  if (code === "tr" || code.startsWith("tr-") || code.startsWith("tr_")) {
    return "tr";
  }
  return "en";
}

export async function userLanguage(uid: string): Promise<AppLanguage> {
  const snap = await getFirestore().doc(`userSettings/${uid}`).get();
  const data = snap.data() ?? {};
  return languageFromCode(data.languageCode ?? data.language);
}
