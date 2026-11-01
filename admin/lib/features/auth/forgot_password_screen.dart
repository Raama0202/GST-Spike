import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/glass.dart';
import '../../core/validators.dart';
import '../../shared/widgets.dart';
import 'auth.dart';

/// Email a 6-digit code, then set a new password with it.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});
  final String? initialEmail;
  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailForm = GlobalKey<FormState>();
  final _resetForm = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _sentTo;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    for (final c in [_email, _code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _sendCode() async {
    // The email form isn't mounted when resending from the code step.
    if (_emailForm.currentState?.validate() == false) return;
    setState(() => _busy = true);
    try {
      final sentTo = await ref
          .read(authRepositoryProvider)
          .forgotPassword(_email.text);
      if (mounted) setState(() => _sentTo = sentTo ?? _email.text.trim());
    } catch (error) {
      if (mounted) showSnack(context, apiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (!_resetForm.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .resetPassword(_email.text, _code.text, _password.text);
      if (!mounted) return;
      showSnack(context, 'Password updated. Sign in with your new password.');
      context.canPop() ? context.pop() : context.go('/login');
    } catch (error) {
      if (mounted) {
        showSnack(context, apiError(error));
        setState(() => _busy = false);
      }
    }
  }

  void _back() {
    if (_sentTo != null) {
      setState(() => _sentTo = null);
    } else {
      context.canPop() ? context.pop() : context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: _sentTo == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _sentTo = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reset password'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _busy ? null : _back,
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: GlassCard(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  child: _sentTo == null
                      ? _emailStep(theme)
                      : _resetStep(theme),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emailStep(ThemeData theme) => Form(
    key: _emailForm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter your work email. We will send a 6-digit code to reset '
          'your password.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _email,
          autofillHints: const [AutofillHints.email],
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Work email',
            prefixIcon: Icon(Icons.mail_outline),
          ),
          validator: (v) =>
              isValidEmail(v ?? '') ? null : 'Enter a valid email address',
          onFieldSubmitted: (_) => _sendCode(),
        ),
        const SizedBox(height: 24),
        GlassButton(
          label: 'Send code',
          icon: Icons.send_rounded,
          loading: _busy,
          onPressed: _sendCode,
        ),
      ],
    ),
  );

  Widget _resetStep(ThemeData theme) => AutofillGroup(
    child: Form(
      key: _resetForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'If an admin account exists for this email, a code is on its '
            'way to $_sentTo. Check your spam folder too.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _code,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(
              labelText: '6-digit code',
              prefixIcon: Icon(Icons.pin_outlined),
            ),
            validator: (v) =>
                (v ?? '').length == 6 ? null : 'Enter the 6-digit code',
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText:
                  'New password (${AppConstants.minPasswordLength}+ characters)',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              ),
            ),
            validator: newPasswordError,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirm,
            obscureText: _obscure,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            validator: (v) =>
                v != _password.text ? 'The passwords do not match' : null,
            onFieldSubmitted: (_) => _reset(),
          ),
          const SizedBox(height: 24),
          GlassButton(
            label: 'Set new password',
            icon: Icons.check_rounded,
            loading: _busy,
            onPressed: _reset,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _sendCode,
            child: const Text('Send a new code'),
          ),
        ],
      ),
    ),
  );
}
