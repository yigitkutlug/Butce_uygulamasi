import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../state/app_controller.dart';
import '../widgets/brand_mark.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppLocalizer.text(controller, key);
    return Scaffold(
      appBar: AppBar(title: Text(t('about'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const BrandMark(size: 44, radius: 14),
                      const SizedBox(width: 10),
                      Text(
                        t('appTitle'),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(t('aboutSubtitle')),
                  const SizedBox(height: 10),
                  const Text('v1.0.0'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _FeatureRow(
                      icon: Icons.smart_toy_rounded,
                      text: 'AI kategori tahmini'),
                  _FeatureRow(
                      icon: Icons.bar_chart_rounded,
                      text: 'Aylık özet ve trend takibi'),
                  _FeatureRow(
                      icon: Icons.currency_exchange_rounded,
                      text: 'Canlı döviz dönüştürme'),
                  _FeatureRow(
                      icon: Icons.security_rounded,
                      text: 'JWT tabanlı güvenli oturum'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
