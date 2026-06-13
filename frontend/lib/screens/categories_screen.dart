import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../models/transaction.dart';
import '../services/token_storage.dart';
import '../state/app_controller.dart';
import '../utils/category_utils.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  bool _loading = true;
  String? _error;
  List<TransactionItem> _transactions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _formatMoney(num value) {
    final symbol = widget.controller.currencySymbol;
    final fixed = value.abs().toStringAsFixed(2);
    return value < 0 ? '-$fixed $symbol' : '$fixed $symbol';
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
      setState(() {
        _transactions = txRaw.map((e) => TransactionItem.fromJson(e)).toList();
      });
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

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(t('categories'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(t('categories'))),
        body: Center(child: Text(_error!)),
      );
    }

    final grouped = <String, List<TransactionItem>>{};
    for (final tx in _transactions) {
      grouped.putIfAbsent(tx.category, () => []).add(tx);
    }
    final keys = grouped.keys.toList()
      ..sort((a, b) {
        final aTotal = grouped[a]!.fold<double>(0, (p, e) => p + e.amount.abs());
        final bTotal = grouped[b]!.fold<double>(0, (p, e) => p + e.amount.abs());
        return bTotal.compareTo(aTotal);
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(t('categories')),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: t('refresh'),
          )
        ],
      ),
      body: keys.isEmpty
          ? Center(child: Text(t('noCategoryData')))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: keys.length,
              itemBuilder: (context, index) {
                final key = keys[index];
                final items = grouped[key]!;
                final total = items.fold<double>(0, (p, e) => p + e.amount.abs());
                final localized = localizeCategory(widget.controller, key);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    title: Text(localized, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${items.length} ${t('recentTransactions').toLowerCase()}'),
                    trailing: Text(
                      _formatMoney(total),
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    children: [
                      for (final tx in items.take(20))
                        ListTile(
                          dense: true,
                          title: Text(tx.description),
                          subtitle: Text(tx.date.toLocal().toString().split(' ')[0]),
                          trailing: Text(
                            _formatMoney(tx.amount),
                            style: TextStyle(
                              color: tx.amount >= 0 ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

