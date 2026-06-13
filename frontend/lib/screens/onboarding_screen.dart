import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../state/app_controller.dart';
import 'dashboard_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.controller,
    required this.token,
    required this.initialMonthlyIncome,
  });

  final AppController controller;
  final String token;
  final double initialMonthlyIncome;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _monthlyIncomeController = TextEditingController();
  final _essentialExpenseController = TextEditingController();
  final _savingsGoalController = TextEditingController();
  int _step = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _monthlyIncomeController.text = widget.initialMonthlyIncome > 0
        ? widget.initialMonthlyIncome.toStringAsFixed(0)
        : '';
  }

  @override
  void dispose() {
    _monthlyIncomeController.dispose();
    _essentialExpenseController.dispose();
    _savingsGoalController.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController controller) {
    return double.tryParse(controller.text.trim().replaceAll(',', '.'));
  }

  Future<void> _finish() async {
    final income = _parse(_monthlyIncomeController);
    final expense = _parse(_essentialExpenseController) ?? 0;
    final goal = _parse(_savingsGoalController) ?? 0;
    if (income == null || income <= 0) {
      setState(() => _error = AppLocalizer.text(widget.controller, 'monthlyIncomeRequired'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.controller.api.completeOnboarding(
        token: widget.token,
        monthlyIncome: income,
        essentialExpense: expense,
        savingsGoal: goal,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DashboardScreen(controller: widget.controller),
        ),
      );
    } catch (err) {
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppLocalizer.text(widget.controller, key);
    final scheme = Theme.of(context).colorScheme;
    final steps = [
      t('onboardingStepIncome'),
      t('onboardingStepEssentials'),
      t('onboardingStepGoal'),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(t('onboardingTitle'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('onboardingSubtitle'), style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: (_step + 1) / 3),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: List.generate(
                steps.length,
                (index) => Chip(
                  label: Text(steps[index]),
                  backgroundColor: index == _step
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_step == 0)
              _OnboardingField(
                controller: _monthlyIncomeController,
                title: t('monthlyIncome'),
                hint: t('monthlyIncomeHint'),
                icon: Icons.payments_rounded,
              ),
            if (_step == 1)
              _OnboardingField(
                controller: _essentialExpenseController,
                title: t('essentialExpense'),
                hint: t('essentialExpenseHint'),
                icon: Icons.receipt_long_rounded,
              ),
            if (_step == 2)
              _OnboardingField(
                controller: _savingsGoalController,
                title: t('savingsGoal'),
                hint: t('savingsGoalHint'),
                icon: Icons.savings_rounded,
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
            ],
            const Spacer(),
            Row(
              children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _loading ? null : () => setState(() => _step -= 1),
                      child: Text(t('back')),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _loading
                        ? null
                        : () {
                            if (_step < 2) {
                              setState(() => _step += 1);
                            } else {
                              _finish();
                            }
                          },
                    child: Text(
                      _loading
                          ? t('saving')
                          : (_step == 2 ? t('finishSetup') : t('continueNext')),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingField extends StatelessWidget {
  const _OnboardingField({
    required this.controller,
    required this.title,
    required this.hint,
    required this.icon,
  });

  final TextEditingController controller;
  final String title;
  final String hint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }
}
