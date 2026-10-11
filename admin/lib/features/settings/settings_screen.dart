import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../shared/widgets.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _name = TextEditingController();
  final _color = TextEditingController(text: '0B5FFF');
  bool _duplicateCheck = true;
  bool _gpsRequired = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await ref.read(dioProvider).get(ApiPaths.settings);
      final data = Map<String, dynamic>.from(response.data as Map);
      _name.text = (data['name'] ?? '').toString();
      _color.text = (data['primary_color_hex'] ?? '0B5FFF')
          .toString()
          .replaceAll('#', '');
      _duplicateCheck = data['duplicate_check_enabled'] ?? true;
      _gpsRequired = data['requires_gps'] ?? false;
    } catch (error) {
      _error = apiError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(dioProvider)
          .patch(
            ApiPaths.settings,
            data: {
              'name': _name.text.trim(),
              'primaryColorHex': _color.text
                  .trim()
                  .replaceAll('#', '')
                  .toUpperCase(),
              'duplicateCheckEnabled': _duplicateCheck,
              'requiresGps': _gpsRequired,
            },
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Settings saved.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _color.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          title: 'Company settings',
          subtitle: 'Configure company identity and employee upload controls.',
        ),
        const SizedBox(height: 24),
        if (_loading)
          const LinearProgressIndicator()
        else if (_error != null)
          ErrorPanel(message: _error!, onRetry: _load)
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Company identity',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _color,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Theme color',
                        prefixText: '#',
                        helperText:
                            'Six-digit hexadecimal color used in the employee app.',
                      ),
                    ),
                    const Divider(height: 40),
                    Text(
                      'Expense controls',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Duplicate invoice check'),
                      subtitle: const Text(
                        'Warn employees when an invoice may already exist.',
                      ),
                      value: _duplicateCheck,
                      onChanged: (value) =>
                          setState(() => _duplicateCheck = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('GPS required'),
                      subtitle: const Text(
                        'Require a location when an invoice is submitted.',
                      ),
                      value: _gpsRequired,
                      onChanged: (value) =>
                          setState(() => _gpsRequired = value),
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_saving ? 'Saving…' : 'Save changes'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
