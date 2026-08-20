export type BoostCreditDecision =
  | {shouldCredit: true; added: number; balance: number}
  | {shouldCredit: false; alreadyProcessed: true; balance: number; added: 0}
  | {shouldCredit: false; invalidPack: true; balance: number; added: 0};

export class BoostCreditService {
  credit(params: {boostCount: number; currentBalance: number; alreadyCredited: boolean}): BoostCreditDecision {
    if (params.alreadyCredited) {
      return {shouldCredit: false, alreadyProcessed: true, balance: params.currentBalance, added: 0};
    }
    if (!Number.isFinite(params.boostCount) || params.boostCount < 1) {
      return {shouldCredit: false, invalidPack: true, balance: params.currentBalance, added: 0};
    }
    const added = Math.floor(params.boostCount);
    return {
      shouldCredit: true,
      added,
      balance: params.currentBalance + added,
    };
  }
}
