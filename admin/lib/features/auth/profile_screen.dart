import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/glass.dart';
import '../../core/validators.dart';
import '../../shared/widgets.dart';
import 'auth.dart';

final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) showSnack(context, 'Open $url in a browser.');
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await confirmAction(
      context,
      title: 'Sign out?',
      message: 'You will need your email and password to sign in again.',
      confirmLabel: 'Sign out',
    );
    if (ok) await ref.read(authProvider.notifier).logout();
  }

  Future<void> _changePassword(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (changed == true && context.mounted) {
      showSnack(
        context,
        'Password changed. Other devices have been signed out.',
      );
    }
  }

  Future<void> _deleteCompany(BuildContext context, WidgetRef ref) async {
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeleteCompanyDialog(),
    );
    if (deleted == true && context.mounted) {
      showSnack(context, 'Your company and all its data have been deleted.');
      ref.read(authProvider.notifier).signedOutLocally();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider).value;
    final version = ref.watch(appVersionProvider);
    final theme = Theme.of(context);
    return ContentPage(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHeader(
              title: 'Profile',
              subtitle: 'Your administrator account and app information.',
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 30,
                      child: Text(initialOf(session?.name ?? session?.email)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      (session?.name?.trim().isNotEmpty ?? false)
                          ? session!.name!
                          : 'Administrator',
                      style: theme.textTheme.titleLarge,
                    ),
                    if (session?.email != null) Text(session!.email!),
                    const SizedBox(height: 6),
                    const StatusPill('Company Admin'),
                    if (session?.companyId != null) ...[
                      const SizedBox(height: 16),
                      SelectableText(
                        'Company ID: ${session!.companyId}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock_reset_rounded),
                    title: const Text('Change password'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _changePassword(context),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.open_in_browser_rounded),
                    title: const Text('Web console'),
                    subtitle: const Text('Billing, renewals and reports'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _open(context, AppConstants.consoleUrl),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('Privacy policy'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _open(context, AppConstants.privacyUrl),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Terms of service'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _open(context, AppConstants.termsUrl),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('App version'),
                    trailing: Text(version.value ?? '…'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _signOut(context, ref),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
            const SizedBox(height: 32),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(GlassMetrics.radius),
                side: BorderSide(color: Brand.danger.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Danger zone',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Brand.danger,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Permanently delete your company account, including all '
                      'employees, invoices, images and settings. This cannot '
                      'be undone.',
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Brand.danger,
                        side: const BorderSide(color: Brand.danger),
                      ),
                      onPressed: () => _deleteCompany(context, ref),
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('Delete company account'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();
  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_current, _next, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .changePassword(_current.text, _next.text);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = apiError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Change password'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _current,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Current password',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
                validator: (v) =>
                    (v ?? '').isEmpty ? 'Enter your current password' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _next,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText:
                      'New password (${AppConstants.minPasswordLength}+ characters)',
                ),
                validator: (v) =>
                    newPasswordError(v) ??
                    (v == _current.text ? 'Choose a different password' : null),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirm,
                obscureText: _obscure,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                ),
                validator: (v) =>
                    v != _next.text ? 'The passwords do not match' : null,
                onFieldSubmitted: (_) => _save(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Change password'),
      ),
    ],
  );
}

class _DeleteCompanyDialog extends ConsumerStatefulWidget {
  const _DeleteCompanyDialog();
  @override
  ConsumerState<_DeleteCompanyDialog> createState() =>
      _DeleteCompanyDialogState();
}

class _DeleteCompanyDialogState extends ConsumerState<_DeleteCompanyDialog> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  String? _companyName;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _password.addListener(() => setState(() {}));
    ref
        .read(dioProvider)
        .get(ApiPaths.settings)
        .then((response) {
          final name = (response.data as Map?)?['name']?.toString();
          if (mounted && name != null && name.isNotEmpty) {
            setState(() => _companyName = name);
          }
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _ready {
    final typed = _name.text.trim().toLowerCase();
    final nameOk = _companyName == null
        ? typed.isNotEmpty
        : typed == _companyName!.trim().toLowerCase();
    return nameOk && _password.text.isNotEmpty && !_deleting;
  }

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .deleteCompany(password: _password.text, confirmName: _name.text);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _deleting = false;
          _error = apiError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Delete company account?'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This permanently deletes the company, every admin and employee '
              'account, all invoices and images, and all settings. Employees '
              'are signed out immediately. This cannot be undone.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: _companyName == null
                    ? 'Type the company name'
                    : 'Type "$_companyName" to confirm',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Your password'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _deleting ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: Brand.danger),
        onPressed: _ready ? _delete : null,
        child: Text(_deleting ? 'Deleting…' : 'Delete forever'),
      ),
    ],
  );
}
