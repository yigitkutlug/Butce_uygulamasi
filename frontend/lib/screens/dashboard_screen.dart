import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../models/transaction.dart';
import '../services/token_storage.dart';
import '../state/app_controller.dart';
import '../utils/category_utils.dart';
import '../utils/error_messages.dart';
import '../widgets/app_drawer.dart';
import 'add_transaction_screen.dart';
import 'login_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? _token;
  bool _loading = true;
  String? _error;
  List<TransactionItem> _transactions = [];
  Map<String, dynamic> _summary = {};
  Map<String, dynamic> _prediction = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isTurkish => widget.controller.settings.languageCode == 'tr';

  String _localizedCategory(String rawCategory) {
    return localizeCategory(widget.controller, rawCategory);
  }

  String _groupThousands(String integerPart, String separator) {
    // Para formatını manuel kuruyoruz çünkü Türkçe ve İngilizce gösterimde
    // binlik/ondalık ayırıcıları farklı.
    final isNegative = integerPart.startsWith('-');
    final digitsOnly = isNegative ? integerPart.substring(1) : integerPart;

    final out = StringBuffer();
    for (var i = 0; i < digitsOnly.length; i++) {
      final idxFromRight = digitsOnly.length - i;
      out.write(digitsOnly[i]);
      if (idxFromRight > 1 && idxFromRight % 3 == 1) {
        out.write(separator);
      }
    }

    final result = out.toString();
    return isNegative ? '-$result' : result;
  }

  String _formatMoney(num value) {
    final fixed = value.toDouble().toStringAsFixed(2);
    final parts = fixed.split('.');

    if (_isTurkish) {
      final grouped = _groupThousands(parts[0], '.');
      return '$grouped,${parts[1]} ${widget.controller.currencySymbol}';
    }

    final grouped = _groupThousands(parts[0], ',');
    return '${widget.controller.currencySymbol}$grouped.${parts[1]}';
  }

  String _formatSignedMoney(num value) {
    if (value > 0) return '+${_formatMoney(value)}';
    if (value < 0) return '-${_formatMoney(value.abs())}';
    return _formatMoney(value);
  }

  String _translateRecommendation(String text) {
    if (!_isTurkish) return text;

    // Backend önerileri sabit İngilizce patternlerle döner; burada demo
    // ekranında kullanıcıya Türkçe ve kategori adı lokalize edilerek gösterilir.
    if (text == 'You exceeded transport budget') {
      return 'Ulaşım bütçeni aştın.';
    }

    final overallIncreased =
        RegExp(r'^Your overall spending increased by (\d+)% last month\.$');
    final overallDecreased = RegExp(
        r'^Great job! Your overall spending decreased by (\d+)% last month\.$');
    final categoryIncreased =
        RegExp(r'^Your (.+) spending increased by (\d+)% last month\.$');
    final highSpending = RegExp(r'^High spending in (.+)\.$');
    final aboveTarget =
        RegExp(r'^You spent (\d+)% above your monthly income target\.$');
    final budgetExceeded = RegExp(r'^Budget exceeded in (.+)\.$');
    final budgetNear = RegExp(r'^Budget is close to limit in (.+)\.$');
    const nearTarget =
        'You are close to your monthly income limit. Keep tracking your expenses.';
    const safeTarget =
        'Great discipline! You are safely below your monthly income target.';

    final increasedMatch = overallIncreased.firstMatch(text);
    if (increasedMatch != null) {
      return 'Geçen ay toplam harcaman %${increasedMatch.group(1)} arttı.';
    }

    final decreasedMatch = overallDecreased.firstMatch(text);
    if (decreasedMatch != null) {
      return 'Harika! Geçen ay toplam harcaman %${decreasedMatch.group(1)} azaldı.';
    }

    final categoryMatch = categoryIncreased.firstMatch(text);
    if (categoryMatch != null) {
      final cat = _localizedCategory(categoryMatch.group(1) ?? '');
      final pct = categoryMatch.group(2) ?? '0';
      return 'Geçen ay $cat harcaman %$pct arttı.';
    }

    final highMatch = highSpending.firstMatch(text);
    if (highMatch != null) {
      final cat = _localizedCategory(highMatch.group(1) ?? '');
      return '$cat kategorisinde harcama yüksek.';
    }

    final aboveMatch = aboveTarget.firstMatch(text);
    if (aboveMatch != null) {
      final pct = aboveMatch.group(1) ?? '0';
      return 'Aylık gelir hedefinin %$pct üzerinde harcadın.';
    }

    if (text == nearTarget) {
      return 'Aylık gelir limitine yaklaştın, harcamayı takip etmeye devam et.';
    }

    if (text == safeTarget) {
      return 'Harika disiplin! Aylık gelir hedefinin güvenli seviyedesin.';
    }

    final budgetExceededMatch = budgetExceeded.firstMatch(text);
    if (budgetExceededMatch != null) {
      final cat = _localizedCategory(budgetExceededMatch.group(1) ?? '');
      return '$cat kategorisinde bütçe limiti aşıldı.';
    }

    final budgetNearMatch = budgetNear.firstMatch(text);
    if (budgetNearMatch != null) {
      final cat = _localizedCategory(budgetNearMatch.group(1) ?? '');
      return '$cat kategorisinde bütçe limitine yaklaşıldı.';
    }

    return text;
  }

  Color _categoryColor(String category) {
    // Grafik ve işlem listesinde aynı kategori aynı renkle gösterilsin diye
    // kategori adına göre deterministik renk seçilir.
    final key = category.toLowerCase();
    if (key.contains('transport') || key.contains('ulaşım')) {
      return const Color(0xFF2563EB);
    }
    if (key.contains('market')) {
      return const Color(0xFF16A34A);
    }
    if (key.contains('food') || key.contains('yemek')) {
      return const Color(0xFFA21CAF);
    }
    if (key.contains('salary') || key.contains('maaş')) {
      return const Color(0xFF0D9488);
    }
    if (key.contains('income') || key.contains('gelir')) {
      return const Color(0xFF0EA5E9);
    }
    return const Color(0xFF64748B);
  }

  IconData _categoryIcon(String category) {
    // İşlem listesinde kategoriler hızlı ayırt edilsin diye aynı mantıkla ikon
    // atanır.
    final key = category.toLowerCase();
    if (key.contains('transport') || key.contains('ulaşım')) {
      return Icons.directions_bus_rounded;
    }
    if (key.contains('market')) {
      return Icons.shopping_cart_rounded;
    }
    if (key.contains('food') || key.contains('yemek')) {
      return Icons.restaurant_rounded;
    }
    if (key.contains('salary') || key.contains('maaş')) {
      return Icons.payments_rounded;
    }
    if (key.contains('income') || key.contains('gelir')) {
      return Icons.trending_up_rounded;
    }
    return Icons.category_rounded;
  }

  List<PieChartSectionData> _buildSections(
      Map<String, dynamic> categorySpending) {
    // Pasta grafikte en çok harcanan kategoriler önce gelsin diye büyükten
    // küçüğe sıralanır.
    final entries = categorySpending.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));
    if (entries.isEmpty) return [];

    return List.generate(entries.length, (index) {
      final value = (entries[index].value as num).toDouble();
      return PieChartSectionData(
        value: value,
        title: '',
        color: _categoryColor(entries[index].key),
        radius: 58,
      );
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Dashboard üç ana veriyi birlikte çeker: işlem listesi, analiz özeti ve
      // gelecek ay harcama tahmini.
      final token = await TokenStorage().getToken();
      if (token == null) {
        throw Exception(AppLocalizer.text(widget.controller, 'missingToken'));
      }
      final txRaw = await widget.controller.api.getTransactions(token);
      final summary = await widget.controller.api.getSummary(token);
      final prediction = await widget.controller.api.getPrediction(token);

      setState(() {
        _token = token;
        _transactions = txRaw.map((e) => TransactionItem.fromJson(e)).toList();
        _summary = summary;
        _prediction = prediction;
      });
    } catch (err) {
      if (mounted) setState(() => _error = userFacingError(err));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    // Token silinince kullanıcı tüm önceki ekranlardan çıkarılıp login'e döner.
    await TokenStorage().clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => LoginScreen(controller: widget.controller)),
      (_) => false,
    );
  }

  Widget _metricCard(
      {required String label, required String value, required IconData icon}) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 12)),
                const SizedBox(height: 3),
                Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppLocalizer.text(widget.controller, key);
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(t('dashboard'))),
        body: Center(child: Text(_error!)),
      );
    }

    final totalIncome = (_summary['total_income'] ?? 0) as num;
    final totalExpense = (_summary['total_expense'] ?? 0) as num;
    final activeBalance =
        (_summary['active_balance'] ?? (totalIncome - totalExpense)) as num;
    final categorySpending =
        (_summary['category_spending'] ?? {}) as Map<String, dynamic>;
    final recommendations =
        (_summary['recommendations'] ?? []) as List<dynamic>;
    final predicted =
        (_prediction['predicted_next_month_spending'] ?? 0) as num;
    final monthlyIncomeTarget = (_summary['monthly_income_target'] ?? 0) as num;
    final monthChangePct = (_summary['month_change_pct'] ?? 0) as num;
    final topCategories = (_summary['top_categories'] as List<dynamic>? ?? []);
    final billReminders = (_summary['bill_reminders'] as List<dynamic>? ?? []);
    final weeklyCurrent = (_summary['weekly_expense_current'] ?? 0) as num;
    final weeklyPrevious = (_summary['weekly_expense_previous'] ?? 0) as num;
    final weeklyChange = (_summary['weekly_change_pct'] ?? 0) as num;

    final categoryEntries = categorySpending.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));

    // Bu ekran backend özetini küçük kartlara böler: üstte finansal metrikler,
    // ortada grafik/analiz, altta öneriler ve son işlemler.
    return Scaffold(
      drawer: AppDrawer(controller: widget.controller),
      appBar: AppBar(
        title: Text(t('dashboard')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded),
              tooltip: t('logout')),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddTransactionScreen(
                  controller: widget.controller, token: _token!),
            ),
          );
          if (result == true) _load();
        },
        child: const Icon(Icons.add),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.35),
              scheme.surface,
              scheme.tertiaryContainer.withValues(alpha: 0.28),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: -80,
                right: -70,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary.withValues(alpha: 0.09),
                  ),
                ),
              ),
              RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 84),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                            color:
                                scheme.outlineVariant.withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _metricCard(
                                  label: t('totalIncome'),
                                  value: _formatMoney(totalIncome),
                                  icon: Icons.arrow_downward_rounded,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _metricCard(
                                  label: t('totalExpense'),
                                  value: _formatMoney(totalExpense),
                                  icon: Icons.arrow_upward_rounded,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _metricCard(
                            label: t('activeBalance'),
                            value: _formatMoney(activeBalance),
                            icon: Icons.account_balance_wallet_rounded,
                          ),
                          const SizedBox(height: 10),
                          _metricCard(
                            label: t('predictedNextMonth'),
                            value: _formatMoney(predicted),
                            icon: Icons.insights_rounded,
                          ),
                          if (monthlyIncomeTarget > 0)
                            const SizedBox(height: 10),
                          if (monthlyIncomeTarget > 0)
                            _metricCard(
                              label: t('monthlyTarget'),
                              value: _formatMoney(monthlyIncomeTarget),
                              icon: Icons.account_balance_wallet_rounded,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (categorySpending.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                              color: scheme.outlineVariant
                                  .withValues(alpha: 0.35)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('categoryBreakdown'),
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 210,
                              child: PieChart(
                                PieChartData(
                                  sections: _buildSections(categorySpending),
                                  centerSpaceRadius: 42,
                                  sectionsSpace: 2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: categoryEntries
                                  .map(
                                    (entry) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: _categoryColor(entry.key)
                                            .withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: _categoryColor(entry.key),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${_localizedCategory(entry.key)} • ${_formatMoney((entry.value as num).toDouble())}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    if (recommendations.isNotEmpty) const SizedBox(height: 14),
                    if (billReminders.isNotEmpty) const SizedBox(height: 14),
                    if (billReminders.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                              color: scheme.outlineVariant
                                  .withValues(alpha: 0.35)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('upcomingPayments'),
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 10),
                            ...billReminders.map((item) {
                              final row = item as Map<String, dynamic>;
                              final title = row['title']?.toString() ?? '-';
                              final amount =
                                  (row['amount'] as num? ?? 0).toDouble();
                              final category =
                                  row['category']?.toString() ?? '';
                              final daysLeft =
                                  (row['days_left'] as num? ?? 0).toInt();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.notifications_active_rounded,
                                        color: scheme.primary, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '$title • ${_localizedCategory(category)} • ${_formatMoney(amount)} • $daysLeft ${t('dueInDays')}',
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                            color:
                                scheme.outlineVariant.withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('weeklyAnalysis'),
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(
                              '${t('last7Days')}: ${_formatMoney(weeklyCurrent)}'),
                          Text(
                              '${t('previous7Days')}: ${_formatMoney(weeklyPrevious)}'),
                          const SizedBox(height: 6),
                          Text(
                            '${t('weeklyChange')}: ${weeklyChange >= 0 ? '+' : ''}${weeklyChange.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: weeklyChange >= 0
                                  ? const Color(0xFFB91C1C)
                                  : const Color(0xFF15803D),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (topCategories.isNotEmpty) const SizedBox(height: 14),
                    if (topCategories.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                              color: scheme.outlineVariant
                                  .withValues(alpha: 0.35)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('quickAnalysis'),
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text(
                              '${t('monthChange')}: ${monthChangePct >= 0 ? '+' : ''}${monthChangePct.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: monthChangePct >= 0
                                    ? const Color(0xFFB91C1C)
                                    : const Color(0xFF15803D),
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...topCategories.map((item) {
                              final row = item as Map<String, dynamic>;
                              final category =
                                  row['category']?.toString() ?? '';
                              final amount =
                                  (row['amount'] as num? ?? 0).toDouble();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  '• ${_localizedCategory(category)}: ${_formatMoney(amount)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    if (topCategories.isNotEmpty) const SizedBox(height: 14),
                    if (recommendations.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                              color: scheme.outlineVariant
                                  .withValues(alpha: 0.35)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('recommendations'),
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 10),
                            ...recommendations.map((r) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.auto_awesome_rounded,
                                          color: scheme.primary, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                          child: Text(_translateRecommendation(
                                              r.toString()))),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    Text(t('recentTransactions'),
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    ..._transactions.take(12).map(
                          (tx) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.surface.withValues(alpha: 0.84),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                  color: scheme.outlineVariant
                                      .withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: _categoryColor(tx.category)
                                        .withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(_categoryIcon(tx.category),
                                      color: _categoryColor(tx.category),
                                      size: 20),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        tx.description,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${_localizedCategory(tx.category)} • ${tx.date.toLocal().toString().split(' ')[0]} • ${tx.account}',
                                        style: TextStyle(
                                            color: scheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatSignedMoney(tx.amount),
                                  style: TextStyle(
                                    color: tx.amount >= 0
                                        ? const Color(0xFF15803D)
                                        : const Color(0xFFB91C1C),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
