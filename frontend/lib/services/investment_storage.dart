import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class InvestmentStorage {
  static const _favoritesKey = 'investment_favorite_symbols';
  static const _positionsKey = 'investment_positions';

  Future<Set<String>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_favoritesKey) ?? const <String>[];
    return list.map((e) => e.toUpperCase()).toSet();
  }

  Future<void> saveFavorites(Set<String> symbols) async {
    final prefs = await SharedPreferences.getInstance();
    final ordered = symbols.toList()..sort();
    await prefs.setStringList(_favoritesKey, ordered);
  }

  Future<Map<String, Map<String, double>>> loadPositions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_positionsKey);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return {};

    final out = <String, Map<String, double>>{};
    for (final entry in decoded.entries) {
      final key = entry.key.toUpperCase();
      final value = entry.value;
      if (value is! Map<String, dynamic>) continue;
      final quantity = (value['quantity'] as num?)?.toDouble();
      final avgPrice = (value['avg_price'] as num?)?.toDouble();
      if (quantity == null || avgPrice == null) continue;
      out[key] = {
        'quantity': quantity,
        'avg_price': avgPrice,
      };
    }
    return out;
  }

  Future<void> savePositions(Map<String, Map<String, double>> positions) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, Map<String, double>>{};
    for (final entry in positions.entries) {
      payload[entry.key.toUpperCase()] = {
        'quantity': entry.value['quantity'] ?? 0,
        'avg_price': entry.value['avg_price'] ?? 0,
      };
    }
    await prefs.setString(_positionsKey, jsonEncode(payload));
  }
}
