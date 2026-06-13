import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'localization/app_localizer.dart';
import 'screens/consent_gate_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'services/background_alert_service.dart';
import 'services/token_storage.dart';
import 'state/app_controller.dart';

const String _apiFromEnv = String.fromEnvironment('API_BASE_URL');
const String _productionApi = 'https://budget-tracker-api-anv1.onrender.com';
const String _androidEmulatorApi = 'http://10.0.2.2:8000';
const String _localApi = 'http://127.0.0.1:8000';

String _normalizeApiBaseUrl(String raw) {
  var value = raw.trim();
  // Kullanıcı/env bazen /docs veya sonda / ile URL verebilir; API çağrıları
  // kırılmasın diye base URL tek biçime indirilir.
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

String resolveApiBaseUrl() {
  // Build sırasında API_BASE_URL verilirse onu kullanırız; yoksa platforma göre
  // local, emulator veya production adresine düşeriz.
  if (_apiFromEnv.isNotEmpty) {
    return _normalizeApiBaseUrl(_apiFromEnv);
  }
  if (kReleaseMode) {
    return _productionApi;
  }
  if (kIsWeb) {
    return _localApi;
  }
  return defaultTargetPlatform == TargetPlatform.android
      ? _androidEmulatorApi
      : _localApi;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bildirim servisi runApp'ten önce hazırlanır; böylece uygulama açılırken
  // fiyat alarmı ve bütçe hatırlatıcısı kayıtları kurulmuş olur.
  await BackgroundAlertService.instance.bootstrap();
  runApp(const BudgetApp());
}

class BudgetApp extends StatefulWidget {
  const BudgetApp({super.key});

  @override
  State<BudgetApp> createState() => _BudgetAppState();
}

class _BudgetAppState extends State<BudgetApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    // AppController hem API servisini hem de kalıcı uygulama ayarlarını yönetir.
    _controller = AppController(api: ApiService(baseUrl: resolveApiBaseUrl()));
    _controller.init();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return MaterialApp(
          title: AppLocalizer.text(_controller, 'appTitle'),
          debugShowCheckedModeBanner: false,
          themeMode: _controller.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: const Color(0xFF0A7F78),
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF4F7F8),
            cardTheme: const CardThemeData(
              elevation: 0,
              margin: EdgeInsets.zero,
            ),
            inputDecorationTheme: const InputDecorationTheme(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: const Color(0xFF20B3A9),
            brightness: Brightness.dark,
            cardTheme: const CardThemeData(
              elevation: 0,
              margin: EdgeInsets.zero,
            ),
            inputDecorationTheme: const InputDecorationTheme(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
          home: !_controller.ready
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : FutureBuilder<String?>(
                  future: TokenStorage().getToken(),
                  builder: (context, snapshot) {
                    // Token varsa kullanıcı doğrudan ana akışa alınır; yoksa
                    // login ekranı gösterilir.
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Scaffold(
                          body: Center(child: CircularProgressIndicator()));
                    }
                    final token = snapshot.data;
                    if (token != null) {
                      return ConsentGateScreen(
                          controller: _controller, token: token);
                    }
                    return LoginScreen(controller: _controller);
                  },
                ),
        );
      },
    );
  }
}
