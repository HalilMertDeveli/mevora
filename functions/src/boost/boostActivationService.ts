import {ALLOW_STACKING, BOOST_PRODUCTS} from "./config.js";
import type {ActiveBoostSnapshot} from "./types.js";

export type ActivationDecision =
  | {shouldActivate: true; startedAt: Date; expiresAt: Date; extendBoostId?: string}
  | {shouldActivate: false; alreadyActive: true}
  | {shouldActivate: false; insufficientBalance: true};

export class BoostActivationService {
  constructor(
    private readonly allowStacking = ALLOW_STACKING,
    private readonly durationMs = BOOST_PRODUCTS.durationMs,
  ) {}

  activeBoost(boosts: ActiveBoostSnapshot[], now: Date): ActiveBoostSnapshot | null {
    for (const boost of boosts) {
      if (this.isActive(boost, now)) {
        return boost;
      }
    }
    return null;
  }

  isActive(boost: ActiveBoostSnapshot, now: Date): boolean {
    if (boost.status !== "active") {
      return false;
    }
    if (!boost.expiresAt) {
      return false;
    }
    return boost.expiresAt.getTime() > now.getTime();
  }

  decide(params: {
    now: Date;
    currentActive: ActiveBoostSnapshot | null;
    balance?: number;
    durationMs?: number;
    requireBalance?: boolean;
  }): ActivationDecision {
    const grantMs = params.durationMs ?? this.durationMs;
    if (!Number.isFinite(grantMs) || grantMs <= 0) {
      return {shouldActivate: false, insufficientBalance: true};
    }
    const live =
      params.currentActive && this.isActive(params.currentActive, params.now)
        ? params.currentActive
        : null;
    if (live && !this.allowStacking) {
      return {shouldActivate: false, alreadyActive: true};
    }
    if (params.requireBalance && (params.balance ?? 0) < 1) {
      return {shouldActivate: false, insufficientBalance: true};
    }
    const base = live?.expiresAt ?? params.now;
    return {
      shouldActivate: true,
      startedAt: live?.startedAt ?? params.now,
      expiresAt: new Date(base.getTime() + grantMs),
      extendBoostId: live?.boostId,
    };
  }
}
