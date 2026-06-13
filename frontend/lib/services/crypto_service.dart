import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/investment_item.dart';

class CryptoService {
  Future<List<InvestmentItem>> fetchCoins() async {
    final uri = Uri.parse(
      'https://api.coingecko.com/api/v3/coins/markets'
      '?vs_currency=usd&order=market_cap_desc&per_page=20&page=1&sparkline=false'
      '&price_change_percentage=24h',
    );
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to fetch market data');
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(
          (item) => InvestmentItem(
            symbol: (item['symbol'] ?? '').toString().toUpperCase(),
            name: (item['name'] ?? '').toString(),
            price: (item['current_price'] as num?)?.toDouble() ?? 0.0,
            currency: 'USD',
            changePercent: (item['price_change_percentage_24h'] as num?)?.toDouble() ?? 0.0,
          ),
        )
        .toList();
  }
}

