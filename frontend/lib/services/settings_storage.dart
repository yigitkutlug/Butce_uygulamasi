import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class SettingsStorage {
  static const _themeModeKey = 'settings_theme_mode';
  static const _languageCodeKey = 'settings_language_code';
  static const _currencyCodeKey = 'settings_currency_code';
  // BackgroundAlertService uygulama state'ine erişemediği için bu key public
  // tutulur; arka plan bildirimi kullanıcı tercihine göre durdurulabilir.
  static const financialRemindersEnabledKey =
      'settings_financial_reminders_enabled';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      themeMode:
          prefs.getString(_themeModeKey) ?? AppSettings.defaults.themeMode,
      languageCode: prefs.getString(_languageCodeKey) ??
          AppSettings.defaults.languageCode,
      currencyCode: prefs.getString(_currencyCodeKey) ??
          AppSettings.defaults.currencyCode,
      financialRemindersEnabled: prefs.getBool(financialRemindersEnabledKey) ??
          AppSettings.defaults.financialRemindersEnabled,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, settings.themeMode);
    await prefs.setString(_languageCodeKey, settings.languageCode);
    await prefs.setString(_currencyCodeKey, settings.currencyCode);
    await prefs.setBool(
      financialRemindersEnabledKey,
      settings.financialRemindersEnabled,
    );
  }
}
