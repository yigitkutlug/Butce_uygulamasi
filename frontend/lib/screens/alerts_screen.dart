import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../services/token_storage.dart';
import '../state/app_controller.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _alerts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String> _token() async {
    // Bu ekran tamamen kullanıcıya bağlı alarm verisiyle çalıştığı için token
    // yoksa hiçbir API isteği yapılmaz.
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
      // Alarm listesi backend'deki price_alerts koleksiyonundan gelir; eventler
      // bildirim servisi tarafından ayrıca okunur.
      final token = await _token();
      final raw = await widget.controller.api.getPriceAlerts(token: token);
      _alerts = raw.whereType<Map<String, dynamic>>().toList();
    } catch (err) {
      _error = err.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteAlert(String id) async {
    try {
      final token = await _token();
      await widget.controller.api.deletePriceAlert(token: token, alertId: id);
      await _load();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err.toString())));
    }
  }

  Future<void> _editAlert(Map<String, dynamic> alert) async {
    // Düzenleme dialog içinde yapılır; kullanıcı kaydetmeden mevcut alarm
    // listesi değişmez.
    final priceCtrl = TextEditingController(
      text:
          (alert['target_price'] as num?)?.toDouble().toStringAsFixed(2) ?? '',
    );
    String condition = (alert['condition'] ?? 'above').toString();
    bool isActive = (alert['is_active'] as bool?) ?? true;
    final symbol = (alert['symbol'] ?? '').toString();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setInner) {
            return AlertDialog(
              title: Text('$symbol Alarmı'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: priceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Hedef Fiyat'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: condition,
                    items: const [
                      DropdownMenuItem(
                          value: 'above', child: Text('Üstüne çıkarsa')),
                      DropdownMenuItem(
                          value: 'below', child: Text('Altına düşerse')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setInner(() => condition = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: isActive,
                    onChanged: (v) => setInner(() => isActive = v),
                    title: const Text('Alarm Aktif'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(AppLocalizer.text(widget.controller, 'back')),
                ),
                FilledButton(
                  onPressed: () async {
                    // Hedef fiyat pozitif sayı olmalı; aksi durumda backend'e
                    // istek atmadan kullanıcı uyarılır.
                    final target = double.tryParse(
                        priceCtrl.text.trim().replaceAll(',', '.'));
                    if (target == null || target <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Geçerli bir hedef fiyat gir.')),
                      );
                      return;
                    }
                    try {
                      final token = await _token();
                      await widget.controller.api.updatePriceAlert(
                        token: token,
                        alertId: (alert['id'] ?? '').toString(),
                        targetPrice: target,
                        condition: condition,
                        isActive: isActive,
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
                  child: Text(AppLocalizer.text(widget.controller, 'save')),
                ),
              ],
            );
          },
        );
      },
    );
    priceCtrl.dispose();
    if (saved == true) {
      // Kaydetme başarılıysa liste yeniden çekilir; aktif/pasif rozetleri güncel
      // backend durumunu gösterir.
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppLocalizer.text(widget.controller, key);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('alerts')),
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
              : _alerts.isEmpty
                  ? Center(child: Text(t('noAlerts')))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _alerts.length,
                      itemBuilder: (context, index) {
                        final item = _alerts[index];
                        final symbol = (item['symbol'] ?? '-').toString();
                        final condition =
                            (item['condition'] ?? 'above').toString();
                        final target =
                            (item['target_price'] as num?)?.toDouble() ?? 0;
                        final active = (item['is_active'] as bool?) ?? false;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            title: Text(symbol,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${condition == 'above' ? t('alertAbove') : t('alertBelow')} ${target.toStringAsFixed(2)}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (active
                                        ? const Color(0xFFDFF5E8)
                                        : const Color(0xFFF3F4F6)),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    active ? t('active') : t('inactive'),
                                    style: TextStyle(
                                      color: active
                                          ? const Color(0xFF166534)
                                          : scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _editAlert(item),
                                  icon: const Icon(Icons.edit_rounded),
                                  tooltip: t('editAlert'),
                                ),
                                IconButton(
                                  onPressed: () => _deleteAlert(
                                      (item['id'] ?? '').toString()),
                                  icon:
                                      const Icon(Icons.delete_outline_rounded),
                                  tooltip: t('deleteAlert'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
