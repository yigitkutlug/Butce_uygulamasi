import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/investment_item.dart';

class InvestmentService {
  static const _yahooSymbols = 'GC=F,SI=F,PL=F,PA=F,CL=F,NG=F,^GSPC,^IXIC,^DJI';
  static const _stooqSymbols = 'gc.f,si.f,cl.f,ng.f,^spx,^ixic,^dji';
  String? lastError;

  Future<List<InvestmentItem>> fetchInstruments() async {
    lastError = null;
    final allResults = await Future.wait<List<InvestmentItem>>([
      _tryYahoo(),
      _tryTruncgil(),
      _tryStooq(),
      _tryMetalsLive(),
      _tryGenelParaGold(),
    ]);

    for (final result in allResults) {
      if (result.isNotEmpty) return result;
    }

    lastError ??= 'Tüm kaynaklardan anlık piyasa verisi alınamadı.';
    return [];
  }

  List<InvestmentItem> get fallbackInstruments => _fallbackInstruments();

  Future<List<InvestmentItem>> _tryYahoo() async {
    try {
      final yahooUri = Uri.parse(
        'https://query1.finance.yahoo.com/v7/finance/quote?symbols=$_yahooSymbols',
      );
      final response = await http.get(
        yahooUri,
        headers: {
          'User-Agent': 'Mozilla/5.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        lastError = 'Yahoo API error: HTTP ${response.statusCode}';
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final result = (data['quoteResponse']?['result'] as List<dynamic>? ?? []);
      return result.map(_fromYahoo).whereType<InvestmentItem>().toList();
    } catch (_) {
      lastError = 'Yahoo API request failed';
      return [];
    }
  }

  InvestmentItem? _fromYahoo(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;

    final symbol = (raw['symbol'] ?? '').toString();
    final name = (raw['shortName'] ?? raw['longName'] ?? symbol).toString();
    final price = (raw['regularMarketPrice'] as num?)?.toDouble();
    final changePercent = (raw['regularMarketChangePercent'] as num?)?.toDouble() ?? 0.0;
    final currency = (raw['currency'] ?? '').toString();

    if (price == null) return null;

    return InvestmentItem(
      symbol: symbol,
      name: name,
      price: price,
      currency: currency.isEmpty ? 'USD' : currency,
      changePercent: changePercent,
    );
  }

  Future<List<InvestmentItem>> _tryStooq() async {
    try {
      final uri = Uri.parse(
        'https://stooq.com/q/l/?s=$_stooqSymbols&f=sd2t2ohlcv&h&e=csv',
      );
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'Mozilla/5.0',
          'Accept': 'text/csv',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        lastError = 'Stooq API error: HTTP ${response.statusCode}';
        return [];
      }

      final lines = const LineSplitter().convert(response.body);
      if (lines.length <= 1) return [];

      final header = lines.first.trim();
      final delimiter = header.contains(';') ? ';' : ',';
      final headers = header.split(delimiter).map((e) => e.trim().toLowerCase()).toList();
      final symbolIndex = headers.indexOf('symbol');
      final closeIndex = headers.indexOf('close');
      final safeSymbolIndex = symbolIndex >= 0 ? symbolIndex : 0;
      final safeCloseIndex = closeIndex >= 0 ? closeIndex : 6;

      final out = <InvestmentItem>[];
      for (var i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        final parts = line.split(delimiter);
        if (parts.length <= safeCloseIndex || parts.length <= safeSymbolIndex) continue;

        final symbol = parts[safeSymbolIndex].trim().toUpperCase();
        final closeRaw = parts[safeCloseIndex].trim();
        final close = _parseFlexibleNumber(closeRaw);
        if (close == null) continue;

        out.add(
          InvestmentItem(
            symbol: symbol,
            name: _stooqName(symbol),
            price: close,
            currency: 'USD',
            changePercent: 0,
          ),
        );
      }

      return out;
    } catch (_) {
      lastError = 'Stooq API request failed';
      return [];
    }
  }

  Future<List<InvestmentItem>> _tryMetalsLive() async {
    try {
      final uri = Uri.parse('https://api.metals.live/v1/spot');
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'Mozilla/5.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        lastError = 'Metals Live API error: HTTP ${response.statusCode}';
        return [];
      }

      final body = jsonDecode(response.body);
      if (body is! List) {
        return [];
      }

      double? xau;
      double? xag;
      for (final item in body) {
        if (item is! Map) continue;
        final key = item.keys.isNotEmpty ? item.keys.first.toString().toLowerCase() : '';
        final rawValue = item.values.isNotEmpty ? item.values.first : null;
        final parsed = _parseFlexibleNumber(rawValue?.toString() ?? '');
        if (parsed == null) continue;
        if (key == 'gold') xau = parsed;
        if (key == 'silver') xag = parsed;
      }

      final out = <InvestmentItem>[];
      if (xau != null) {
        out.add(
          InvestmentItem(
            symbol: 'XAUUSD',
            name: 'Gold Spot',
            price: xau,
            currency: 'USD',
            changePercent: 0,
          ),
        );
      }
      if (xag != null) {
        out.add(
          InvestmentItem(
            symbol: 'XAGUSD',
            name: 'Silver Spot',
            price: xag,
            currency: 'USD',
            changePercent: 0,
          ),
        );
      }
      return out;
    } catch (_) {
      lastError = 'Metals Live API request failed';
      return [];
    }
  }

