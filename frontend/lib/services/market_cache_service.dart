import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/investment_item.dart';

class CachedValue<T> {
  const CachedValue({
    required this.value,
    required this.updatedAt,
  });

  final T value;
  final DateTime updatedAt;
}

class MarketCacheService {
  static const _investmentsKey = 'cache_market_investments';
  static const _coinsKey = 'cache_market_coins';
  static const _exchangePrefix = 'cache_exchange_';
  static const _dataSuffix = '_data';
  static const _updatedSuffix = '_updated_at';

  Future<CachedValue<List<InvestmentItem>>?> loadInvestments() async {
    return _loadInvestmentList(_investmentsKey);
  }

  Future<void> saveInvestments(List<InvestmentItem> items) async {
    await _saveInvestmentList(_investmentsKey, items);
  }

  Future<CachedValue<List<InvestmentItem>>?> loadCoins() async {
    return _loadInvestmentList(_coinsKey);
  }

  Future<void> saveCoins(List<InvestmentItem> items) async {
    await _saveInvestmentList(_coinsKey, items);
  }

  Future<CachedValue<Map<String, double>>?> loadExchangeRates(String base) async {
    final key = '$_exchangePrefix${base.toUpperCase()}';
    final prefs = await SharedPreferences.getInstance();
    final rawData = prefs.getString('$key$_dataSuffix');
    final rawUpdated = prefs.getString('$key$_updatedSuffix');
    if (rawData == null || rawUpdated == null) return null;

    try {
      final decoded = jsonDecode(rawData) as Map<String, dynamic>;
      final value = decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
      final updatedAt = DateTime.parse(rawUpdated);
      return CachedValue(value: value, updatedAt: updatedAt);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveExchangeRates(String base, Map<String, double> rates) async {
    final key = '$_exchangePrefix${base.toUpperCase()}';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$key$_dataSuffix', jsonEncode(rates));
    await prefs.setString('$key$_updatedSuffix', DateTime.now().toIso8601String());
  }

  Future<CachedValue<List<InvestmentItem>>?> _loadInvestmentList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final rawData = prefs.getString('$key$_dataSuffix');
    final rawUpdated = prefs.getString('$key$_updatedSuffix');
    if (rawData == null || rawUpdated == null) return null;

    try {
      final decoded = jsonDecode(rawData) as List<dynamic>;
      final items = decoded
          .whereType<Map<String, dynamic>>()
          .map(
            (it) => InvestmentItem(
              symbol: (it['symbol'] ?? '').toString(),
              name: (it['name'] ?? '').toString(),
              price: (it['price'] as num?)?.toDouble() ?? 0,
              currency: (it['currency'] ?? '').toString(),
              changePercent: (it['changePercent'] as num?)?.toDouble() ?? 0,
            ),
          )
          .toList();
      final updatedAt = DateTime.parse(rawUpdated);
      return CachedValue(value: items, updatedAt: updatedAt);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveInvestmentList(String key, List<InvestmentItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final serialized = items
        .map(
          (it) => {
            'symbol': it.symbol,
            'name': it.name,
            'price': it.price,
            'currency': it.currency,
            'changePercent': it.changePercent,
          },
        )
        .toList();
    await prefs.setString('$key$_dataSuffix', jsonEncode(serialized));
    await prefs.setString('$key$_updatedSuffix', DateTime.now().toIso8601String());
  }
}

