/// Server-owned Boost balance. Clients never write this document.
class BoostWallet {
  const BoostWallet({this.balance = 0, this.updatedAt});

  final int balance;
  final DateTime? updatedAt;

  bool get hasBoosts => balance > 0;
}
