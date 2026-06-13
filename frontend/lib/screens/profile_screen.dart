import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../services/token_storage.dart';
import '../state/app_controller.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _monthlyIncomeController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _consentSaving = false;
  String? _email;
  String? _error;
  bool _aiConsent = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _monthlyIncomeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await TokenStorage().getToken();
      if (token == null) {
        throw Exception(AppLocalizer.text(widget.controller, 'missingToken'));
      }
      final profile = await widget.controller.api.getProfile(token);
      _email = (profile['email'] ?? '').toString();
      final monthly = (profile['monthly_income'] as num? ?? 0).toDouble();
      _aiConsent = profile['ai_data_consent'] as bool? ?? false;
      _monthlyIncomeController.text = monthly <= 0 ? '' : monthly.toStringAsFixed(2);
    } catch (err) {
      _error = err.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final monthlyIncome =
        double.tryParse(_monthlyIncomeController.text.trim().replaceAll(',', '.')) ?? 0;
    if (monthlyIncome <= 0) {
      setState(() => _error = AppLocalizer.text(widget.controller, 'monthlyIncomeRequired'));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final token = await TokenStorage().getToken();
      if (token == null) {
        throw Exception(AppLocalizer.text(widget.controller, 'missingToken'));
      }
      await widget.controller.api.updateProfile(token: token, monthlyIncome: monthlyIncome);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizer.text(widget.controller, 'profileSaved'))),
      );
      Navigator.of(context).pop(true);
    } catch (err) {
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _updateConsent(bool value) async {
    setState(() {
      _consentSaving = true;
      _error = null;
    });
    try {
      final token = await TokenStorage().getToken();
      if (token == null) {
        throw Exception(AppLocalizer.text(widget.controller, 'missingToken'));
      }
      await widget.controller.api.updateConsent(token: token, aiDataConsent: value);
      if (!mounted) return;
      setState(() => _aiConsent = value);
    } catch (err) {
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _consentSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppLocalizer.text(widget.controller, key);

    return Scaffold(
      appBar: AppBar(title: Text(t('profile'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('email'), style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 4),
                        Text(_email ?? '-', style: Theme.of(context).textTheme.bodyLarge),
                        const SizedBox(height: 16),
                        Text(t('monthlyIncome'), style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _monthlyIncomeController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            hintText: t('monthlyIncomeHint'),
                            prefixIcon: const Icon(Icons.account_balance_wallet_rounded),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _aiConsent,
                          onChanged: _consentSaving ? null : _updateConsent,
                          title: Text(t('aiDataConsent')),
                        ),
                        const SizedBox(height: 12),
                        if (_error != null)
                          Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
                        if (_error != null) const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save_rounded),
                          label: Text(_saving ? t('saving') : t('save')),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
