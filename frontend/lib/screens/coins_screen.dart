import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../models/investment_item.dart';
import '../services/crypto_service.dart';
import '../services/market_cache_service.dart';
import '../state/app_controller.dart';

class CoinsScreen extends StatefulWidget {
  const CoinsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<CoinsScreen> createState() => _CoinsScreenState();
}

class _CoinsScreenState extends State<CoinsScreen> {
  final _service = CryptoService();
  final _cache = MarketCacheService();
  bool _loading = true;
  bool _refreshing = false;
  bool _showingCachedData = false;
  String? _error;
  List<InvestmentItem> _items = [];
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    _loadCachedAndRefresh();
  }

  Future<void> _loadCachedAndRefresh() async {
    final cached = await _cache.loadCoins();
    if (cached != null && mounted) {
      setState(() {
        _items = cached.value;
        _updatedAt = cached.updatedAt;
        _showingCachedData = true;
        _loading = false;
      });
    }
    await _refreshCoins(showLoader: cached == null);
  }

  Future<void> _refreshCoins({required bool showLoader}) async {
    setState(() {
      if (showLoader) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
    });
    try {
      final items = await _service.fetchCoins();
      if (items.isNotEmpty) {
        await _cache.saveCoins(items);
      }
      setState(() {
        _items = items;
        _updatedAt = DateTime.now();
        _showingCachedData = false;
      });
    } catch (_) {
      setState(() {
        if (_items.isEmpty) {
          _error = AppLocalizer.text(widget.controller, 'marketDataError');
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

  String _formatPrice(double price, String currency) {
    final fixed = price >= 1000 ? price.toStringAsFixed(2) : price.toStringAsFixed(4);
    return '$fixed $currency';
  }

  String _turkeyTimeString(DateTime? dt) {
    if (dt == null) return '--:--';
    final tr = dt.toUtc().add(const Duration(hours: 3));
    final h = tr.hour.toString().padLeft(2, '0');
    final m = tr.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppLocalizer.text(widget.controller, key);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('coins')),
        actions: [
          IconButton(
            onPressed: () => _refreshCoins(showLoader: _items.isEmpty),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: t('refresh'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_refreshing)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4E5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFCC80)),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFF8A5A00),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (_showingCachedData)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
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
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('liveMarketData'), style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 6),
                          Text(t('coinMarket'), style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 4),
                          Text(
                            '${t('lastUpdated')}: ${_turkeyTimeString(_updatedAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._items.map(
                      (item) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          title: Text(item.symbol, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _formatPrice(item.price, item.currency),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${item.changePercent >= 0 ? '+' : ''}${item.changePercent.toStringAsFixed(2)}%',
                                style: TextStyle(
                                  color: item.changePercent >= 0
                                      ? const Color(0xFF15803D)
                                      : const Color(0xFFB91C1C),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
