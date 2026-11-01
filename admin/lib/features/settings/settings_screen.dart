import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/validators.dart';
import '../../shared/widgets.dart';

List<String> _splitList(String raw, {bool upper = false}) {
  final seen = <String>{};
  final items = <String>[];
  for (final part in raw.split(RegExp(r'[\n,]'))) {
    final value = upper ? part.trim().toUpperCase() : part.trim();
    if (value.isNotEmpty && seen.add(value.toLowerCase())) items.add(value);
  }
  return items;
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _color = TextEditingController(text: '0B5FFF');
  final _legalName = TextEditingController();
  final _gstin = TextEditingController();
  final _additionalGstins = TextEditingController();
  final _aliases = TextEditingController();
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ref.read(dioProvider).get(ApiPaths.settings);
      final data = Map<String, dynamic>.from(response.data as Map);
      _name.text = (data['name'] ?? '').toString();
      _color.text = (data['primary_color_hex'] ?? '0B5FFF')
          .toString()
          .replaceAll('#', '');
      _legalName.text = (data['legal_name'] ?? '').toString();
      _gstin.text = (data['gstin'] ?? '').toString();
      _additionalGstins.text =
          ((data['additional_gstins'] as List?) ?? const []).join('\n');
      _aliases.text = ((data['name_aliases'] as List?) ?? const []).join('\n');
      _duplicateCheck = data['duplicate_check_enabled'] ?? true;
      _gpsRequired = data['requires_gps'] ?? false;
    } catch (error) {
      _error = apiError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final gstin = _gstin.text.replaceAll(RegExp(r'\s'), '').toUpperCase();
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
              'legalName': _legalName.text.trim().isEmpty
                  ? null
                  : _legalName.text.trim(),
              'gstin': gstin.isEmpty ? null : gstin,
              'additionalGstins': _splitList(
                _additionalGstins.text,
                upper: true,
              ).where((g) => g != gstin).toList(),
              'nameAliases': _splitList(_aliases.text),
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
    for (final c in [
      _name,
      _color,
      _legalName,
      _gstin,
      _additionalGstins,
      _aliases,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleLarge;
    return ContentPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            title: 'Company settings',
            subtitle:
                'Configure company identity and employee upload controls.',
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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Branding', style: titleStyle),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Display name is required'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _color,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: 'Theme color',
                            prefixText: '#',
                            helperText:
                                'Six-digit hexadecimal color used in the employee app.',
                          ),
                          validator: (v) =>
                              RegExp(
                                r'^[0-9a-fA-F]{6}$',
                              ).hasMatch((v ?? '').trim().replaceAll('#', ''))
                              ? null
                              : 'Use six hex digits, e.g. 0B5FFF',
                        ),
                        const Divider(height: 40),
                        Text('Company identity', style: titleStyle),
                        const SizedBox(height: 6),
                        Text(
                          'Bills usually show two companies: the seller and you. '
                          'These details let the apps pick the seller automatically.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _gstin,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(labelText: 'GSTIN'),
                          validator: gstinError,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _legalName,
                          decoration: const InputDecoration(
                            labelText: 'Legal name (as on GST certificate)',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _additionalGstins,
                          minLines: 2,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Other GSTINs (one per line)',
                            helperText: 'Registrations in other states.',
                          ),
                          validator: (v) {
                            for (final g in _splitList(v ?? '', upper: true)) {
                              final error = gstinError(g);
                              if (error != null) return '$g: $error';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _aliases,
                          minLines: 2,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Other names (one per line)',
                            helperText:
                                'Trade names or short names printed on bills addressed to you.',
                          ),
                        ),
                        const Divider(height: 40),
                        Text('Expense controls', style: titleStyle),
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
            ),
        ],
      ),
    );
  }
}
