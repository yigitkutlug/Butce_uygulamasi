import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/api_service.dart';
import '../services/settings_storage.dart';

class AppController extends ChangeNotifier {
  AppController({required this.api}) : _settings = AppSettings.defaults;

  final ApiService api;
  // Uygulama genelindeki ayarlar tek controller'da tutulur; ekranlar bu state'i
  // dinleyerek tema, dil, para birimi ve bildirim tercihini güncel görür.
  final SettingsStorage _storage = SettingsStorage();

  AppSettings _settings;
  bool _ready = false;

  AppSettings get settings => _settings;
  bool get ready => _ready;

  ThemeMode get themeMode {
    // Flutter ThemeMode enum beklediği için kaydedilen string değer burada
    // uygulamanın anlayacağı tipe çevrilir.
    switch (_settings.themeMode) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }

  String get currencySymbol {
    // Para birimi kodu hesaplamalarda saklanır, ekranda kısa sembol gösterilir.
    switch (_settings.currencyCode) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      default:
        return '₺';
    }
  }

  Future<void> init() async {
    // İlk açılışta kalıcı ayarlar yüklenir; ready true olana kadar main.dart
    // loading ekranı gösterir.
    _settings = await _storage.load();
    _ready = true;
    notifyListeners();
  }

  Future<void> setThemeMode(String value) async {
    // Her setter hem bellekteki state'i günceller hem de sonraki açılış için
    // SharedPreferences'a yazar.
    _settings = _settings.copyWith(themeMode: value);
    await _storage.save(_settings);
    notifyListeners();
  }

  Future<void> setLanguageCode(String value) async {
    _settings = _settings.copyWith(languageCode: value);
    await _storage.save(_settings);
    notifyListeners();
  }

  Future<void> setCurrencyCode(String value) async {
    _settings = _settings.copyWith(currencyCode: value);
    await _storage.save(_settings);
    notifyListeners();
  }

  Future<void> setFinancialRemindersEnabled(bool value) async {
    _settings = _settings.copyWith(financialRemindersEnabled: value);
    await _storage.save(_settings);
    notifyListeners();
  }
}
