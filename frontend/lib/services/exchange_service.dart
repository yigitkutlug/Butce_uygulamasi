import 'dart:convert';

import 'package:http/http.dart' as http;

class ExchangeService {
  static const _supported = ['USD', 'EUR', 'TRY', 'GBP'];

  Future<Map<String, double>> fetchRates({required String base}) async {
    final targets = _supported.where((c) => c != base).join(',');
    final uri = Uri.parse('https://api.frankfurter.app/latest?from=$base&to=$targets');
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to fetch exchange rates');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rates = (data['rates'] as Map<String, dynamic>);
    return rates.map((key, value) => MapEntry(key, (value as num).toDouble()));
  }
}

