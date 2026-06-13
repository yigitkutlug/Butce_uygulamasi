import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../services/token_storage.dart';
import '../state/app_controller.dart';

class AiMetricsScreen extends StatefulWidget {
  const AiMetricsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<AiMetricsScreen> createState() => _AiMetricsScreenState();
}

class _AiMetricsScreenState extends State<AiMetricsScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _metrics = {};

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
      final token = await TokenStorage().getToken();
      if (token == null) throw Exception(AppLocalizer.text(widget.controller, 'missingToken'));
      final metrics = await widget.controller.api.getMlMetrics(token);
      _metrics = metrics;
    } catch (err) {
      _error = err.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppLocalizer.text(widget.controller, key);
    final accuracy = (_metrics['validation_accuracy'] as num?)?.toDouble();
    final precision = (_metrics['validation_precision'] as num?)?.toDouble();
    final recall = (_metrics['validation_recall'] as num?)?.toDouble();
    final f1 = (_metrics['validation_f1'] as num?)?.toDouble();
    final sourceCounts = Map<String, dynamic>.from(_metrics['source_counts'] as Map? ?? {});
    final perCategory = (_metrics['per_category_counts'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final thesis = Map<String, dynamic>.from(_metrics['thesis_ready_summary'] as Map? ?? {});

    return Scaffold(
      appBar: AppBar(
        title: Text(t('aiPerformance')),
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
                    _SectionTitle(text: t('aiPerformance')),
                    _MetricCard(
                      title: t('totalTrainingSamples'),
                      value: '${_metrics['total_samples'] ?? 0}',
                    ),
                    _MetricCard(
                      title: t('correctedSamples'),
                      value: '${_metrics['corrected_samples'] ?? 0}',
                    ),
                    _MetricCard(
                      title: t('uniqueCategories'),
                      value: '${_metrics['unique_categories'] ?? 0}',
                    ),
                    _MetricCard(
                      title: t('validationAccuracy'),
                      value: accuracy == null ? '-' : '%${(accuracy * 100).toStringAsFixed(1)}',
                    ),
                    _MetricCard(
                      title: 'Precision',
                      value: precision == null ? '-' : '%${(precision * 100).toStringAsFixed(1)}',
                    ),
                    _MetricCard(
                      title: 'Recall',
                      value: recall == null ? '-' : '%${(recall * 100).toStringAsFixed(1)}',
                    ),
                    _MetricCard(
                      title: 'F1-Score',
                      value: f1 == null ? '-' : '%${(f1 * 100).toStringAsFixed(1)}',
                    ),
                    _MetricCard(
                      title: t('lastRetrainAt'),
                      value: (_metrics['last_retrain_at'] ?? '-').toString(),
                    ),
                    _MetricCard(
                      title: t('lastRetrainSamples'),
                      value: '${_metrics['last_retrain_samples'] ?? 0}',
                    ),
                    const SizedBox(height: 12),
                    _SectionTitle(text: t('datasetSources')),
                    _MetricCard(title: 'Seed', value: '${sourceCounts['seed'] ?? 0}'),
                    _MetricCard(title: 'Manual', value: '${sourceCounts['manual'] ?? 0}'),
                    _MetricCard(title: 'Corrected', value: '${sourceCounts['corrected'] ?? 0}'),
                    const SizedBox(height: 12),
                    _SectionTitle(text: t('perCategoryDistribution')),
                    if (perCategory.isEmpty)
                      const Card(child: ListTile(title: Text('-')))
                    else
                      ...perCategory.take(8).map(
                        (row) => _MetricCard(
                          title: row['category'].toString(),
                          value: '${row['count'] ?? 0}',
                        ),
                      ),
                    const SizedBox(height: 12),
                    _SectionTitle(text: t('thesisSummary')),
                    _MetricCard(
                      title: 'Dataset Total',
                      value: '${thesis['dataset_total'] ?? 0}',
                    ),
                    _MetricCard(
                      title: 'Seed Samples',
                      value: '${thesis['dataset_seed'] ?? 0}',
                    ),
                    _MetricCard(
                      title: 'User Labeled Samples',
                      value: '${thesis['dataset_user_labeled'] ?? 0}',
                    ),
                    _MetricCard(
                      title: 'Model Accuracy %',
                      value: '${thesis['model_accuracy_percent'] ?? '-'}',
                    ),
                    _MetricCard(
                      title: 'Model Precision %',
                      value: '${thesis['model_precision_percent'] ?? '-'}',
                    ),
                    _MetricCard(
                      title: 'Model Recall %',
                      value: '${thesis['model_recall_percent'] ?? '-'}',
                    ),
                    _MetricCard(
                      title: 'Model F1 %',
                      value: '${thesis['model_f1_percent'] ?? '-'}',
                    ),
                    _MetricCard(
                      title: 'Auto Retrain Rule',
                      value: '${thesis['auto_retrain_rule'] ?? '-'}',
                    ),
                  ],
                ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(title),
        trailing: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
