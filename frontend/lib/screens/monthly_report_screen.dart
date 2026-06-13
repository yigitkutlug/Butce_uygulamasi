import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../services/report_export_service.dart';
import '../services/token_storage.dart';
import '../state/app_controller.dart';

class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  final _exportService = ReportExportService();
  bool _loading = true;
  String? _error;
  String? _token;
  List<Map<String, dynamic>> _monthly = [];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await TokenStorage().getToken();
      if (token == null) throw Exception(AppLocalizer.text(widget.controller, 'missingToken'));
      _token = token;
      final summary = await widget.controller.api.getSummary(token);
      final monthlyRaw = (summary['monthly_summary'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      _monthly = monthlyRaw.reversed.toList();
    } catch (err) {
      _error = err.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _exportCsv() async {
    final t = (String key) => AppLocalizer.text(widget.controller, key);
    try {
      final token = _token ?? await TokenStorage().getToken();
      if (token == null) throw Exception(t('missingToken'));
      final bytes = await widget.controller.api.exportCsv(token);
      final path = await _exportService.saveCsv(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t('exportSaved')}: $path')),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t('exportFailed')}: $err')),
      );
    }
  }

  Future<void> _exportPdf() async {
    final t = (String key) => AppLocalizer.text(widget.controller, key);
    try {
      final path = await _exportService.savePdfFromMonthly(
        monthly: _monthly,
        currencySymbol: widget.controller.currencySymbol,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t('exportSaved')}: $path')),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t('exportFailed')}: $err')),
      );
    }
  }

  String _formatMoney(num value) {
    final symbol = widget.controller.currencySymbol;
    return '${value.toStringAsFixed(2)} $symbol';
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppLocalizer.text(widget.controller, key);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('monthlyReport')),
        actions: [
          IconButton(
            onPressed: _monthly.isEmpty ? null : _exportCsv,
            icon: const Icon(Icons.table_view_rounded),
            tooltip: t('exportCsv'),
          ),
          IconButton(
            onPressed: _monthly.isEmpty ? null : _exportPdf,
            icon: const Icon(Icons.picture_as_pdf_rounded),
            tooltip: t('exportPdf'),
          ),
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
              : _monthly.isEmpty
                  ? Center(child: Text(t('noTransactions')))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _monthly.length,
                      itemBuilder: (context, index) {
                        final m = _monthly[index];
                        final income = (m['income'] as num? ?? 0).toDouble();
                        final expense = (m['expense'] as num? ?? 0).toDouble();
                        final net = income - expense;
                        final maxV = (income > expense ? income : expense).clamp(1.0, double.infinity);
                        final incomeRatio = income / maxV;
                        final expenseRatio = expense / maxV;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${t('month')}: ${m['month']}',
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                    ),
                                    Text(
                                      '${t('net')}: ${_formatMoney(net)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: net >= 0 ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text('${t('totalIncome')}: ${_formatMoney(income)}'),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: incomeRatio,
                                    minHeight: 8,
                                    backgroundColor: const Color(0xFFE5E7EB),
                                    color: const Color(0xFF0EA5A4),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text('${t('totalExpense')}: ${_formatMoney(expense)}'),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: expenseRatio,
                                    minHeight: 8,
                                    backgroundColor: const Color(0xFFE5E7EB),
                                    color: const Color(0xFFE11D48),
                                  ),
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
