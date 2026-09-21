export {evaluatePremiumAccess} from "./entitlementPolicy.js";
export {resolvePremiumAccess} from "./entitlementResolver.js";
export {
  SubscriptionEntitlementWriter,
  decideWrite,
  defaultEntitlementFor,
  mergeEntitlement,
  type EntitlementPersistence,
} from "./entitlementWriter.js";
export {
  FirestoreEntitlementStore,
  fromDocument,
  readCanonicalSubscription,
  subscriptionDocPath,
  toDocument,
} from "./firestoreEntitlementStore.js";
export type {
  CanonicalSubscription,
  EntitlementGrant,
  EntitlementSource,
  EntitlementWriteInput,
  EntitlementWriteOutcome,
  EntitlementWriteResult,
  PremiumAccess,
  PremiumAccessReason,
  StoreEnvironment,
  StorePlatform,
  SubscriptionStatus,
} from "./types.js";
