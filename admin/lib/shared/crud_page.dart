import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import 'widgets.dart';

typedef ItemSubtitle = String Function(Map<String, dynamic> item);
typedef FormBuilderCallback =
    Widget Function(
      BuildContext context,
      Map<String, TextEditingController> controllers,
    );

class CrudPage extends StatefulWidget {
  const CrudPage({
    super.key,
    required this.dio,
    required this.endpoint,
    required this.title,
    required this.subtitle,
    required this.emptyTitle,
    required this.fields,
    required this.formBuilder,
    required this.itemSubtitle,
    this.allowDeactivate = false,
    this.allowReorder = false,
  });
  final Dio dio;
  final String endpoint;
  final String title;
  final String subtitle;
  final String emptyTitle;
  final List<String> fields;
  final FormBuilderCallback formBuilder;
  final ItemSubtitle itemSubtitle;
  final bool allowDeactivate;
  final bool allowReorder;

  @override
  State<CrudPage> createState() => _CrudPageState();
}

class _CrudPageState extends State<CrudPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

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
      final response = await widget.dio.get(widget.endpoint);
      final items = itemList(response.data);
      if (widget.allowReorder) {
        items.sort(
          (a, b) => ((a['sortOrder'] ?? 0) as num).compareTo(
            (b['sortOrder'] ?? 0) as num,
          ),
        );
      }
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) setState(() => _error = apiError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([Map<String, dynamic>? existing]) async {
    final controllers = {
      for (final field in widget.fields)
        field: TextEditingController(text: existing?[field]?.toString() ?? ''),
    };
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          existing == null
              ? 'Add ${widget.title.toLowerCase().replaceAll(RegExp('s\$'), '')}'
              : 'Edit item',
        ),
        content: SizedBox(
          width: 480,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: widget.formBuilder(context, controllers),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                final data = <String, dynamic>{
                  for (final entry in controllers.entries)
                    if (entry.value.text.trim().isNotEmpty)
                      entry.key: entry.value.text.trim()
                    else if (existing != null)
                      entry.key: null,
                };
                if (existing == null) {
                  await widget.dio.post(widget.endpoint, data: data);
                } else {
                  // Category/branch PATCH replaces the whole resource.
                  for (final key in const ['sortOrder', 'isActive']) {
                    if (existing.containsKey(key)) data[key] = existing[key];
                  }
                  await widget.dio.patch(
                    '${widget.endpoint}/${existing['id']}',
                    data: data,
                  );
                }
                if (context.mounted) Navigator.pop(context, true);
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(apiError(error))));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (saved == true) _load();
  }

  Future<void> _deactivate(Map<String, dynamic> item) async {
    final yes = await confirmAction(
      context,
      title: 'Deactivate employee?',
      message: 'They will no longer be able to upload expenses.',
      confirmLabel: 'Deactivate',
    );
    if (!yes) return;
    try {
      await widget.dio.delete('${widget.endpoint}/${item['id']}');
      _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
      }
    }
  }

  Future<void> _persistOrder() async {
    try {
      for (var i = 0; i < _items.length; i++) {
        final item = _items[i];
        if (item['sortOrder'] == i + 1) continue;
        await widget.dio.patch(
          '${widget.endpoint}/${item['id']}',
          data: {
            'name': item['name'],
            'code': item['code'],
            'parentId': item['parentId'],
            'sortOrder': i + 1,
            'isActive': item['isActive'] ?? true,
          },
        );
        item['sortOrder'] = i + 1;
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
      }
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: widget.title,
          subtitle: widget.subtitle,
          action: FilledButton.icon(
            onPressed: _openForm,
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: LinearProgressIndicator(),
                )
              : _error != null
              ? ErrorPanel(message: _error!, onRetry: _load)
              : _items.isEmpty
              ? EmptyPanel(
                  icon: Icons.inventory_2_outlined,
                  title: widget.emptyTitle,
                  message: 'Use Add to create the first item.',
                )
              : widget.allowReorder
              ? ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  itemCount: _items.length,
                  onReorderItem: (oldIndex, newIndex) {
                    setState(() {
                      final item = _items.removeAt(oldIndex);
                      _items.insert(newIndex, item);
                    });
                    _persistOrder();
                  },
                  itemBuilder: (context, index) => _tile(
                    _items[index],
                    index,
                    key: ValueKey(_items[index]['id']),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => _tile(_items[index], index),
                ),
        ),
      ],
    ),
  );

  Widget _tile(Map<String, dynamic> item, int index, {Key? key}) {
    final active = item['active'] ?? item['isActive'] ?? true;
    return ListTile(
      key: key,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: widget.allowReorder
          ? ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle),
            )
          : CircleAvatar(child: Text('${index + 1}')),
      title: Text(
        (item['name'] ?? item['title'] ?? item['employeeCode'] ?? 'Item')
            .toString(),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(widget.itemSubtitle(item)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.allowDeactivate)
            StatusPill(active == true ? 'active' : 'inactive'),
          IconButton(
            onPressed: () => _openForm(item),
            icon: const Icon(Icons.edit_outlined),
          ),
          if (widget.allowDeactivate && active == true)
            IconButton(
              onPressed: () => _deactivate(item),
              icon: const Icon(Icons.person_off_outlined),
            ),
        ],
      ),
    );
  }
}

Widget requiredField(
  Map<String, TextEditingController> controllers,
  String key,
  String label, {
  TextInputType? keyboardType,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 14),
  child: TextFormField(
    controller: controllers[key],
    keyboardType: keyboardType,
    decoration: InputDecoration(labelText: label),
    validator: (value) =>
        value == null || value.trim().isEmpty ? '$label is required' : null,
  ),
);
