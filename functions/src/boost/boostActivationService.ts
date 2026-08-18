import {ALLOW_STACKING, BOOST_PRODUCTS} from "./config.js";
import type {ActiveBoostSnapshot} from "./types.js";

export type ActivationDecision =
  | {shouldActivate: true; startedAt: Date; expiresAt: Date}
  | {shouldActivate: false; alreadyActive: true};

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

  decide(params: {now: Date; currentActive: ActiveBoostSnapshot | null}): ActivationDecision {
    if (params.currentActive && this.isActive(params.currentActive, params.now) && !this.allowStacking) {
      return {shouldActivate: false, alreadyActive: true};
    }
    const startedAt = params.now;
    return {
      shouldActivate: true,
      startedAt,
      expiresAt: new Date(startedAt.getTime() + this.durationMs),
    };
  }
}