  Future<List<InvestmentItem>> _tryTruncgil() async {
    try {
      final uri = Uri.parse('https://finans.truncgil.com/today.json');
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'Mozilla/5.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        lastError = 'Truncgil API error: HTTP ${response.statusCode}';
        return [];
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return [];

      final out = <InvestmentItem>[];
      _addTruncgilItem(out, body, code: 'gram-altin', symbol: 'XAU-TRY', name: 'Gram Altın');
      _addTruncgilItem(out, body, code: 'ceyrek-altin', symbol: 'CEYREK-TRY', name: 'Çeyrek Altın');
      _addTruncgilItem(out, body, code: 'yarim-altin', symbol: 'YARIM-TRY', name: 'Yarım Altın');
      _addTruncgilItem(out, body, code: 'tam-altin', symbol: 'TAM-TRY', name: 'Tam Altın');
      _addTruncgilItem(out, body, code: 'gumus', symbol: 'XAG-TRY', name: 'Gümüş');
      _addTruncgilItem(out, body, code: 'ons', symbol: 'XAU-USD', name: 'Altın Ons');

      return out;
    } catch (_) {
      lastError = 'Truncgil API request failed';
      return [];
    }
  }

  Future<List<InvestmentItem>> _tryGenelParaGold() async {
    try {
      final uri = Uri.parse(
        'https://api.genelpara.com/json/?list=altin&sembol=GA,C,Y,T,GAG,XAUUSD',
      );
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'Mozilla/5.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        lastError = 'GenelPara API error: HTTP ${response.statusCode}';
        return [];
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return [];
      final data = body['data'];
      if (data is! Map<String, dynamic>) {
        lastError = 'GenelPara API response format unexpected';
        return [];
      }

      final out = <InvestmentItem>[];
      _addGenelParaItem(out, data, code: 'GA', symbol: 'XAU-TRY', name: 'Gram Altın', currency: 'TRY');
      _addGenelParaItem(out, data, code: 'C', symbol: 'CEYREK-TRY', name: 'Çeyrek Altın', currency: 'TRY');
      _addGenelParaItem(out, data, code: 'Y', symbol: 'YARIM-TRY', name: 'Yarım Altın', currency: 'TRY');
      _addGenelParaItem(out, data, code: 'T', symbol: 'TAM-TRY', name: 'Tam Altın', currency: 'TRY');
      _addGenelParaItem(out, data, code: 'GAG', symbol: 'XAG-TRY', name: 'Gram Gümüş', currency: 'TRY');
      _addGenelParaItem(out, data, code: 'XAUUSD', symbol: 'XAUUSD', name: 'Ons Altın', currency: 'USD');

      return out;
    } catch (_) {
      lastError = 'GenelPara API request failed';
      return [];
    }
  }

