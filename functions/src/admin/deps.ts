import {getAuth} from "firebase-admin/auth";
import {getFirestore, type Firestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";

/**
 * The slice of Firebase Auth the admin platform uses. Declared as a port so
 * the command handlers run against an in-memory double in `npm test`.
 */
export interface AdminAuthPort {
  getUser(uid: string): Promise<{
    uid: string;
    email?: string;
    phoneNumber?: string;
    disabled: boolean;
    emailVerified?: boolean;
    customClaims?: Record<string, unknown>;
    metadata?: {creationTime?: string; lastSignInTime?: string; lastRefreshTime?: string | null};
    providerData?: Array<{providerId: string}>;
    multiFactor?: {enrolledFactors?: Array<{factorId: string}>};
  }>;
  getUserByEmail(email: string): Promise<{uid: string}>;
  getUserByPhoneNumber(phoneNumber: string): Promise<{uid: string}>;
  updateUser(uid: string, properties: {disabled?: boolean}): Promise<unknown>;
  revokeRefreshTokens(uid: string): Promise<void>;
  setCustomUserClaims(uid: string, claims: Record<string, unknown> | null): Promise<void>;
}

/** The slice of a Storage bucket the photo / attachment review paths use. */
export interface AdminBucketPort {
  name: string;
  file(path: string): {
    exists(): Promise<[boolean]>;
    download(options?: {validation?: boolean}): Promise<[Buffer]>;
    getMetadata(): Promise<[{contentType?: string; size?: string | number}]>;
    copy(destination: unknown): Promise<unknown>;
    delete(options?: {ignoreNotFound?: boolean}): Promise<unknown>;
    setMetadata(metadata: Record<string, unknown>): Promise<unknown>;
  };
  getFiles(options: {prefix: string; maxResults?: number; autoPaginate?: boolean}): Promise<[
    Array<{name: string}>,
    ...unknown[],
  ]>;
}

/** A member-facing notification the admin platform asks for. */
export interface AdminNotifyInput {
  uid: string;
  type: "supportReply";
  data: Record<string, string>;
}

export interface AdminDeps {
  db: Firestore;
  auth: AdminAuthPort;
  bucket: () => AdminBucketPort;
  now: () => number;
  /**
   * Sends a member push + in-app notification. Optional so the in-memory
   * test world runs without it; callers treat it as best-effort. The default
   * loads notifications.ts lazily — that module reads Firestore at import.
   */
  notify?: (input: AdminNotifyInput) => Promise<void>;
}

export function defaultAdminDeps(): AdminDeps {
  return {
    db: getFirestore(),
    auth: getAuth() as unknown as AdminAuthPort,
    bucket: () => getStorage().bucket() as unknown as AdminBucketPort,
    now: () => Date.now(),
    notify: async (input) => {
      const {FcmTypes, sendUserPush} = await import("../notifications.js");
      await sendUserPush({
        uid: input.uid,
        type: FcmTypes[input.type],
        data: input.data,
        // A reply to the member's own request is a service message: only the
        // master switch silences it, like an account notice.
        prefKey: "notificationsEnabled",
      });
    },
  };
}
