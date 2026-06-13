import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../models/investment_item.dart';
import '../screens/alerts_screen.dart';
import '../screens/portfolio_screen.dart';
import '../services/investment_service.dart';
import '../services/investment_storage.dart';
import '../services/market_cache_service.dart';
import '../services/token_storage.dart';
import '../state/app_controller.dart';

class InvestmentsScreen extends StatefulWidget {
  const InvestmentsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<InvestmentsScreen> createState() => _InvestmentsScreenState();
}

class _InvestmentsScreenState extends State<InvestmentsScreen> {
  final _service = InvestmentService();
  final _storage = InvestmentStorage();
  final _cache = MarketCacheService();
  bool _loading = true;
  bool _refreshing = false;
  bool _showingCachedData = false;
  String? _error;
  List<InvestmentItem> _items = [];
  DateTime? _updatedAt;
  String? _token;
  Set<String> _favoriteSymbols = {};
  Map<String, Map<String, double>> _positions = {};

  @override
  void initState() {
    super.initState();
    _loadPrefsAndData();
  }

  Future<void> _loadPrefsAndData() async {
    try {
      _favoriteSymbols = await _storage.loadFavorites();
      _positions = await _storage.loadPositions();
    } catch (_) {
      _favoriteSymbols = {};
      _positions = {};
    }
    await _loadCachedAndRefresh();
  }

  Future<void> _loadCachedAndRefresh() async {
    final cached = await _cache.loadInvestments();
    if (cached != null && mounted) {
      setState(() {
        _items = cached.value;
        _updatedAt = cached.updatedAt;
        _showingCachedData = true;
        _loading = false;
      });
    }
    await _refreshMarket(showLoader: cached == null);
  }

