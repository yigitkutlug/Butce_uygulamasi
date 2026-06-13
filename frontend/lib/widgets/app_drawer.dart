import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../screens/ai_metrics_screen.dart';
import '../screens/about_screen.dart';
import '../screens/alerts_screen.dart';
import '../screens/budget_limits_screen.dart';
import '../screens/categories_screen.dart';
import '../screens/coins_screen.dart';
import '../screens/coach_chat_screen.dart';
import '../screens/exchange_rates_screen.dart';
import '../screens/investments_screen.dart';
import '../screens/monthly_report_screen.dart';
import '../screens/portfolio_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/recurring_payments_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/transactions_by_type_screen.dart';
import '../state/app_controller.dart';
import 'brand_mark.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppLocalizer.text(controller, key);
    final scheme = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primaryContainer.withValues(alpha: 0.9),
                    scheme.secondaryContainer.withValues(alpha: 0.7),
                  ],
                ),
              ),
              child: Row(
                children: [
                  const BrandMark(size: 44, radius: 14),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('menu'),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        t('appTitle'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _DrawerItem(
              icon: Icons.home_rounded,
              title: t('home'),
              onTap: () => Navigator.of(context).pop(),
            ),
            _SectionTitle(text: t('records')),
            _DrawerItem(
              icon: Icons.arrow_downward_rounded,
              title: t('incomeList'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TransactionsByTypeScreen(
                        controller: controller, showIncome: true),
                  ),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.arrow_upward_rounded,
              title: t('expenseList'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TransactionsByTypeScreen(
                        controller: controller, showIncome: false),
                  ),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.category_rounded,
              title: t('categories'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => CategoriesScreen(controller: controller)),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.speed_rounded,
              title: t('budgetLimits'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) =>
                          BudgetLimitsScreen(controller: controller)),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.receipt_long_rounded,
              title: t('recurringPayments'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) =>
                          RecurringPaymentsScreen(controller: controller)),
                );
              },
            ),
            _SectionTitle(text: t('financialTools')),
            _DrawerItem(
              icon: Icons.assessment_rounded,
              title: t('monthlyReport'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) =>
                          MonthlyReportScreen(controller: controller)),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.psychology_rounded,
              title: t('aiPerformance'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => AiMetricsScreen(controller: controller)),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.smart_toy_rounded,
              title: t('aiCoach'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => CoachChatScreen(controller: controller)),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.show_chart_rounded,
              title: t('coins'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => CoinsScreen(controller: controller)),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.account_balance_rounded,
              title: t('investmentAssets'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) =>
                          InvestmentsScreen(controller: controller)),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.account_balance_wallet_rounded,
              title: t('portfolio'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => PortfolioScreen(controller: controller)),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.notifications_active_rounded,
              title: t('alerts'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => AlertsScreen(controller: controller)),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.currency_exchange_rounded,
              title: t('exchangeRates'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) =>
                          ExchangeRatesScreen(controller: controller)),
                );
              },
            ),
            _SectionTitle(text: t('about')),
            _DrawerItem(
              icon: Icons.person_rounded,
              title: t('profile'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => ProfileScreen(controller: controller)),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.settings_rounded,
              title: t('settings'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => SettingsScreen(controller: controller)),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.info_outline_rounded,
              title: t('about'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => AboutScreen(controller: controller)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }
}
