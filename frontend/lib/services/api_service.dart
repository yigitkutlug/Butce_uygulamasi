import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiService {
  ApiService({required this.baseUrl});

  final String baseUrl;
  static const Duration _requestTimeout = Duration(seconds: 30);

  Future<http.Response> _withNetworkErrorHandling(
      Future<http.Response> request) async {
    try {
      // Tüm HTTP istekleri aynı timeout ve ağ hatası çevirisinden geçer; ekran
      // dosyaları her endpoint için ayrı try/catch yazmak zorunda kalmaz.
      return await request.timeout(_requestTimeout);
    } on TimeoutException {
      throw const ApiException(
        'Sunucuya bağlanırken süre aşımı oldu. İnternet bağlantını kontrol edip tekrar dene.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Sunucuya ulaşılamadı. İnternet bağlantını kontrol edip tekrar dene.',
      );
    }
  }

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) {
    return _withNetworkErrorHandling(http.get(uri, headers: headers));
  }

  Future<http.Response> _post(Uri uri,
      {Map<String, String>? headers, Object? body}) {
    return _withNetworkErrorHandling(
        http.post(uri, headers: headers, body: body));
  }

  Future<http.Response> _put(Uri uri,
      {Map<String, String>? headers, Object? body}) {
    return _withNetworkErrorHandling(
        http.put(uri, headers: headers, body: body));
  }

  Future<http.Response> _delete(Uri uri, {Map<String, String>? headers}) {
    return _withNetworkErrorHandling(http.delete(uri, headers: headers));
  }

  String _detailMessage(http.Response response) {
    try {
      // FastAPI hataları genelde {"detail": "..."} formatında döner. Burada
      // backend mesajı güvenli şekilde okunup kullanıcı mesajına çevrilir.
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        final detail = body['detail'];
        if (detail is String && detail.isNotEmpty) {
          return detail;
        }
        if (detail is List && detail.isNotEmpty) {
          return 'Girdiğin bilgileri kontrol edip tekrar dene.';
        }
      }
    } catch (_) {
      // Keep the generic message when body is not JSON.
    }
    return '';
  }

  String _translateDetail(String detail, String fallback) {
    // Backend İngilizce sabit hata kodları döndürür; frontend bunları Türkçe ve
    // kullanıcı dostu metinlere çevirir.
    switch (detail) {
      case 'Invalid credentials':
        return 'Kullanıcı adı veya parola hatalı.';
      case 'Invalid token':
        return 'Oturumun süresi dolmuş olabilir. Lütfen tekrar giriş yap.';
      case 'Email already registered':
        return 'Bu e-posta adresiyle zaten bir hesap var.';
      case 'Password is too long. Use at most 72 bytes.':
        return 'Şifre çok uzun. Lütfen daha kısa bir şifre kullan.';
      default:
        return detail.isNotEmpty ? detail : fallback;
    }
  }

  String _errorMessage(String fallback, http.Response response) {
    // 401 ve 422 gibi sık durumlar endpointten bağımsız aynı açıklamayla
    // gösterilir.
    if (response.statusCode == 401) {
      return 'Oturumun süresi dolmuş olabilir. Lütfen tekrar giriş yap.';
    }
    if (response.statusCode == 422) {
      return 'Girdiğin bilgileri kontrol edip tekrar dene.';
    }
    return _translateDetail(_detailMessage(response), fallback);
  }

  bool _isSuccess(int statusCode) => statusCode >= 200 && statusCode < 300;

  Future<void> register(
      String email, String password, double monthlyIncome) async {
    final uri = Uri.parse('$baseUrl/register');
    final response = await _post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'monthly_income': monthlyIncome,
      }),
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(
        _translateDetail(_detailMessage(response),
            'Kayıt oluşturulamadı. Lütfen tekrar dene.'),
      );
    }
  }

  Future<String> login(String email, String password) async {
    final uri = Uri.parse('$baseUrl/login');
    final response = await _post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(
        _translateDetail(
            _detailMessage(response), 'Giriş yapılamadı. Lütfen tekrar dene.'),
      );
    }
    // Backend sadece access_token döndürür; token güvenli depolamaya ekran
    // tarafında yazılır.
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['access_token'] as String;
  }

  Future<List<dynamic>> getTransactions(String token) async {
    final response = await _get(
      Uri.parse('$baseUrl/transactions'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(
          _errorMessage('İşlemler alınamadı. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> addTransaction({
    required String token,
    required double amount,
    required String description,
    required DateTime date,
    String? category,
    String? account,
  }) async {
    // Kategori boş gönderilirse backend açıklamaya göre AI kategori tahmini
    // yapar; kullanıcı seçerse manuel etiket olarak kaydedilebilir.
    final response = await _post(
      Uri.parse('$baseUrl/transaction'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'amount': amount,
        'description': description,
        'date': date.toIso8601String(),
        'category': category,
        'account': account,
      }),
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(
          _errorMessage('İşlem eklenemedi. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getSummary(String token) async {
    // Dashboard'u besleyen ana endpoint: toplamlar, uyarılar, haftalık değişim
    // ve yaklaşan ödemeler bu response içinde gelir.
    final response = await _get(
      Uri.parse('$baseUrl/summary'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(_errorMessage(
          'Özet bilgileri alınamadı. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getPrediction(String token) async {
    final response = await _get(
      Uri.parse('$baseUrl/prediction'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(_errorMessage(
          'Tahmin bilgisi alınamadı. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getProfile(String token) async {
    final response = await _get(
      Uri.parse('$baseUrl/profile'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(_errorMessage(
          'Profil bilgileri alınamadı. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateConsent({
    required String token,
    required bool aiDataConsent,
  }) async {
    final response = await _put(
      Uri.parse('$baseUrl/profile/consent'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'ai_data_consent': aiDataConsent}),
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(_errorMessage(
          'Veri izni güncellenemedi. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateProfile({
    required String token,
    required double monthlyIncome,
  }) async {
    final response = await _put(
      Uri.parse('$baseUrl/profile'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'monthly_income': monthlyIncome}),
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(_errorMessage(
          'Profil güncellenemedi. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> completeOnboarding({
    required String token,
    required double monthlyIncome,
    required double essentialExpense,
    required double savingsGoal,
  }) async {
    final response = await _put(
      Uri.parse('$baseUrl/profile/onboarding'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'monthly_income': monthlyIncome,
        'essential_expense': essentialExpense,
        'savings_goal': savingsGoal,
      }),
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(_errorMessage(
          'Kurulum bilgileri kaydedilemedi. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getCategories(String token) async {
    final response = await _get(
      Uri.parse('$baseUrl/categories'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(_errorMessage(
          'Kategoriler alınamadı. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getBudgets(String token) async {
    final response = await _get(
      Uri.parse('$baseUrl/budgets'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(_errorMessage(
          'Bütçe limitleri alınamadı. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<void> updateBudget({
    required String token,
    required String category,
    required double limit,
  }) async {
    final response = await _put(
      Uri.parse('$baseUrl/budgets'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'category': category,
        'limit': limit,
      }),
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(_errorMessage(
          'Bütçe limiti güncellenemedi. Lütfen tekrar dene.', response));
    }
  }

  Future<List<dynamic>> getRecurringPayments(String token) async {
    final response = await _get(
      Uri.parse('$baseUrl/recurring'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(_errorMessage(
          'Tekrarlayan ödemeler alınamadı. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> createRecurringPayment({
    required String token,
    required String title,
    required double amount,
    required String category,
    required int dueDay,
    required String account,
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/recurring'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'title': title,
        'amount': amount,
        'category': category,
        'due_day': dueDay,
        'account': account,
        'interval': 'monthly',
      }),
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(_errorMessage(
          'Tekrarlayan ödeme eklenemedi. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setRecurringActive({
    required String token,
    required String recurringId,
    required bool isActive,
  }) async {
    final response = await _put(
      Uri.parse('$baseUrl/recurring/$recurringId/active'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'is_active': isActive}),
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(_errorMessage(
          'Tekrarlayan ödeme güncellenemedi. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Uint8List> exportCsv(String token) async {
    final response = await _get(
      Uri.parse('$baseUrl/export/csv'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(_errorMessage(
          'Rapor dışarı aktarılamadı. Lütfen tekrar dene.', response));
    }
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> getMlMetrics(String token) async {
    final response = await _get(
      Uri.parse('$baseUrl/ml/metrics'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(_errorMessage(
          'AI performans bilgileri alınamadı. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> coachChat({
    required String token,
    required String message,
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/coach/chat'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'message': message}),
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(_errorMessage(
          'AI koç yanıt veremedi. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createPriceAlert({
    required String token,
    required String symbol,
    required double targetPrice,
    required String condition,
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/alerts'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'symbol': symbol,
        'target_price': targetPrice,
        'condition': condition,
      }),
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(
          _errorMessage('Alarm oluşturulamadı. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getPriceAlerts({
    required String token,
  }) async {
    final response = await _get(
      Uri.parse('$baseUrl/alerts'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(
          _errorMessage('Alarmlar alınamadı. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> updatePriceAlert({
    required String token,
    required String alertId,
    String? symbol,
    double? targetPrice,
    String? condition,
    bool? isActive,
  }) async {
    final payload = <String, dynamic>{};
    if (symbol != null) payload['symbol'] = symbol;
    if (targetPrice != null) payload['target_price'] = targetPrice;
    if (condition != null) payload['condition'] = condition;
    if (isActive != null) payload['is_active'] = isActive;

    final response = await _put(
      Uri.parse('$baseUrl/alerts/$alertId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(
          _errorMessage('Alarm güncellenemedi. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> deletePriceAlert({
    required String token,
    required String alertId,
  }) async {
    final response = await _delete(
      Uri.parse('$baseUrl/alerts/$alertId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(
          _errorMessage('Alarm silinemedi. Lütfen tekrar dene.', response));
    }
  }

  Future<List<dynamic>> getAlertEvents({
    required String token,
    bool unreadOnly = false,
  }) async {
    final response = await _get(
      Uri.parse('$baseUrl/alerts/events?unread_only=$unreadOnly'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(_errorMessage(
          'Alarm geçmişi alınamadı. Lütfen tekrar dene.', response));
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<void> markAlertEventRead({
    required String token,
    required String eventId,
  }) async {
    final response = await _put(
      Uri.parse('$baseUrl/alerts/events/$eventId/read'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (!_isSuccess(response.statusCode)) {
      throw ApiException(_errorMessage(
          'Alarm bildirimi güncellenemedi. Lütfen tekrar dene.', response));
    }
  }
}