  Future<void> _refreshMarket({required bool showLoader}) async {
    setState(() {
      if (showLoader) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
    });
    try {
      _token ??= await TokenStorage().getToken();
      final items = await _service.fetchInstruments();
      final now = DateTime.now();
      if (items.isNotEmpty) {
        await _cache.saveInvestments(items);
      }
      setState(() {
        _items = items;
        _updatedAt = now;
        _showingCachedData = false;
        _error = items.isEmpty ? (_service.lastError ?? 'Market data unavailable') : null;
      });
      await _checkTriggeredAlerts();
    } catch (err) {
      setState(() {
        _updatedAt = DateTime.now();
        if (_items.isEmpty) {
          _items = const [];
          _error = _service.lastError ?? err.toString();
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

  List<InvestmentItem> get _sortedItems {
    final list = [..._items];
    list.sort((a, b) {
      final aFav = _favoriteSymbols.contains(a.symbol.toUpperCase()) ? 1 : 0;
      final bFav = _favoriteSymbols.contains(b.symbol.toUpperCase()) ? 1 : 0;
      if (aFav != bFav) return bFav.compareTo(aFav);
      return a.symbol.compareTo(b.symbol);
    });
    return list;
  }

  Map<String, double> _portfolioTotals() {
    final bySymbol = {
      for (final item in _items) item.symbol.toUpperCase(): item.price,
    };
    double totalInvested = 0;
    double totalCurrent = 0;
    int counted = 0;

    for (final entry in _positions.entries) {
      final symbol = entry.key;
      final pos = entry.value;
      final quantity = pos['quantity'] ?? 0;
      final avgPrice = pos['avg_price'] ?? 0;
      if (quantity <= 0 || avgPrice <= 0) continue;
      final currentPrice = bySymbol[symbol];
      if (currentPrice == null || currentPrice <= 0) continue;

      totalInvested += quantity * avgPrice;
      totalCurrent += quantity * currentPrice;
      counted += 1;
    }

    return {
      'invested': totalInvested,
      'current': totalCurrent,
      'pnl': totalCurrent - totalInvested,
      'counted': counted.toDouble(),
    };
  }

  Future<void> _checkTriggeredAlerts() async {
    final token = _token;
    if (token == null) return;
    try {
      final events = await widget.controller.api.getAlertEvents(
        token: token,
        unreadOnly: true,
      );
      if (events.isEmpty || !mounted) return;

      final messages = events
          .whereType<Map<String, dynamic>>()
          .map((e) => (e['message'] ?? '').toString())
          .where((m) => m.isNotEmpty)
          .toList();

      if (messages.isNotEmpty) {
        final joined = messages.take(3).join('\n');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(joined),
            duration: const Duration(seconds: 6),
          ),
        );
      }

      for (final raw in events) {
        if (raw is! Map<String, dynamic>) continue;
        final id = raw['id']?.toString();
        if (id == null || id.isEmpty) continue;
        await widget.controller.api.markAlertEventRead(token: token, eventId: id);
      }
    } catch (_) {
      // Alert polling errors should not block market screen.
    }
  }

  Future<void> _openCreateAlertDialog(InvestmentItem item) async {
    final token = _token;
    if (token == null) return;
    final controller = TextEditingController(text: item.price > 0 ? item.price.toStringAsFixed(2) : '');
    String condition = 'above';
    final t = (String key) => AppLocalizer.text(widget.controller, key);

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setInner) {
            return AlertDialog(
              title: Text('${item.symbol} Alarm'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Hedef Fiyat',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: condition,
                    items: const [
                      DropdownMenuItem(value: 'above', child: Text('Üstüne çıkarsa')),
                      DropdownMenuItem(value: 'below', child: Text('Altına düşerse')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setInner(() => condition = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(t('clear')),
                ),
                FilledButton(
                  onPressed: () async {
                    final target = double.tryParse(controller.text.trim().replaceAll(',', '.'));
                    if (target == null || target <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Geçerli bir hedef fiyat gir.')),
                      );
                      return;
                    }
                    try {
                      await widget.controller.api.createPriceAlert(
                        token: token,
                        symbol: item.symbol,
                        targetPrice: target,
                        condition: condition,
                      );
                      if (!mounted) return;
                      Navigator.of(context).pop(true);
                    } catch (err) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(err.toString())),
                      );
                    }
                  },
                  child: const Text('Alarm Kur'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alarm oluşturuldu. Arka planda izlenecek.')),
      );
    }
  }

  String _formatPrice(double price, String currency) {
    if (price <= 0) return '-- $currency';
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
        title: Text(t('investmentAssets')),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AlertsScreen(controller: widget.controller),
                ),
              );
            },
            icon: const Icon(Icons.notifications_active_rounded),
            tooltip: t('alerts'),
          ),
          IconButton(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PortfolioScreen(controller: widget.controller),
                ),
              );
              if (!mounted) return;
              await _loadPrefsAndData();
            },
            icon: const Icon(Icons.account_balance_wallet_rounded),
            tooltip: t('portfolio'),
          ),
          IconButton(
            onPressed: () => _refreshMarket(showLoader: _items.isEmpty),
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
                          '${t('marketDataError')}: $_error',
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
                          Text(t('assetsMarket'), style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 4),
                          Text(
                            '${t('lastUpdated')}: ${_turkeyTimeString(_updatedAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_positions.isNotEmpty)
                      Builder(
                        builder: (context) {
                          final totals = _portfolioTotals();
                          final invested = totals['invested'] ?? 0;
                          final current = totals['current'] ?? 0;
                          final pnl = totals['pnl'] ?? 0;
                          final counted = (totals['counted'] ?? 0).toInt();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Portföy Simülasyonu',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                Text('Takip edilen pozisyon: $counted'),
                                Text('Toplam maliyet: ${invested.toStringAsFixed(2)}'),
                                Text('Güncel değer: ${current.toStringAsFixed(2)}'),
                                Text(
                                  'Kar/Zarar: ${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: pnl >= 0 ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    if (_items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          t('marketDataError'),
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ..._sortedItems.map(
                      (item) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          onTap: () => _openCreateAlertDialog(item),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          title: Text(item.symbol, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            _positions.containsKey(item.symbol.toUpperCase())
                                ? '${item.name} | ${t('portfolioPositionExists')}'
                                : item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
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

