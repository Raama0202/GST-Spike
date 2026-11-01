import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/glass.dart';
import 'auth.dart';

/// Self-service firm sign-up: details, then the 6-digit code emailed to the
/// admin. A verified sign-up lands on the dashboard with a free trial.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  static const _minPassword = 10;
  static const _resendSeconds = 30;
  static final _gstinPattern = RegExp(
    r'^[0-9]{2}[A-Z0-9]{10}[0-9A-Z]Z[0-9A-Z]$',
  );

  final _formKey = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _gstin = TextEditingController();
  final _legalName = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();

  RegistrationOptions? _options;
  String? _sentTo;
  bool _busy = false;
  bool _obscure = true;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    ref.read(authRepositoryProvider).registrationOptions().then((options) {
      if (mounted) setState(() => _options = options);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in [
      _company,
      _gstin,
      _legalName,
      _name,
      _email,
      _mobile,
      _password,
      _confirm,
      _code,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendIn = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendIn <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendIn = 0);
        return;
      }
      setState(() => _resendIn--);
    });
  }

  void _show(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  void _signedIn(AdminSession session) {
    ref.read(authProvider.notifier).signedIn(session);
    _show('Welcome! Add your GSTINs and employees to get started.');
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(authRepositoryProvider)
          .register(
            FirmRegistration(
              companyName: _company.text,
              gstin: _gstin.text,
              legalName: _legalName.text,
              adminName: _name.text,
              adminEmail: _email.text,
              mobile: _mobile.text,
              adminPassword: _password.text,
            ),
          );
      if (!mounted) return;
      final session = result.session;
      if (session != null) {
        _signedIn(session);
        return;
      }
      setState(() => _sentTo = result.destination ?? _email.text.trim());
      _startResendTimer();
    } catch (error) {
      if (mounted) _show(apiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_code.text.trim().length != 6) {
      _show('Enter the 6-digit code from the email');
      return;
    }
    setState(() => _busy = true);
    try {
      final session = await ref
          .read(authRepositoryProvider)
          .verifyRegistration(_email.text, _code.text, _password.text);
      if (mounted) _signedIn(session);
    } catch (error) {
      if (mounted) {
        _show(apiError(error));
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _resend() async {
    setState(() => _busy = true);
    try {
      final sentTo = await ref
          .read(authRepositoryProvider)
          .resendRegistrationCode(_email.text);
      if (!mounted) return;
      setState(() => _sentTo = sentTo ?? _sentTo);
      _code.clear();
      _startResendTimer();
      _show('A new code is on its way');
    } catch (error) {
      if (mounted) _show(apiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = _options;
    return Scaffold(
      appBar: AppBar(
        title: Text(_sentTo == null ? 'Register your firm' : 'Verify email'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _busy
              ? null
              : () => _sentTo != null
                    ? setState(() => _sentTo = null)
                    : context.canPop()
                    ? context.pop()
                    : context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: GlassCard(
                blur: true,
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                child: _sentTo == null
                    ? _detailsForm(theme, options)
                    : _codeForm(theme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailsForm(ThemeData theme, RegistrationOptions? options) {
    final unavailable = options != null && !options.available;
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              options == null
                  ? 'Create your company and its administrator account.'
                  : 'Free ${options.trialDays}-day trial for up to '
                        '${options.trialSeats} employees. No card needed.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (unavailable) ...[
              const SizedBox(height: 12),
              Text(
                'Registration is temporarily unavailable. Please try again later.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            TextFormField(
              controller: _company,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Company name',
                prefixIcon: Icon(Icons.business_outlined),
              ),
              validator: (value) => (value ?? '').trim().length < 2
                  ? 'Enter your company name'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _gstin,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9A-Za-z]')),
                LengthLimitingTextInputFormatter(15),
              ],
              decoration: const InputDecoration(
                labelText: 'GSTIN (recommended)',
                helperText:
                    'Lets the scanner tell your firm apart from the supplier on bills',
                helperMaxLines: 2,
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
              validator: (value) {
                final gstin = (value ?? '').trim().toUpperCase();
                return gstin.isEmpty || _gstinPattern.hasMatch(gstin)
                    ? null
                    : 'A GSTIN has 15 characters, like 36AABCS1429B1Z5';
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _legalName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Legal name (optional)',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _name,
              autofillHints: const [AutofillHints.name],
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Your name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) =>
                  (value ?? '').trim().length < 2 ? 'Enter your name' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              autofillHints: const [AutofillHints.email],
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Work email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              validator: (value) =>
                  RegExp(
                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                  ).hasMatch((value ?? '').trim())
                  ? null
                  : 'Enter a valid email address',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _mobile,
              autofillHints: const [AutofillHints.telephoneNumber],
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile (optional)',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Password ($_minPassword+ characters)',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
              validator: (value) => (value ?? '').length < _minPassword
                  ? 'Use at least $_minPassword characters'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (value) =>
                  value != _password.text ? 'The passwords do not match' : null,
              onFieldSubmitted: (_) => _register(),
            ),
            const SizedBox(height: 24),
            GlassButton(
              label: options?.verificationRequired == false
                  ? 'Create account'
                  : 'Continue',
              icon: Icons.arrow_forward_rounded,
              loading: _busy,
              onPressed: unavailable ? null : _register,
            ),
            if (_busy) ...[
              const SizedBox(height: 10),
              Text(
                'The server may take up to a minute to wake up.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _codeForm(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: IconBadge(
            icon: Icons.mark_email_unread_rounded,
            color: Brand.primary,
            size: 68,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Check your email',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'We sent a 6-digit code to $_sentTo',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 12),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: const InputDecoration(
            hintText: '000000',
            counterText: '',
          ),
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: 20),
        GlassButton(
          label: 'Verify and create account',
          icon: Icons.verified_rounded,
          loading: _busy,
          onPressed: _verify,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _resendIn > 0 || _busy ? null : _resend,
          child: Text(
            _resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'No email? Check your spam folder.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
