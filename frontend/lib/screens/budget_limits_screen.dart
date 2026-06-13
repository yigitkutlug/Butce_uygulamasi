import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../services/token_storage.dart';
import '../state/app_controller.dart';
import '../utils/category_utils.dart';

class BudgetLimitsScreen extends StatefulWidget {
  const BudgetLimitsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<BudgetLimitsScreen> createState() => _BudgetLimitsScreenState();
}

class _BudgetLimitsScreenState extends State<BudgetLimitsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<String> _categories = [];
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Önce gider kategorileri, sonra mevcut limitler çekilir; her kategoriye
      // ayrı TextEditingController bağlanır.
      final token = await TokenStorage().getToken();
      if (token == null) {
        throw Exception(AppLocalizer.text(widget.controller, 'missingToken'));
      }
      final categoriesRaw = await widget.controller.api.getCategories(token);
      final expense = (categoriesRaw['expense'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      final budgetsRaw = await widget.controller.api.getBudgets(token);
      final budgetMap = <String, double>{};
      for (final item in budgetsRaw) {
        final map = item as Map<String, dynamic>;
        budgetMap[map['category'].toString()] =
            (map['limit'] as num?)?.toDouble() ?? 0;
      }

      for (final category in expense) {
        // Controller yeniden oluşturulurken eski controller dispose edilir; bu
        // ekran tekrar yüklendiğinde memory leak oluşmaz.
        _controllers[category]?.dispose();
        _controllers[category] = TextEditingController(
          text: (budgetMap[category] ?? 0).toStringAsFixed(0),
        );
      }

      if (!mounted) return;
      setState(() => _categories = expense);
    } catch (err) {
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveAll() async {
    final token = await TokenStorage().getToken();
    if (token == null) {
      setState(
          () => _error = AppLocalizer.text(widget.controller, 'missingToken'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      for (final category in _categories) {
        final ctrl = _controllers[category];
        if (ctrl == null) continue;
        // Boş veya geçersiz limitler atlanır; kullanıcı sadece değiştirdiği
        // pozitif değerleri kaydedebilir.
        final limit =
            double.tryParse(ctrl.text.trim().replaceAll(',', '.')) ?? 0;
        if (limit <= 0) continue;
        await widget.controller.api.updateBudget(
          token: token,
          category: category,
          limit: limit,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizer.text(widget.controller, 'budgetSaved'))),
      );
      Navigator.of(context).pop(true);
    } catch (err) {
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppLocalizer.text(widget.controller, key);

    return Scaffold(
      appBar: AppBar(title: Text(t('budgetLimits'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  t('budgetLimitsHint'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                ..._categories.map((category) {
                  final ctrl = _controllers[category]!;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: ctrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText:
                            localizeCategory(widget.controller, category),
                        suffixText: widget.controller.currencySymbol,
                      ),
                    ),
                  );
                }),
                if (_error != null)
                  Text(_error!,
                      style: const TextStyle(color: Color(0xFFB91C1C))),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _saving ? null : _saveAll,
                  icon: const Icon(Icons.save_rounded),
                  label: Text(_saving ? t('saving') : t('save')),
                ),
              ],
            ),
    );
  }
}
