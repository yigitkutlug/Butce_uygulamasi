import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../state/app_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizer.text(controller, 'settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.language),
              title: Text(AppLocalizer.text(controller, 'language')),
              subtitle: DropdownButton<String>(
                value: controller.settings.languageCode,
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                    value: 'tr',
                    child: Text(AppLocalizer.text(controller, 'turkish')),
                  ),
                  DropdownMenuItem(
                    value: 'en',
                    child: Text(AppLocalizer.text(controller, 'english')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    // Dil değişince AppController notify eder ve uygulamadaki
                    // lokalize metinler yeniden çizilir.
                    controller.setLanguageCode(value);
                  }
                },
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.dark_mode),
              title: Text(AppLocalizer.text(controller, 'theme')),
              subtitle: DropdownButton<String>(
                value: controller.settings.themeMode,
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                    value: 'light',
                    child: Text(AppLocalizer.text(controller, 'lightMode')),
                  ),
                  DropdownMenuItem(
                    value: 'dark',
                    child: Text(AppLocalizer.text(controller, 'darkMode')),
                  ),
                  DropdownMenuItem(
                    value: 'system',
                    child: Text(AppLocalizer.text(controller, 'systemMode')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    // Tema seçimi kalıcı saklanır; uygulama tekrar açıldığında
                    // aynı görünüm korunur.
                    controller.setThemeMode(value);
                  }
                },
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.attach_money),
              title: Text(AppLocalizer.text(controller, 'currency')),
              subtitle: DropdownButton<String>(
                value: controller.settings.currencyCode,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'TRY', child: Text('TRY')),
                  DropdownMenuItem(value: 'USD', child: Text('USD')),
                  DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    // Para birimi sembolü dashboard ve raporlardaki tutar
                    // formatını etkiler.
                    controller.setCurrencyCode(value);
                  }
                },
              ),
            ),
          ),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.notifications_active_rounded),
              title: Text(AppLocalizer.text(controller, 'financialReminders')),
              subtitle: Text(
                AppLocalizer.text(controller, 'financialRemindersHint'),
              ),
              value: controller.settings.financialRemindersEnabled,
              // Kullanıcı kapatırsa arka plan servisi de aynı ayarı okuyup 5
              // günlük bütçe bildirimini göndermez.
              onChanged: controller.setFinancialRemindersEnabled,
            ),
          ),
        ],
      ),
    );
  }
}
