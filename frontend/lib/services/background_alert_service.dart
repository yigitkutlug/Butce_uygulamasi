import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'api_service.dart';
import 'settings_storage.dart';
import 'token_storage.dart';

const String _apiFromEnv = String.fromEnvironment('API_BASE_URL');
const String _productionApi = 'https://budget-tracker-api-anv1.onrender.com';
const String _androidEmulatorApi = 'http://10.0.2.2:8000';
const String _localApi = 'http://127.0.0.1:8000';

String _normalizeApiBaseUrl(String raw) {
  var value = raw.trim();
  if (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  for (final suffix in const ['/docs', '/redoc', '/openapi.json']) {
    if (value.endsWith(suffix)) {
      value = value.substring(0, value.length - suffix.length);
      break;
    }
  }
  return value;
}

String _resolveApiBaseUrl() {
  if (_apiFromEnv.isNotEmpty) return _normalizeApiBaseUrl(_apiFromEnv);
  if (kReleaseMode) return _productionApi;
  if (kIsWeb) return _localApi;
  return defaultTargetPlatform == TargetPlatform.android
      ? _androidEmulatorApi
      : _localApi;
}

@pragma('vm:entry-point')
void backgroundAlertDispatcher() {
  // Workmanager arka planda ayrı bir isolate başlatabildiği için giriş noktası
  // top-level tutulur ve gerekli Flutter servisleri burada yeniden hazırlanır.
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await BackgroundAlertService.instance.ensureInitialized();
    await BackgroundAlertService.instance.checkAlertsAndNotify();
    return true;
  });
}

class BackgroundAlertService {
  BackgroundAlertService._();

  static final BackgroundAlertService instance = BackgroundAlertService._();

  static const String taskName = 'price_alert_background_task';
  static const Duration _financialReminderInterval = Duration(days: 5);
  static const String _notificationChannelId = 'price_alert_channel';
  static const String _notificationChannelName = 'Fiyat Alarmları';
  static const String _notificationChannelDescription =
      'Yatırım fiyat alarm bildirimleri';

