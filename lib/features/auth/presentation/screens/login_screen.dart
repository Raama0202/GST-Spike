import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gst_expense_scanner/core/config/server_config.dart';
import 'package:gst_expense_scanner/core/constants/app_constants.dart';
import 'package:gst_expense_scanner/core/theme/glass.dart';
import 'package:gst_expense_scanner/features/auth/presentation/providers/auth_providers.dart';
import 'package:gst_expense_scanner/features/settings/presentation/server_endpoint_dialog.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mobileController = TextEditingController();
  bool _rememberLogin = true;
  bool _submitting = false;

  @override
  void dispose() {
    _mobileController.dispose();
    super.dispose();
  }

  String? _validateMobile(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) {
      return 'Enter a valid 10-digit Indian mobile number';
    }
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
      return 'Mobile number must start with 6, 7, 8, or 9';
    }
    return null;
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    final mobile = _mobileController.text.replaceAll(RegExp(r'\D'), '');
    setState(() => _submitting = true);

    await ref.read(authStateProvider.notifier).sendOtp(mobile);

    if (!mounted) return;
    setState(() => _submitting = false);

    final authState = ref.read(authStateProvider);
    if (authState is AuthErrorState) {
      _showMessage(authState.message);
      ref.read(authStateProvider.notifier).clearError();
      return;
    }

    context.push(
      '/otp',
      extra: {'mobile': mobile, 'rememberLogin': _rememberLogin},
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authStateProvider);
    final loading = _submitting || authState is AuthAuthenticating;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: IconBadge(
                        icon: Icons.receipt_long_rounded,
                        color: theme.colorScheme.primary,
                        size: 76,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppConstants.appName,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Snap GST bills, we handle the rest',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Brand.muted,
                      ),
                    ),
                    const SizedBox(height: 32),
                    GlassCard(
                      blur: true,
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Sign in', style: theme.textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Text(
                            'Use your registered mobile number',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _mobileController,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.done,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Mobile number',
                              prefixIcon: Icon(Icons.phone_iphone_rounded),
                              prefixText: '+91 ',
                              hintText: '9876543210',
                            ),
                            validator: _validateMobile,
                            onFieldSubmitted: (_) => _sendOtp(),
                          ),
                          const SizedBox(height: 16),
                          CheckboxListTile(
                            value: _rememberLogin,
                            onChanged: loading
                                ? null
                                : (value) {
                                    setState(
                                      () => _rememberLogin = value ?? true,
                                    );
                                  },
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('Remember login on this device'),
                          ),
                          const SizedBox(height: 16),
                          GlassButton(
                            label: 'Send OTP',
                            icon: Icons.arrow_forward_rounded,
                            loading: loading,
                            onPressed: _sendOtp,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.lock_rounded,
                          size: 14,
                          color: Brand.muted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Secured with one-time passcode',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    if (ServerConfig.canOverride) ...[
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: loading
                            ? null
                            : () => ServerEndpointDialog.show(context),
                        icon: const Icon(Icons.dns_outlined, size: 18),
                        label: Text('Server: ${ServerConfig.displayHost}'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