  void _addTruncgilItem(
    List<InvestmentItem> out,
    Map<String, dynamic> raw, {
    required String code,
    required String symbol,
    required String name,
  }) {
    final item = raw[code];
    if (item is! Map<String, dynamic>) return;
    final buyRaw = (item['Alis'] ?? item['Satis'] ?? '').toString();
    final value = _parseNumber(buyRaw);
    if (value == null) return;

    out.add(
      InvestmentItem(
        symbol: symbol,
        name: name,
        price: value,
        currency: symbol.endsWith('-TRY') ? 'TRY' : 'USD',
        changePercent: 0,
      ),
    );
  }

  void _addGenelParaItem(
    List<InvestmentItem> out,
    Map<String, dynamic> raw, {
    required String code,
    required String symbol,
    required String name,
    required String currency,
  }) {
    final item = raw[code];
    if (item is! Map<String, dynamic>) return;
    final buyRaw = (item['alis'] ?? item['satis'] ?? item['Alis'] ?? item['Satis'] ?? '').toString();
    final value = _parseFlexibleNumber(buyRaw);
    if (value == null) return;

    final changeRaw = (item['degisim'] ?? item['Degisim'] ?? '0').toString().replaceAll('%', '');
    final change = _parseFlexibleNumber(changeRaw) ?? 0;

    out.add(
      InvestmentItem(
        symbol: symbol,
        name: name,
        price: value,
        currency: currency,
        changePercent: change,
      ),
    );
  }

  double? _parseNumber(String value) {
    final normalized = value.replaceAll('.', '').replaceAll(',', '.').trim();
    return double.tryParse(normalized);
  }

  double? _parseFlexibleNumber(String value) {
    final raw = value.trim();
    if (raw.isEmpty || raw.toUpperCase() == 'N/D' || raw == '-') return null;

    final bothSeparators = raw.contains('.') && raw.contains(',');
    if (bothSeparators) {
      return _parseNumber(raw);
    }

    final normalized = raw.replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  String _stooqName(String symbol) {
    switch (symbol) {
      case 'GC.F':
        return 'Gold Futures';
      case 'SI.F':
        return 'Silver Futures';
      case 'CL.F':
        return 'Crude Oil Futures';
      case 'NG.F':
        return 'Natural Gas Futures';
      case '^SPX':
        return 'S&P 500';
      case '^IXIC':
        return 'NASDAQ Composite';
      case '^DJI':
        return 'Dow Jones Industrial Average';
      default:
        return symbol;
    }
  }

  List<InvestmentItem> _fallbackInstruments() {
    return const [
      InvestmentItem(symbol: 'XAU-TRY', name: 'Gram Altın', price: 0, currency: 'TRY', changePercent: 0),
      InvestmentItem(symbol: 'XAG-TRY', name: 'Gümüş', price: 0, currency: 'TRY', changePercent: 0),
      InvestmentItem(symbol: 'GC=F', name: 'Gold Futures', price: 0, currency: 'USD', changePercent: 0),
      InvestmentItem(symbol: 'SI=F', name: 'Silver Futures', price: 0, currency: 'USD', changePercent: 0),
      InvestmentItem(symbol: 'PL=F', name: 'Platinum Futures', price: 0, currency: 'USD', changePercent: 0),
      InvestmentItem(symbol: 'PA=F', name: 'Palladium Futures', price: 0, currency: 'USD', changePercent: 0),
      InvestmentItem(symbol: 'CL=F', name: 'Crude Oil Futures', price: 0, currency: 'USD', changePercent: 0),
      InvestmentItem(symbol: 'NG=F', name: 'Natural Gas Futures', price: 0, currency: 'USD', changePercent: 0),
      InvestmentItem(symbol: '^GSPC', name: 'S&P 500', price: 0, currency: 'USD', changePercent: 0),
      InvestmentItem(symbol: '^IXIC', name: 'NASDAQ Composite', price: 0, currency: 'USD', changePercent: 0),
      InvestmentItem(symbol: '^DJI', name: 'Dow Jones Industrial Average', price: 0, currency: 'USD', changePercent: 0),
    ];
  }
}
