import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../services/exchange_service.dart';
import '../services/market_cache_service.dart';
import '../state/app_controller.dart';

class ExchangeRatesScreen extends StatefulWidget {
  const ExchangeRatesScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ExchangeRatesScreen> createState() => _ExchangeRatesScreenState();
}

class _ExchangeRatesScreenState extends State<ExchangeRatesScreen> {
  static const _currencies = ['USD', 'EUR', 'TRY', 'GBP'];
  final _amountController = TextEditingController(text: '1');
  final _service = ExchangeService();
  final _cache = MarketCacheService();

  String _base = 'USD';
  bool _loading = true;
  bool _refreshing = false;
  bool _showingCachedData = false;
  String? _error;
  Map<String, double> _rates = {};
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    _loadCachedAndRefresh();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadCachedAndRefresh() async {
    final cached = await _cache.loadExchangeRates(_base);
    if (cached != null && mounted) {
      setState(() {
        _rates = cached.value;
        _updatedAt = cached.updatedAt;
        _showingCachedData = true;
        _loading = false;
      });
    }
    await _refreshRates(showLoader: cached == null);
  }

  Future<void> _refreshRates({required bool showLoader}) async {
    setState(() {
      if (showLoader) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
    });
    try {
      final rates = await _service.fetchRates(base: _base);
      await _cache.saveExchangeRates(_base, rates);
      setState(() {
        _rates = rates;
        _updatedAt = DateTime.now();
        _showingCachedData = false;
      });
    } catch (_) {
      setState(() {
        if (_rates.isEmpty) {
          _error = AppLocalizer.text(widget.controller, 'fxError');
        } else {
          _showingCachedData = true;
          _error = 'Canlı veri alınamadı. Önbellekteki son veri gösteriliyor.';
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  String _turkeyTimeString(DateTime? dt) {
    if (dt == null) return '--:--';
    final tr = dt.toUtc().add(const Duration(hours: 3));
    final h = tr.hour.toString().padLeft(2, '0');
    final m = tr.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatValue(double value) {
    if (value >= 1000) return value.toStringAsFixed(2);
    return value.toStringAsFixed(4);
  }

  Color _currencyColor(String code) {
    switch (code) {
      case 'EUR':
        return const Color(0xFF2563EB);
      case 'GBP':
        return const Color(0xFF7C3AED);
      case 'TRY':
        return const Color(0xFF0E9F6E);
      default:
        return const Color(0xFF0891B2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppLocalizer.text(widget.controller, key);
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 1.0;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('exchangeRates')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: () => _refreshRates(showLoader: _rates.isEmpty),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: t('refresh'),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.28),
              scheme.surface,
              scheme.tertiaryContainer.withValues(alpha: 0.2),
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primary.withValues(alpha: 0.14),
                    scheme.secondary.withValues(alpha: 0.12),
                  ],
                ),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.currency_exchange_rounded, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('liveMarketData'), style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          '${t('updatedNow')}: ${_turkeyTimeString(_updatedAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.84),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('baseCurrency'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _base,
                    items: _currencies
                        .map((c) => DropdownMenuItem<String>(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _base = value);
                      _loadCachedAndRefresh();
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(t('amountToConvert'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.calculate_rounded),
                      suffixText: _base,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (_refreshing)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFCDD2)),
                ),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
              ),
            if (_showingCachedData)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F3FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFB3D8FF)),
                ),
                child: const Text(
                  'Önbellekteki son veri gösteriliyor, canlı veri arka planda yenileniyor.',
                  style: TextStyle(
                    color: Color(0xFF1B4D89),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (!_loading && _rates.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.84),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('conversionResult'), style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    ..._rates.entries.map(
                      (entry) {
                        final converted = amount * entry.value;
                        final color = _currencyColor(entry.key);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: color.withValues(alpha: 0.22),
                                child: Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: color,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_formatValue(converted)} ${entry.key}',
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                    ),
                                    const SizedBox(height: 2),
                                    Text('1 $_base = ${entry.value.toStringAsFixed(4)} ${entry.key}'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
