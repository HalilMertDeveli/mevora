import 'package:mevora/features/boost/domain/config/boost_pack_catalog.dart';
import 'package:mevora/features/boost/domain/entities/boost_pack.dart';

class BoostCreditDecision {
  const BoostCreditDecision._({
    required this.shouldCredit,
    required this.added,
    required this.balance,
    this.alreadyProcessed = false,
    this.invalidPack = false,
  });

  factory BoostCreditDecision.credited({
    required int added,
    required int balance,
  }) {
    return BoostCreditDecision._(
      shouldCredit: true,
      added: added,
      balance: balance,
    );
  }

  factory BoostCreditDecision.idempotent(int balance) {
    return BoostCreditDecision._(
      shouldCredit: false,
      added: 0,
      balance: balance,
      alreadyProcessed: true,
    );
  }

  factory BoostCreditDecision.invalidPack(int balance) {
    return BoostCreditDecision._(
      shouldCredit: false,
      added: 0,
      balance: balance,
      invalidPack: true,
    );
  }

  final bool shouldCredit;
  final int added;
  final int balance;
  final bool alreadyProcessed;
  final bool invalidPack;
}

/// Maps a verified store SKU onto wallet credit. Idempotent on purchase id.
class BoostCreditService {
  const BoostCreditService({this.catalog});

  final List<BoostPack>? catalog;

  BoostCreditDecision credit({
    required String productId,
    required int currentBalance,
    required bool alreadyCredited,
  }) {
    if (alreadyCredited) {
      return BoostCreditDecision.idempotent(currentBalance);
    }
    final pack = BoostPackCatalog.packFor(productId, catalog: catalog);
    if (pack == null || pack.boostCount < 1) {
      return BoostCreditDecision.invalidPack(currentBalance);
    }
    return BoostCreditDecision.credited(
      added: pack.boostCount,
      balance: currentBalance + pack.boostCount,
    );
  }
}
