import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../models/transaction.dart';
import '../services/token_storage.dart';
import '../state/app_controller.dart';
import '../utils/category_utils.dart';

class TransactionsByTypeScreen extends StatefulWidget {
  const TransactionsByTypeScreen({
    super.key,
    required this.controller,
    required this.showIncome,
  });

  final AppController controller;
  final bool showIncome;

  @override
  State<TransactionsByTypeScreen> createState() => _TransactionsByTypeScreenState();
}

class _TransactionsByTypeScreenState extends State<TransactionsByTypeScreen> {
  bool _loading = true;
  String? _error;
  List<TransactionItem> _allTransactions = [];
  List<TransactionItem> _transactions = [];

  final _searchController = TextEditingController();
  final _minController = TextEditingController();
  final _maxController = TextEditingController();
  String? _selectedCategory;
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await TokenStorage().getToken();
      if (token == null) throw Exception(AppLocalizer.text(widget.controller, 'missingToken'));
      final txRaw = await widget.controller.api.getTransactions(token);
      final all = txRaw.map((e) => TransactionItem.fromJson(e)).toList();
      _allTransactions = all.where((tx) => widget.showIncome ? tx.amount >= 0 : tx.amount < 0).toList();
      _applyFilters();
    } catch (err) {
      _error = err.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  double? _parseAmount(String value) {
    if (value.trim().isEmpty) return null;
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    final min = _parseAmount(_minController.text);
    final max = _parseAmount(_maxController.text);

    final filtered = _allTransactions.where((tx) {
      final absAmount = tx.amount.abs();
      if (query.isNotEmpty &&
          !tx.description.toLowerCase().contains(query) &&
          !tx.category.toLowerCase().contains(query)) {
        return false;
      }
      if (_selectedCategory != null && tx.category != _selectedCategory) {
        return false;
      }
      if (min != null && absAmount < min) {
        return false;
      }
      if (max != null && absAmount > max) {
        return false;
      }
      if (_fromDate != null) {
        final from = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
        final d = DateTime(tx.date.year, tx.date.month, tx.date.day);
        if (d.isBefore(from)) {
          return false;
        }
      }
      if (_toDate != null) {
        final to = DateTime(_toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59);
        if (tx.date.isAfter(to)) {
          return false;
        }
      }
      return true;
    }).toList();

    setState(() {
      _transactions = filtered;
    });
  }

  void _clearFilters() {
    _searchController.clear();
    _minController.clear();
    _maxController.clear();
    _selectedCategory = null;
    _fromDate = null;
    _toDate = null;
    _applyFilters();
  }

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final initial = isFrom ? (_fromDate ?? now) : (_toDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
    _applyFilters();
  }

  String _formatMoney(num value) {
    final symbol = widget.controller.currencySymbol;
    final fixed = value.abs().toStringAsFixed(2);
    return value < 0 ? '-$fixed $symbol' : '+$fixed $symbol';
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppLocalizer.text(widget.controller, key);
    final title = widget.showIncome ? t('incomeList') : t('expenseList');
    final categories = _allTransactions.map((e) => e.category).toSet().toList()..sort();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: t('refresh'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: t('search'),
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.filter_alt_rounded),
                                onPressed: _applyFilters,
                                tooltip: t('filter'),
                              ),
                            ),
                            onChanged: (_) => _applyFilters(),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String?>(
                                  value: _selectedCategory,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    hintText: t('allCategories'),
                                  ),
                                  items: [
                                    DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text(t('allCategories')),
                                    ),
                                    ...categories.map(
                                      (cat) => DropdownMenuItem<String?>(
                                        value: cat,
                                        child: Text(localizeCategory(widget.controller, cat)),
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    setState(() => _selectedCategory = value);
                                    _applyFilters();
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _minController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(hintText: t('minAmount')),
                                  onChanged: (_) => _applyFilters(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _maxController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(hintText: t('maxAmount')),
                                  onChanged: (_) => _applyFilters(),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              SizedBox(
                                width: 150,
                                child: OutlinedButton.icon(
                                  onPressed: () => _pickDate(true),
                                  icon: const Icon(Icons.date_range_rounded),
                                  label: Text(
                                    _fromDate == null
                                        ? t('fromDate')
                                        : _fromDate!.toIso8601String().split('T').first,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 150,
                                child: OutlinedButton.icon(
                                  onPressed: () => _pickDate(false),
                                  icon: const Icon(Icons.event_rounded),
                                  label: Text(
                                    _toDate == null ? t('toDate') : _toDate!.toIso8601String().split('T').first,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _clearFilters,
                                child: Text(t('clear')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _transactions.isEmpty
                          ? Center(child: Text(t('noTransactions')))
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _transactions.length,
                              itemBuilder: (context, index) {
                                final tx = _transactions[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: ListTile(
                                    title: Text(tx.description),
                                    subtitle: Text(
                                      '${localizeCategory(widget.controller, tx.category)} • ${tx.date.toLocal().toString().split(' ')[0]}',
                                    ),
                                    trailing: Text(
                                      _formatMoney(tx.amount),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: tx.amount >= 0 ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
