import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gst_expense_scanner/core/config/server_config.dart';
import 'package:gst_expense_scanner/core/di/providers.dart';
import 'package:gst_expense_scanner/core/network/api_client.dart';

/// Lets a demo or on-premise device point the app at a different API server.
///
/// Only reachable when the build was compiled with `ALLOW_SERVER_OVERRIDE=true`.
class ServerEndpointDialog extends ConsumerStatefulWidget {
  const ServerEndpointDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const ServerEndpointDialog(),
    );
  }

  @override
  ConsumerState<ServerEndpointDialog> createState() =>
      _ServerEndpointDialogState();
}

class _ServerEndpointDialogState extends ConsumerState<ServerEndpointDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: ServerConfig.baseUrl);
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final normalized = ServerConfig.normalize(_controller.text);
    if (normalized == null) {
      setState(() => _error = 'Enter a valid http(s) address');
      return;
    }

    setState(() {
      _error = null;
      _checking = true;
    });

    final reachable =
        await ConnectivityService(baseUrl: normalized).hasConnection;

    final storage = ref.read(secureStorageProvider);
    final saved = await ServerConfig.save(storage, normalized);
    if (saved != null) _repointClients(saved);

    if (!mounted) return;
    setState(() => _checking = false);
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          reachable
              ? 'Server set to ${ServerConfig.displayHost}'
              : 'Saved ${ServerConfig.displayHost}, but it did not respond. '
                  'Check the server is running.',
        ),
      ),
    );
  }

  Future<void> _reset() async {
    await ServerConfig.reset(ref.read(secureStorageProvider));
    _repointClients(ServerConfig.baseUrl);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Restored ${ServerConfig.displayHost}')),
    );
  }

  void _repointClients(String baseUrl) {
    ref.read(apiClientProvider).updateBaseUrl(baseUrl);
    ref.read(authApiClientProvider).updateBaseUrl(baseUrl);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Server address'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'API base URL',
              hintText: 'https://example.trycloudflare.com/v1',
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          Text(
            'Built-in default: ${ServerConfig.compiledBaseUrl}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        if (ServerConfig.isOverridden)
          TextButton(
            onPressed: _checking ? null : _reset,
            child: const Text('Use default'),
          ),
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _checking ? null : _save,
          child: _checking
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
