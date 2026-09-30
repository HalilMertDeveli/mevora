import type {Firestore} from "firebase-admin/firestore";
import type {AdminActor} from "../auth/adminAuthorization.js";
import type {AdminDeps} from "../deps.js";
import {AdminError} from "../errors.js";
import {cursorPart, decodeCursor, encodeCursor, iso} from "../validation.js";
import {loadUserCards, maskEmail, maskPhone, type UserCard} from "./userCards.js";
import {LOOKUP_COLLECTION, foldSearchText} from "./userLookup.js";

/**
 * Staff user search.
 *
 * - uid          exact document read
 * - email        exact Firebase Auth lookup (no prefix search: the console must
 *                not become an address-enumeration tool)
 * - phone        exact Firebase Auth lookup, E.164 only
 * - name         folded prefix query over adminUserLookup, cursor-paginated
 * - status       users by accountStatus (suspended / banned), newest first
 *
 * Every mode is bounded; nothing downloads the users collection.
 */
export const SEARCH_MODES = ["auto", "uid", "email", "phone", "name", "status"] as const;
export type SearchMode = (typeof SEARCH_MODES)[number];

export interface SearchInput {
  query: string;
  mode: SearchMode;
  status: "suspended" | "banned" | null;
  cursor: unknown;
  limit: number;
}

export interface SearchResultRow extends UserCard {
  matchedBy: string;
  email: string | null;
  phone: string | null;
  statusUpdatedAt: string | null;
}

export function detectMode(query: string): Exclude<SearchMode, "auto" | "status"> {
  if (query.includes("@")) {
    return "email";
  }
  if (/^\+\d[\d\s()-]{6,}$/.test(query)) {
    return "phone";
  }
  if (/^[A-Za-z0-9]{20,128}$/.test(query)) {
    return "uid";
  }
  return "name";
}

export function normalizePhone(raw: string): string | null {
  const digits = raw.replace(/[\s()-]/g, "");
  return /^\+\d{8,15}$/.test(digits) ? digits : null;
}

async function authLookup(
  deps: AdminDeps,
  kind: "email" | "phone",
  value: string,
): Promise<string | null> {
  try {
    const record = kind === "email"
      ? await deps.auth.getUserByEmail(value)
      : await deps.auth.getUserByPhoneNumber(value);
    return record.uid;
  } catch (error) {
    const code = (error as {code?: string}).code;
    if (code === "auth/user-not-found" || code === "auth/invalid-email" || code === "auth/invalid-phone-number") {
      return null;
    }
    throw error;
  }
}

async function rowsFor(
  db: Firestore,
  uids: string[],
  matchedBy: string,
  nowMs: number,
): Promise<SearchResultRow[]> {
  const cards = await loadUserCards(db, uids, nowMs);
  const accounts = uids.length ? await db.getAll(...uids.map((u) => db.doc(`users/${u}`))) : [];
  return uids
    .map((u, index) => {
      const card = cards.get(u);
      if (!card || !card.exists) {
        return null;
      }
      const account = accounts[index]?.data() ?? {};
      return {
        ...card,
        matchedBy,
        // Search results are always masked; the sensitive overview is the
        // only (audited) place a full identifier is shown.
        email: maskEmail(account.email),
        phone: maskPhone(account.phoneNumber),
        statusUpdatedAt: iso(account.statusUpdatedAt),
      } satisfies SearchResultRow;
    })
    .filter((row): row is SearchResultRow => row !== null);
}

export async function searchUsers(
  deps: AdminDeps,
  _actor: AdminActor,
  input: SearchInput,
): Promise<{items: SearchResultRow[]; nextCursor: string | null; mode: string}> {
  const {db} = deps;
  const nowMs = deps.now();
  const query = input.query.trim();
  const mode = input.mode === "auto" ? (input.status ? "status" : detectMode(query)) : input.mode;

  if (mode === "status") {
    if (!input.status) {
      throw new AdminError("invalid_argument", "status");
    }
    const after = decodeCursor(input.cursor, 2);
    let q = db.collection("users")
      .where("accountStatus", "==", input.status)
      .orderBy("statusUpdatedAt", "desc")
      .orderBy("__name__", "desc")
      .limit(input.limit);
    if (after) {
      q = q.startAfter(...after);
    }
    const snap = await q.get();
    const items = await rowsFor(db, snap.docs.map((d) => d.id), "status", nowMs);
    const last = snap.docs[snap.docs.length - 1];
    return {
      items,
      nextCursor: snap.docs.length === input.limit && last
        ? encodeCursor([cursorPart(last.get("statusUpdatedAt")), last.id])
        : null,
      mode,
    };
  }

  if (query.length < 2 || query.length > 128) {
    throw new AdminError("invalid_argument", "query");
  }

  if (mode === "uid") {
    return {items: await rowsFor(db, [query], "uid", nowMs), nextCursor: null, mode};
  }
  if (mode === "email") {
    const found = await authLookup(deps, "email", query.toLowerCase());
    return {items: found ? await rowsFor(db, [found], "email", nowMs) : [], nextCursor: null, mode};
  }
  if (mode === "phone") {
    const phone = normalizePhone(query);
    if (!phone) {
      throw new AdminError("invalid_argument", "phone");
    }
    const found = await authLookup(deps, "phone", phone);
    return {items: found ? await rowsFor(db, [found], "phone", nowMs) : [], nextCursor: null, mode};
  }

  const prefix = foldSearchText(query);
  if (prefix.length < 2) {
    throw new AdminError("invalid_argument", "query");
  }
  const after = decodeCursor(input.cursor, 2);
  let q = db.collection(LOOKUP_COLLECTION)
    .where("displayNameLower", ">=", prefix)
    .where("displayNameLower", "<", `${prefix}`)
    .orderBy("displayNameLower")
    .orderBy("__name__")
    .limit(input.limit);
  if (after) {
    q = q.startAfter(...after);
  }
  const snap = await q.get();
  const uids = snap.docs.map((d) => d.id);
  // A bare uid-looking query that also names nobody by display name still
  // resolves the uid, so the console needs no mode picker for the common case.
  if (input.mode === "auto" && !uids.length && /^[A-Za-z0-9_-]{6,128}$/.test(query)) {
    const direct = await rowsFor(db, [query], "uid", nowMs);
    if (direct.length) {
      return {items: direct, nextCursor: null, mode: "uid"};
    }
  }
  const items = await rowsFor(db, uids, "name", nowMs);
  const last = snap.docs[snap.docs.length - 1];
  return {
    items,
    nextCursor: snap.docs.length === input.limit && last
      ? encodeCursor([String(last.get("displayNameLower") ?? ""), last.id])
      : null,
    mode: "name",
  };
}
