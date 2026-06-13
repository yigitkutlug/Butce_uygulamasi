import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../state/app_controller.dart';
import '../utils/category_utils.dart';

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({
    super.key,
    required this.controller,
    required this.token,
  });

  final AppController controller;
  final String token;

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime _date = DateTime.now();
  bool _isIncome = false;
  bool _loading = false;
  String? _error;
  String? _selectedCategory;
  String _selectedAccount = 'Card';

  List<String> _expenseCategories = ['Food', 'Market', 'Transport', 'Other'];
  List<String> _incomeCategories = [
    'Salary',
    'Additional Income',
    'Scholarship',
    'Freelance',
    'Investment',
    'Rental Income',
    'Gift',
    'Other Income',
  ];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      // Kategoriler backend'den gelir; istek başarısız olursa aşağıdaki lokal
      // varsayılan listelerle form yine kullanılabilir kalır.
      final raw = await widget.controller.api.getCategories(widget.token);
      final expense = (raw['expense'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      final income = (raw['income'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      if (!mounted) return;
      setState(() {
        if (expense.isNotEmpty) _expenseCategories = expense;
        if (income.isNotEmpty) _incomeCategories = income;
      });
    } catch (_) {
      // Keep local fallback categories.
    }
  }

  List<DropdownMenuItem<String?>> _buildCategoryItems(
      String Function(String) t) {
    final categories = _isIncome ? _incomeCategories : _expenseCategories;
    return [
      // Null kategori "otomatik kategori tahmini yap" anlamına gelir; backend
      // açıklama metninden kategori üretir.
      DropdownMenuItem<String?>(value: null, child: Text(t('autoCategory'))),
      ...categories.map(
        (cat) => DropdownMenuItem<String?>(
          value: cat,
          child: Text(localizeCategory(widget.controller, cat)),
        ),
      ),
    ];
  }

  List<DropdownMenuItem<String>> _buildAccountItems(String Function(String) t) {
    return [
      DropdownMenuItem(value: 'Card', child: Text(t('accountCard'))),
      DropdownMenuItem(value: 'Cash', child: Text(t('accountCash'))),
      DropdownMenuItem(value: 'IBAN', child: Text(t('accountIban'))),
    ];
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    final t = (String key) => AppLocalizer.text(widget.controller, key);

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Kullanıcı virgül veya nokta kullanabilir; ikisi de double parse
      // edilebilsin diye virgül nokta yapılır.
      final amount =
          double.tryParse(_amountController.text.trim().replaceAll(',', '.')) ??
              0.0;
      if (amount == 0) throw Exception(t('amountNonZero'));
      // Backend gelirleri pozitif, giderleri negatif tutar. Switch seçimine
      // göre işaret burada belirlenir.
      final signedAmount = _isIncome ? amount.abs() : -amount.abs();
      await widget.controller.api.addTransaction(
        token: widget.token,
        amount: signedAmount,
        description: _descriptionController.text.trim(),
        date: _date,
        category: _selectedCategory,
        account: _selectedAccount,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (err) {
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppLocalizer.text(widget.controller, key);

    return Scaffold(
      appBar: AppBar(title: Text(t('addTransaction'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            SwitchListTile(
              title: Text(t('income')),
              value: _isIncome,
              onChanged: (v) => setState(() {
                // Gelir/gider tipi değişince eski kategori seçimi sıfırlanır;
                // çünkü iki tipin kategori listesi farklıdır.
                _isIncome = v;
                _selectedCategory = null;
              }),
            ),
            TextField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText:
                    '${t('amount')} (${widget.controller.currencySymbol})',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(labelText: t('description')),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              value: _selectedCategory,
              decoration: InputDecoration(
                labelText: t(_isIncome
                    ? 'incomeCategorySelect'
                    : 'expenseCategorySelect'),
              ),
              items: _buildCategoryItems(t),
              onChanged: (value) => setState(() => _selectedCategory = value),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedAccount,
              decoration: InputDecoration(labelText: t('accountType')),
              items: _buildAccountItems(t),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedAccount = value);
                }
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                    '${t('date')}: ${_date.toLocal().toString().split(' ')[0]}'),
                const SizedBox(width: 12),
                TextButton(onPressed: _pickDate, child: Text(t('pickDate'))),
              ],
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: Text(_loading ? t('saving') : t('save')),
            ),
          ],
        ),
      ),
    );
  }
}