  static const String _financialNotificationChannelId =
      'financial_reminder_channel';
  static const String _financialNotificationChannelName =
      'Bütçe Hatırlatmaları';
  static const String _financialNotificationChannelDescription =
      'Beş günde bir bütçe durumu hatırlatmaları';
  static const String _lastFinancialReminderKey = 'last_financial_reminder_at';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> bootstrap() async {
    if (kIsWeb) return;
    await ensureInitialized();
    // Fiyat alarmları hızlı kontrol edilir; finans hatırlatıcısı ise aynı işin
    // içinde ayrıca 5 günlük yerel zaman kilidiyle sınırlandırılır.
    await Workmanager().initialize(
      backgroundAlertDispatcher,
      isInDebugMode: false,
    );
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 2),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
    await checkAlertsAndNotify();
  }

  Future<void> ensureInitialized() async {
    if (_initialized || kIsWeb) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _notifications.initialize(settings);
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  Future<void> checkAlertsAndNotify() async {
    if (kIsWeb) return;
    try {
      final token = await TokenStorage().getToken();
      if (token == null || token.isEmpty) return;

      final api = ApiService(baseUrl: _resolveApiBaseUrl());
      final events = await api.getAlertEvents(token: token, unreadOnly: true);
      if (events.isNotEmpty) {
        // Okunmamış fiyat alarmı olayları bildirime çevrilir ve tekrar
        // gösterilmemesi için backend tarafında okundu işaretlenir.
        for (final raw in events) {
          if (raw is! Map<String, dynamic>) continue;
          final id = (raw['id'] ?? '').toString();
          final message =
              (raw['message'] ?? 'Fiyat alarmın tetiklendi.').toString();
          final symbol = (raw['symbol'] ?? 'Piyasa').toString();

          await _showNotification(
            id: id,
            title: '$symbol alarmı',
            body: message,
          );

          if (id.isNotEmpty) {
            await api.markAlertEventRead(token: token, eventId: id);
          }
        }
      }

      await _checkFinancialReminderAndNotify(api: api, token: token);
    } catch (_) {
      // Background task must fail silently.
    }
  }

  Future<void> _checkFinancialReminderAndNotify({
    required ApiService api,
    required String token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // Bu ayar arka plan servisinden de okunur; böylece kullanıcı kapattığında
    // uygulama açık olmasa bile bütçe hatırlatıcısı gönderilmez.
    final enabled = prefs.getBool(
          SettingsStorage.financialRemindersEnabledKey,
        ) ??
        true;
    if (!enabled) return;

    final now = DateTime.now();
    final lastRaw = prefs.getString(_lastFinancialReminderKey);
    final lastSent = lastRaw == null ? null : DateTime.tryParse(lastRaw);
    // Workmanager sistem tarafından sık uyandırılabilir; gerçek 5 günlük
    // periyot bu yerel kayıtla garanti altına alınır.
    if (lastSent != null &&
        now.difference(lastSent) < _financialReminderInterval) {
      return;
    }

    final summary = await api.getSummary(token);
    final reminder = _buildFinancialReminder(summary);
    await _showNotification(
      id: 'financial-reminder-${now.millisecondsSinceEpoch}',
      title: reminder.title,
      body: reminder.body,
      channelId: _financialNotificationChannelId,
      channelName: _financialNotificationChannelName,
      channelDescription: _financialNotificationChannelDescription,
    );
    await prefs.setString(_lastFinancialReminderKey, now.toIso8601String());
  }

  _FinancialReminder _buildFinancialReminder(Map<String, dynamic> summary) {
    // Dashboard özetindeki bütçe ve gelir/hedef oranları kullanılarak kısa,
    // aksiyon alınabilir bir kullanıcı mesajı seçilir.
    final budgetAlerts = (summary['budget_alerts'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final dangerAlerts =
        budgetAlerts.where((item) => item['level'] == 'danger').toList();
    final warningAlerts =
        budgetAlerts.where((item) => item['level'] == 'warning').toList();
    final monthlyTarget =
        (summary['monthly_income_target'] as num? ?? 0).toDouble();
    final currentExpense =
        (summary['current_month_expense'] as num? ?? 0).toDouble();

    if (dangerAlerts.isNotEmpty) {
      final first = dangerAlerts.first;
      final category = (first['category'] ?? 'bir kategori').toString();
      final usage = (first['usage_percent'] as num? ?? 100).toDouble();
      return _FinancialReminder(
        title: 'Dikkat, bütçe limiti aşıldı',
        body:
            '$category harcaman limitin %${usage.toStringAsFixed(0)} seviyesinde. Bugün biraz frene basmak iyi olabilir.',
      );
    }

    if (warningAlerts.isNotEmpty) {
      final first = warningAlerts.first;
      final category = (first['category'] ?? 'bir kategori').toString();
      final usage = (first['usage_percent'] as num? ?? 80).toDouble();
      return _FinancialReminder(
        title: 'Limitlerine yaklaşıyorsun',
        body:
            '$category harcaman limitin %${usage.toStringAsFixed(0)} seviyesinde. Dengede kalmak için takipte kal.',
      );
    }

    if (monthlyTarget > 0) {
      final ratio = currentExpense / monthlyTarget;
      if (ratio >= 1.0) {
        return const _FinancialReminder(
          title: 'Bu ay bütçe zorlanıyor',
          body:
              'Aylık gelir hedefinin üstüne çıktın. Yeni harcamalarda daha seçici davranmak iyi olur.',
        );
      }
      if (ratio >= 0.85) {
        return const _FinancialReminder(
          title: 'Bütçe sınırına yaklaştın',
          body:
              'Harcamaların aylık hedefe yaklaştı. Kalan günler için küçük bir kontrol iyi gelebilir.',
        );
      }
      if (ratio <= 0.6) {
        return const _FinancialReminder(
          title: 'İyi gidiyorsun',
          body:
              'Harcamaların şu an dengeli görünüyor. Bu tempoyu korursan ay sonu rahat geçer.',
        );
      }
    }

    return const _FinancialReminder(
      title: 'Bütçe kontrol zamanı',
      body:
          'Harcamaların genel olarak dengede görünüyor. Kısa bir kontrolle rotayı koruyabilirsin.',
    );
  }

  Future<void> _showNotification({
    required String id,
    required String title,
    required String body,
    String channelId = _notificationChannelId,
    String channelName = _notificationChannelName,
    String channelDescription = _notificationChannelDescription,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    final notificationId = id.hashCode & 0x7fffffff;
    await _notifications.show(notificationId, title, body, details);
  }
}

class _FinancialReminder {
  const _FinancialReminder({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}
