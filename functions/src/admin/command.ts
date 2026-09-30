import {randomUUID} from "node:crypto";
import {FieldValue} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableFunction} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {logger} from "firebase-functions";
import {rateLimitDecision} from "../callableRateLimit.js";
import {safeLogMeta} from "../security/logHygiene.js";
import {
  EMULATOR_DEV_BFF_SECRET,
  authorizeAdminRequest,
  type AdminActor,
  type AdminAuthEnv,
  type AdminRequestLike,
} from "./auth/adminAuthorization.js";
import type {Permission} from "./auth/permissions.js";
import {defaultAdminDeps, type AdminDeps} from "./deps.js";
import {AdminError, toHttpsError} from "./errors.js";
import {asRecord} from "./validation.js";

/**
 * The one way an admin command is exposed.
 *
 * Each command is an explicit, named callable with a single declared
 * permission, a parser for its payload and a handler. There is deliberately no
 * generic "update document" command: the platform can do exactly what its
 * command list says and nothing else.
 *
 * App Check: admin commands are called server-to-server by mevora-admin-web,
 * which cannot hold an App Check token (App Check attests an app instance, not
 * a staff member). Its place is taken by the BFF credential, the staff ID
 * token, MFA, the adminStaff record, RBAC and per-staff rate limits — see
 * authorizeAdminRequest. Consumer callables keep enforceAppCheck untouched.
 */

export const adminBffSecret = defineSecret("ADMIN_BFF_SHARED_SECRET");

export const ADMIN_REGION = "europe-west1" as const;

export interface AdminCommandContext {
  actor: AdminActor;
  requestId: string;
  deps: AdminDeps;
}

export type RateClass = "read" | "search" | "mutation" | "sensitive";

/** Per staff member, per command family, fixed one-minute windows. */
export const RATE_LIMITS: Readonly<Record<RateClass, number>> = {
  read: 240,
  search: 30,
  mutation: 60,
  sensitive: 20,
};
const RATE_WINDOW_MS = 60 * 1000;

export interface AdminCommandSpec<I, O> {
  name: string;
  permission: Permission;
  rateClass: RateClass;
  parse: (raw: Record<string, unknown>) => I;
  handler: (ctx: AdminCommandContext, input: I) => Promise<O>;
}

export function resolveAdminAuthEnv(): AdminAuthEnv {
  const isEmulator = process.env.FUNCTIONS_EMULATOR === "true";
  let secret = "";
  try {
    secret = adminBffSecret.value() ?? "";
  } catch {
    secret = "";
  }
  if (!secret && isEmulator) {
    secret = process.env.ADMIN_BFF_SHARED_SECRET || EMULATOR_DEV_BFF_SECRET;
  }
  return {
    bffSecret: secret,
    // Production always requires a second factor. The Auth emulator cannot
    // complete TOTP enrolment, so local QA may run without one unless
    // ADMIN_EMULATOR_REQUIRE_MFA=true. Never true outside the emulator.
    allowMissingMfa: isEmulator && process.env.ADMIN_EMULATOR_REQUIRE_MFA !== "true",
  };
}

async function consumeAdminRateLimit(
  deps: AdminDeps,
  actorUid: string,
  rateClass: RateClass,
): Promise<void> {
  const ref = deps.db.doc(`adminRateLimits/${actorUid}_${rateClass}`);
  await deps.db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const decision = rateLimitDecision(
      snap.data() ?? null,
      deps.now(),
      RATE_WINDOW_MS,
      RATE_LIMITS[rateClass],
    );
    if (decision.action === "refuse") {
      throw new AdminError("rate_limited");
    }
    tx.set(ref, {
      windowStart: decision.windowStart,
      count: decision.count,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

/** Scrubs the payload, then attaches our own (already validated) request id verbatim. */
function withRequestId(requestId: string, meta: Record<string, unknown>): Record<string, unknown> {
  return {...safeLogMeta(meta), requestId};
}

function requestIdFrom(request: AdminRequestLike): string {
  const headers = request.rawRequest?.headers ?? {};
  const raw = headers["x-request-id"];
  const value = Array.isArray(raw) ? raw[0] : raw;
  if (typeof value === "string" && /^[A-Za-z0-9_-]{8,64}$/.test(value)) {
    return value;
  }
  return randomUUID();
}

/**
 * Runs one admin command end to end. Exported so tests drive the exact path
 * production uses, with in-memory deps and an explicit auth env.
 */
export async function runAdminCommand<I, O>(
  spec: AdminCommandSpec<I, O>,
  request: AdminRequestLike & {data?: unknown},
  deps: AdminDeps,
  env: AdminAuthEnv,
): Promise<O> {
  const requestId = requestIdFrom(request);
  const started = Date.now();
  let actorUid: string | null = null;
  try {
    const actor = await authorizeAdminRequest(request, spec.permission, deps, env);
    actorUid = actor.uid;
    await consumeAdminRateLimit(deps, actor.uid, spec.rateClass);
    const input = spec.parse(asRecord(request.data));
    const result = await spec.handler({actor, requestId, deps}, input);
    logger.info("admin_command", {
      ...safeLogMeta({command: spec.name, actorUid, outcome: "ok", durationMs: Date.now() - started}),
      // Our own validated correlation id: kept verbatim so a log line can be
      // joined to its audit event (redaction would mistake its digits for a phone).
      requestId,
    });
    return result;
  } catch (error) {
    if (error instanceof AdminError) {
      logger.warn("admin_command", withRequestId(requestId, {
        command: spec.name,
        actorUid,
        outcome: error.code,
        durationMs: Date.now() - started,
      }));
      throw toHttpsError(error, requestId);
    }
    if (error instanceof HttpsError) {
      // Raised by shared domain code (e.g. the humor moderation module).
      logger.warn("admin_command", withRequestId(requestId, {
        command: spec.name,
        actorUid,
        outcome: error.code,
      }));
      throw toHttpsError(new AdminError(mapHttpsCode(error.code), error.message), requestId);
    }
    logger.error("admin_command", withRequestId(requestId, {
      command: spec.name,
      actorUid,
      outcome: "internal_error",
      error: error instanceof Error ? error.message : String(error),
    }));
    throw toHttpsError(new AdminError("internal_error"), requestId);
  }
}

function mapHttpsCode(code: string) {
  switch (code) {
  case "not-found":
    return "not_found" as const;
  case "invalid-argument":
    return "invalid_argument" as const;
  case "permission-denied":
    return "permission_denied" as const;
  case "failed-precondition":
    return "invalid_state_transition" as const;
  default:
    return "internal_error" as const;
  }
}

/** Declares the deployable callable for one command spec. */
export function defineAdminCommand<I, O>(spec: AdminCommandSpec<I, O>): CallableFunction<unknown, Promise<O>> {
  return onCall(
    {
      region: ADMIN_REGION,
      // See the module comment: replaced by the BFF credential + staff auth.
      enforceAppCheck: false,
      secrets: [adminBffSecret],
      memory: "256MiB",
      timeoutSeconds: 60,
    },
    (request) => runAdminCommand(spec, request as unknown as AdminRequestLike & {data?: unknown}, defaultAdminDeps(), resolveAdminAuthEnv()),
  );
}
