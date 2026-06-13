class TransactionItem {
  final String id;
  final double amount;
  final String description;
  final String category;
  final String account;
  final DateTime date;

  TransactionItem({
    required this.id,
    required this.amount,
    required this.description,
    required this.category,
    required this.account,
    required this.date,
  });

  factory TransactionItem.fromJson(Map<String, dynamic> json) {
    return TransactionItem(
      id: json['id'] as String,
      amount: (json['amount'] as num).toDouble(),
      description: json['description'] as String,
      category: json['category'] as String,
      account: (json['account'] as String?) ?? 'Card',
      date: DateTime.parse(json['date'] as String),
    );
  }
}
