import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gst_expense_scanner/core/config/server_config.dart';
import 'package:gst_expense_scanner/core/constants/app_constants.dart';
import 'package:gst_expense_scanner/core/theme/glass.dart';
import 'package:gst_expense_scanner/core/utils/mobile_number.dart';
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

  Future<void> _sendOtp() async {
    if (_submitting || !_formKey.currentState!.validate()) return;

    final mobile = IndianMobile.normalize(_mobileController.text);
    if (mobile == null) return;
    setState(() => _submitting = true);

    final delivery = await ref.read(authStateProvider.notifier).sendOtp(mobile);

    if (!mounted) return;
    setState(() => _submitting = false);

    final authState = ref.read(authStateProvider);
    if (delivery == null || authState is AuthErrorState) {
      if (authState is AuthErrorState) {
        _showMessage(authState.message);
        ref.read(authStateProvider.notifier).clearError();
      }
      return;
    }

    context.push(
      '/otp',
      extra: {
        'mobile': mobile,
        'rememberLogin': _rememberLogin,
        'delivery': delivery,
      },
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
                    if (authState is AuthErrorState && !_submitting) ...[
                      GlassCard(
                        tint: Brand.danger,
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.block_rounded,
                              color: Brand.danger,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                authState.message,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
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
                            autofillHints: const [
                              AutofillHints.telephoneNumber,
                            ],
                            inputFormatters: [
                              // Allows pasted "+91 98765-43210" style input;
                              // IndianMobile strips the country code.
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9+\-\s()]'),
                              ),
                              LengthLimitingTextInputFormatter(17),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Mobile number',
                              prefixIcon: Icon(Icons.phone_iphone_rounded),
                              prefixText: '+91 ',
                              hintText: '9876543210',
                            ),
                            validator: IndianMobile.validate,
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
