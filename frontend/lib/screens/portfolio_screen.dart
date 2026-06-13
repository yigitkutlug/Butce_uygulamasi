import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../models/investment_item.dart';
import '../services/crypto_service.dart';
import '../services/investment_service.dart';
import '../services/investment_storage.dart';
import '../state/app_controller.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  final _investmentService = InvestmentService();
  final _cryptoService = CryptoService();
  final _storage = InvestmentStorage();

  bool _loading = true;
  String? _error;
  List<InvestmentItem> _investments = [];
  List<InvestmentItem> _coins = [];
  Map<String, Map<String, double>> _positions = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final positionMap = await _storage.loadPositions();
      final results = await Future.wait([
        _investmentService.fetchInstruments(),
        _cryptoService.fetchCoins(),
      ]);

      setState(() {
        _positions = positionMap;
        _investments = (results[0] as List<InvestmentItem>);
        _coins = (results[1] as List<InvestmentItem>);
      });
    } catch (err) {
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, InvestmentItem> get _catalogBySymbol {
    final all = <InvestmentItem>[..._investments, ..._coins];
    return {
      for (final item in all) item.symbol.toUpperCase(): item,
    };
  }

  Future<void> _editPosition(String symbol) async {
    final key = symbol.toUpperCase();
    final existing = _positions[key];
    final item = _catalogBySymbol[key];
    final displayName = item?.name ?? symbol;
    final qtyCtrl = TextEditingController(text: existing?['quantity']?.toStringAsFixed(4) ?? '');
    final avgCtrl = TextEditingController(
      text: existing?['avg_price']?.toStringAsFixed(4) ?? ((item?.price ?? 0) > 0 ? item!.price.toStringAsFixed(4) : ''),
    );

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('$key ${AppLocalizer.text(widget.controller, 'portfolio')}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  displayName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: AppLocalizer.text(widget.controller, 'portfolioQuantity')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: avgCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: AppLocalizer.text(widget.controller, 'portfolioAvgPrice')),
              ),
            ],
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () => Navigator.of(context).pop('delete'),
                child: Text(AppLocalizer.text(widget.controller, 'deleteAlert')),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: Text(AppLocalizer.text(widget.controller, 'back')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('save'),
              child: Text(AppLocalizer.text(widget.controller, 'save')),
            ),
          ],
        );
      },
    );

    if (result == 'delete') {
      setState(() {
        _positions.remove(key);
      });
      await _storage.savePositions(_positions);
    } else if (result == 'save') {
      final quantity = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.'));
      final avgPrice = double.tryParse(avgCtrl.text.trim().replaceAll(',', '.'));
      if (quantity == null || avgPrice == null || quantity <= 0 || avgPrice <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizer.text(widget.controller, 'portfolioInvalidInput'))),
          );
        }
      } else {
        setState(() {
          _positions[key] = {'quantity': quantity, 'avg_price': avgPrice};
        });
        await _storage.savePositions(_positions);
      }
    }

    qtyCtrl.dispose();
    avgCtrl.dispose();
  }

  Future<void> _openAddPositionDialog() async {
    final all = [..._investments, ..._coins];
    if (all.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizer.text(widget.controller, 'marketDataError'))),
      );
      return;
    }

    String selectedSymbol = all.first.symbol.toUpperCase();
    final qtyCtrl = TextEditingController();
    final avgCtrl = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setInner) {
            final selected = all.firstWhere(
              (e) => e.symbol.toUpperCase() == selectedSymbol,
              orElse: () => all.first,
            );
            if (avgCtrl.text.trim().isEmpty && selected.price > 0) {
              avgCtrl.text = selected.price.toStringAsFixed(4);
            }
            return AlertDialog(
              title: Text(AppLocalizer.text(widget.controller, 'portfolioAddInvestment')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedSymbol,
                    items: all
                        .map(
                          (item) => DropdownMenuItem<String>(
                            value: item.symbol.toUpperCase(),
                            child: Text('${item.symbol} • ${item.name}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setInner(() {
                        selectedSymbol = value;
                        final selectedItem = all.firstWhere(
                          (e) => e.symbol.toUpperCase() == selectedSymbol,
                          orElse: () => all.first,
                        );
                        if (selectedItem.price > 0) {
                          avgCtrl.text = selectedItem.price.toStringAsFixed(4);
                        }
                      });
                    },
                    decoration: InputDecoration(
                      labelText: AppLocalizer.text(widget.controller, 'portfolioAsset'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: AppLocalizer.text(widget.controller, 'portfolioQuantity')),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: avgCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: AppLocalizer.text(widget.controller, 'portfolioAvgPrice')),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop('cancel'),
                  child: Text(AppLocalizer.text(widget.controller, 'back')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop('save'),
                  child: Text(AppLocalizer.text(widget.controller, 'save')),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == 'save') {
      final quantity = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.'));
      final avgPrice = double.tryParse(avgCtrl.text.trim().replaceAll(',', '.'));
      if (quantity == null || avgPrice == null || quantity <= 0 || avgPrice <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizer.text(widget.controller, 'portfolioInvalidInput'))),
          );
        }
      } else {
        final key = selectedSymbol.toUpperCase();
        setState(() {
          _positions[key] = {'quantity': quantity, 'avg_price': avgPrice};
        });
        await _storage.savePositions(_positions);
      }
    }

    qtyCtrl.dispose();
    avgCtrl.dispose();
  }

  Map<String, double> get _portfolioSummary {
    final priceMap = {
      for (final entry in _catalogBySymbol.entries) entry.key: entry.value.price,
    };
    double invested = 0;
    double current = 0;
    for (final entry in _positions.entries) {
      final quantity = (entry.value['quantity'] ?? 0);
      final avg = (entry.value['avg_price'] ?? 0);
      if (quantity <= 0 || avg <= 0) continue;
      invested += quantity * avg;
      final nowPrice = priceMap[entry.key] ?? 0;
      if (nowPrice > 0) {
        current += quantity * nowPrice;
      }
    }
    return {
      'invested': invested,
      'current': current,
      'pnl': current - invested,
    };
  }

  List<String> get _positionSymbols {
    final keys = _positions.keys.toList()..sort();
    return keys;
  }

  Widget _summaryCard() {
    final s = _portfolioSummary;
    final invested = s['invested'] ?? 0;
    final current = s['current'] ?? 0;
    final pnl = s['pnl'] ?? 0;
    final pnlColor = pnl >= 0 ? const Color(0xFF15803D) : const Color(0xFFB91C1C);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizer.text(widget.controller, 'portfolioSummary'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text('${AppLocalizer.text(widget.controller, 'portfolioTotalInvested')}: ${invested.toStringAsFixed(2)}'),
          Text('${AppLocalizer.text(widget.controller, 'portfolioCurrentValue')}: ${current.toStringAsFixed(2)}'),
          Text(
            '${AppLocalizer.text(widget.controller, 'portfolioPnl')}: ${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}',
            style: TextStyle(fontWeight: FontWeight.w700, color: pnlColor),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppLocalizer.text(widget.controller, key);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('portfolio')),
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
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _summaryCard(),
                    if (_positionSymbols.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          t('portfolioEmpty'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ..._positionSymbols.map((symbol) {
                      final item = _catalogBySymbol[symbol];
                      final pos = _positions[symbol] ?? const {};
                      final quantity = pos['quantity'] ?? 0;
                      final avg = pos['avg_price'] ?? 0;
                      final current = (item?.price ?? 0);
                      final invested = quantity * avg;
                      final currentValue = quantity * current;
                      final pnl = current > 0 ? (currentValue - invested) : 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: () => _editPosition(symbol),
                          title: Text(symbol, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            '${item?.name ?? '-'}\n'
                            '${t('portfolioQuantity')}: ${quantity.toStringAsFixed(4)} | '
                            '${t('portfolioAvgPrice')}: ${avg.toStringAsFixed(4)}',
                          ),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${t('portfolioCurrentValue')}: ${currentValue.toStringAsFixed(2)}'),
                              Text(
                                '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: pnl >= 0 ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddPositionDialog,
        tooltip: t('portfolioAddInvestment'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
