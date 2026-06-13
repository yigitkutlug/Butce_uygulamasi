import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../services/token_storage.dart';
import '../state/app_controller.dart';
import '../utils/category_utils.dart';

class RecurringPaymentsScreen extends StatefulWidget {
  const RecurringPaymentsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<RecurringPaymentsScreen> createState() => _RecurringPaymentsScreenState();
}

class _RecurringPaymentsScreenState extends State<RecurringPaymentsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  List<String> _expenseCategories = ['Food', 'Market', 'Transport', 'Bills', 'Entertainment', 'Other'];

  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  String _category = 'Bills';
  String _account = 'Card';
  int _dueDay = 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<String> _requireToken() async {
    final token = await TokenStorage().getToken();
    if (token == null) {
      throw Exception(AppLocalizer.text(widget.controller, 'missingToken'));
    }
    return token;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await _requireToken();
      final categoriesRaw = await widget.controller.api.getCategories(token);
      final expense = (categoriesRaw['expense'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
      final recurringRaw = await widget.controller.api.getRecurringPayments(token);
      final recurring = recurringRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        if (expense.isNotEmpty) {
          _expenseCategories = expense;
          if (!_expenseCategories.contains(_category)) {
            _category = _expenseCategories.first;
          }
        }
        _items = recurring;
      });
    } catch (err) {
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addRecurring() async {
    final title = _titleController.text.trim();
    final amount = double.tryParse(_amountController.text.trim().replaceAll(',', '.')) ?? 0;
    if (title.length < 2 || amount <= 0) {
      setState(() => _error = AppLocalizer.text(widget.controller, 'invalidRecurringInput'));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final token = await _requireToken();
      await widget.controller.api.createRecurringPayment(
        token: token,
        title: title,
        amount: amount,
        category: _category,
        dueDay: _dueDay,
        account: _account,
      );
      _titleController.clear();
      _amountController.clear();
      await _load();
    } catch (err) {
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggle(String id, bool current) async {
    try {
      final token = await _requireToken();
      await widget.controller.api.setRecurringActive(
        token: token,
        recurringId: id,
        isActive: !current,
      );
      await _load();
    } catch (err) {
      setState(() => _error = err.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppLocalizer.text(widget.controller, key);

    return Scaffold(
      appBar: AppBar(title: Text(t('recurringPayments'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('addRecurring'), style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _titleController,
                          decoration: InputDecoration(labelText: t('description')),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: '${t('amount')} (${widget.controller.currencySymbol})',
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _category,
                          decoration: InputDecoration(labelText: t('categorySelect')),
                          items: _expenseCategories
                              .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(localizeCategory(widget.controller, c)),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) setState(() => _category = value);
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _account,
                                decoration: InputDecoration(labelText: t('accountType')),
                                items: [
                                  DropdownMenuItem(value: 'Card', child: Text(t('accountCard'))),
                                  DropdownMenuItem(value: 'Cash', child: Text(t('accountCash'))),
                                  DropdownMenuItem(value: 'IBAN', child: Text(t('accountIban'))),
                                ],
                                onChanged: (value) {
                                  if (value != null) setState(() => _account = value);
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: _dueDay,
                                decoration: InputDecoration(labelText: t('dueDay')),
                                items: List.generate(
                                  28,
                                  (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
                                ),
                                onChanged: (value) {
                                  if (value != null) setState(() => _dueDay = value);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _saving ? null : _addRecurring,
                          icon: const Icon(Icons.add_rounded),
                          label: Text(_saving ? t('saving') : t('save')),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
                ],
                const SizedBox(height: 12),
                ..._items.map((item) {
                  final active = item['is_active'] as bool? ?? true;
                  final category = item['category']?.toString() ?? '';
                  final dueDate = item['next_due_date']?.toString() ?? '';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text(item['title']?.toString() ?? '-'),
                      subtitle: Text(
                        '${localizeCategory(widget.controller, category)} • ${item['amount']} ${widget.controller.currencySymbol} • $dueDate',
                      ),
                      trailing: Switch(
                        value: active,
                        onChanged: (_) => _toggle(item['id'].toString(), active),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

