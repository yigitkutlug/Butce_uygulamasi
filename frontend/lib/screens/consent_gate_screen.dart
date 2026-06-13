import 'package:flutter/material.dart';

import '../localization/app_localizer.dart';
import '../services/token_storage.dart';
import '../state/app_controller.dart';
import '../utils/error_messages.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

class ConsentGateScreen extends StatefulWidget {
  const ConsentGateScreen({
    super.key,
    required this.controller,
    required this.token,
  });

  final AppController controller;
  final String token;

  @override
  State<ConsentGateScreen> createState() => _ConsentGateScreenState();
}

class _ConsentGateScreenState extends State<ConsentGateScreen> {
  bool _loading = true;
  String? _error;
  bool? _consent;
  bool _onboardingCompleted = false;
  double _monthlyIncome = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await widget.controller.api.getProfile(widget.token);
      _consent = profile['ai_data_consent'] as bool?;
      _onboardingCompleted = profile['onboarding_completed'] as bool? ?? false;
      _monthlyIncome = (profile['monthly_income'] as num?)?.toDouble() ?? 0.0;
    } catch (err) {
      if (isAuthExpiredError(err)) {
        await _logout();
        return;
      }
      _error = userFacingError(err);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setConsent(bool value) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.controller.api.updateConsent(
        token: widget.token,
        aiDataConsent: value,
      );
      _consent = value;
    } catch (err) {
      _error = userFacingError(err);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await TokenStorage().clear();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
          builder: (_) => LoginScreen(controller: widget.controller)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppLocalizer.text(widget.controller, key);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(t('dataConsentTitle'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _loadProfile,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(t('retry')),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(t('logout')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_consent == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t('dataConsentTitle'))),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('dataConsentBody'),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _setConsent(true),
                icon: const Icon(Icons.check_circle_rounded),
                label: Text(t('consentAllow')),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _setConsent(false),
                icon: const Icon(Icons.cancel_rounded),
                label: Text(t('consentDeny')),
              ),
            ],
          ),
        ),
      );
    }

    if (!_onboardingCompleted) {
      return OnboardingScreen(
        controller: widget.controller,
        token: widget.token,
        initialMonthlyIncome: _monthlyIncome,
      );
    }

    return DashboardScreen(controller: widget.controller);
  }
}
