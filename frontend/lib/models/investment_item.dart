class InvestmentItem {
  const InvestmentItem({
    required this.symbol,
    required this.name,
    required this.price,
    required this.currency,
    required this.changePercent,
  });

  final String symbol;
  final String name;
  final double price;
  final String currency;
  final double changePercent;
}

