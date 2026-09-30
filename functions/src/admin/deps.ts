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
  /**
   * Creates a staff login. The password is a throwaway random value the
   * server never returns or stores; the new colleague sets their own through
   * the password-setup email the admin web asks Firebase to send.
   */
  createUser(properties: {email: string; displayName?: string; password: string; emailVerified?: boolean; disabled?: boolean}): Promise<{uid: string}>;
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

export interface AdminDeps {
  db: Firestore;
  auth: AdminAuthPort;
  bucket: () => AdminBucketPort;
  now: () => number;
}

export function defaultAdminDeps(): AdminDeps {
  return {
    db: getFirestore(),
    auth: getAuth() as unknown as AdminAuthPort,
    bucket: () => getStorage().bucket() as unknown as AdminBucketPort,
    now: () => Date.now(),
  };
}
