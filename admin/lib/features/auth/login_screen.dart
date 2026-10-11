import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/glass.dart';
import '../../core/server_config.dart';
import 'auth.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authProvider.notifier).login(_email.text, _password.text);
    if (!mounted) return;
    ref
        .read(authProvider)
        .whenOrNull(
          error: (error, _) => ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(apiError(error)))),
        );
  }

  Future<void> _editServer() async {
    if (!ServerConfig.canOverride) return;
    final controller = TextEditingController(text: ServerConfig.baseUrl);
    final saved = await showDialog<String>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Server address'),
              content: TextField(
                controller: controller,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'API base URL',
                  hintText: 'https://gst-expense-scanner.onrender.com/v1',
                  errorText: error,
                ),
              ),
              actions: [
                if (ServerConfig.isOverridden)
                  TextButton(
                    onPressed: () async {
                      await ServerConfig.reset(ref.read(secureStoreProvider));
                      updateAdminBaseUrl(ref, ServerConfig.baseUrl);
                      if (context.mounted) {
                        Navigator.pop(context, ServerConfig.baseUrl);
                      }
                    },
                    child: const Text('Use default'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final normalized = ServerConfig.normalize(controller.text);
                    if (normalized == null) {
                      setLocal(() => error = 'Enter a valid http(s) address');
                      return;
                    }
                    await ServerConfig.save(
                      ref.read(secureStoreProvider),
                      normalized,
                    );
                    updateAdminBaseUrl(ref, normalized);
                    if (context.mounted) Navigator.pop(context, normalized);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (saved != null && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: GlassCard(
                blur: true,
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(
                          child: IconBadge(
                            icon: Icons.admin_panel_settings_rounded,
                            color: Brand.primary,
                            size: 72,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          AppConstants.appName,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in to manage your expense operations.',
                          textAlign: TextAlign.center,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyLarge?.copyWith(color: Brand.muted),
                        ),
                        const SizedBox(height: 28),
                        TextFormField(
                          controller: _email,
                          autofillHints: const [AutofillHints.email],
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Work email',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (value) =>
                              value == null || !value.contains('@')
                              ? 'Enter a valid email address'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                            ),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Enter your password'
                              : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 24),
                        GlassButton(
                          label: 'Sign in',
                          icon: Icons.login_rounded,
                          loading: auth.isLoading,
                          onPressed: _submit,
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: ServerConfig.canOverride
                              ? _editServer
                              : null,
                          child: Text(
                            ServerConfig.canOverride
                                ? 'Server: ${ServerConfig.displayHost}'
                                : 'API: ${ServerConfig.displayHost}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
