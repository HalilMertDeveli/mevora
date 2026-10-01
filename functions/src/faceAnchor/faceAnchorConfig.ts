import {defineString} from "firebase-functions/params";

/**
 * Server-side switches for Face Anchor. None of these is readable or settable
 * by a client, and none is a secret.
 */

/**
 * Whether a new member must have a verified Face Anchor to finish onboarding.
 *
 * `on` or `off`. Left unset it is off in a deployment, and deliberately so:
 * turning the rule on before the app that can satisfy it is in members' hands
 * — or before a live verification provider is configured — would stop every
 * sign-up. The owner switches it on once both are true. Unset in the emulator
 * it is on, so the rule is what gets tested.
 *
 * The default is empty rather than "off" because the Functions emulator copies
 * a param's default into the environment: "off" would then be indistinguishable
 * from someone having asked for off.
 */
export const faceAnchorEnforcement = defineString("FACE_ANCHOR_ENFORCEMENT", {default: ""});

/**
 * Didit declines a face match scoring at or below this (0–100). Didit's own
 * default of 30 is described by them as permissive; 50 is the low end of what
 * they suggest for stricter checks.
 */
export const faceAnchorMatchThreshold = defineString("FACE_ANCHOR_MATCH_THRESHOLD", {default: "50"});

/** Didit declines a liveness score at or below this (0–100). 30 is Didit's default. */
export const faceAnchorLivenessThreshold = defineString("FACE_ANCHOR_LIVENESS_THRESHOLD", {default: "30"});

/**
 * Billed verifications allowed across all members per UTC day. Per-member
 * limits do not bound the bill when many accounts are involved; this does.
 */
export const faceAnchorDailyGlobalCap = defineString("FACE_ANCHOR_DAILY_GLOBAL_CAP", {default: "2000"});

export function isEmulatorProcess(): boolean {
  return process.env.FUNCTIONS_EMULATOR === "true";
}

function read(envKey: string, param: ReturnType<typeof defineString>, fallback: string): string {
  const fromEnv = process.env[envKey]?.trim();
  if (fromEnv) {
    return fromEnv;
  }
  try {
    return (param.value() || fallback).trim();
  } catch {
    return fallback;
  }
}

export function isFaceAnchorEnforced(): boolean {
  const setting = read("FACE_ANCHOR_ENFORCEMENT", faceAnchorEnforcement, "").toLowerCase();
  if (setting === "on") {
    return true;
  }
  if (setting === "off") {
    return false;
  }
  // Unset, or a word that is neither: on in the emulator, off when deployed.
  return isEmulatorProcess();
}

function threshold(envKey: string, param: ReturnType<typeof defineString>, fallback: number): number {
  const value = Number(read(envKey, param, String(fallback)));
  // Out of range would be rejected by Didit with a 400 on every request.
  return Number.isFinite(value) && value >= 0 && value <= 100 ? value : fallback;
}

export function resolveMatchThreshold(): number {
  return threshold("FACE_ANCHOR_MATCH_THRESHOLD", faceAnchorMatchThreshold, 50);
}

export function resolveLivenessThreshold(): number {
  return threshold("FACE_ANCHOR_LIVENESS_THRESHOLD", faceAnchorLivenessThreshold, 30);
}

export function resolveDailyGlobalCap(): number {
  const value = Number(read("FACE_ANCHOR_DAILY_GLOBAL_CAP", faceAnchorDailyGlobalCap, "2000"));
  return Number.isFinite(value) && value >= 0 ? Math.floor(value) : 2000;
}
