class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.languageCode,
    required this.currencyCode,
    required this.financialRemindersEnabled,
  });

  final String themeMode;
  final String languageCode;
  final String currencyCode;
  final bool financialRemindersEnabled;

  AppSettings copyWith({
    String? themeMode,
    String? languageCode,
    String? currencyCode,
    bool? financialRemindersEnabled,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      languageCode: languageCode ?? this.languageCode,
      currencyCode: currencyCode ?? this.currencyCode,
      financialRemindersEnabled:
          financialRemindersEnabled ?? this.financialRemindersEnabled,
    );
  }

  static const AppSettings defaults = AppSettings(
    themeMode: 'light',
    languageCode: 'tr',
    currencyCode: 'TRY',
    financialRemindersEnabled: true,
  );
}
