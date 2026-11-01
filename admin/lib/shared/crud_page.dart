import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/glass.dart';
import '../core/validators.dart';
import 'widgets.dart';

typedef ItemSubtitle =
    String Function(
      Map<String, dynamic> item,
      List<Map<String, dynamic>> items,
    );
typedef FormBuilderCallback =
    Widget Function(
      BuildContext context,
      Map<String, TextEditingController> controllers,
      CrudFormScope scope,
    );

/// What a form needs beyond its controllers: the row being edited (null when
/// adding) and the loaded rows, e.g. to offer a parent picker.
class CrudFormScope {
  const CrudFormScope({required this.existing, required this.items});
  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> items;
}

class CrudPage extends StatefulWidget {
  const CrudPage({
    super.key,
    required this.dio,
    required this.endpoint,
    required this.title,
    required this.subtitle,
    required this.entityName,
    required this.emptyTitle,
    required this.fields,
    required this.formBuilder,
    required this.itemSubtitle,
    this.allowDeactivate = false,
    this.deactivateMessage = 'It will no longer be available.',
    this.reactivateBody,
    this.allowReorder = false,
    this.pageSize,
    this.searchHint,
    this.activeFilter = false,
    this.prepareData,
    this.summary,
    this.icon = Icons.inventory_2_outlined,
  });
  final Dio dio;
  final String endpoint;
  final String title;
  final String subtitle;

  /// Singular, lower case: "employee" gives "Add employee", "Edit employee".
  final String entityName;
  final String emptyTitle;
  final List<String> fields;
  final FormBuilderCallback formBuilder;
  final ItemSubtitle itemSubtitle;
  final bool allowDeactivate;
  final String deactivateMessage;

  /// PATCH body that reactivates a row; defaults to `{isActive: true}`.
  final Map<String, dynamic> Function(Map<String, dynamic> item)?
  reactivateBody;
  final bool allowReorder;

  /// Server-side paging (`page`, `pageSize`, `q`, `active`); null loads all.
  final int? pageSize;

  /// Shows a search box (sent as `q`) when set.
  final String? searchHint;
  final bool activeFilter;

  /// Last chance to normalise form values before they are sent.
  final Map<String, dynamic> Function(Map<String, dynamic> data)? prepareData;

  /// Optional line under the header built from the list response.
  final String? Function(dynamic responseData)? summary;
  final IconData icon;

  @override
  State<CrudPage> createState() => _CrudPageState();
}

class _CrudPageState extends State<CrudPage> {
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _moreError;
  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  int _page = 1;
  int _generation = 0;
  String _query = '';
  bool? _active;
  String? _summary;
  Timer? _debounce;

  bool get _hasMore => widget.pageSize != null && _items.length < _total;

  String get _entity => widget.entityName;
  String get _entityTitle => _entity[0].toUpperCase() + _entity.substring(1);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_loading || _loadingMore || !_hasMore || _moreError != null)) {
      return;
    }
    final generation = more ? _generation : ++_generation;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
        _moreError = null;
      }
    });
    final page = more ? _page + 1 : 1;
    try {
      final pageSize = widget.pageSize;
      final response = await widget.dio.get(
        widget.endpoint,
        queryParameters: pageSize == null
            ? null
            : {
                'page': page,
                'pageSize': pageSize,
                if (_query.trim().isNotEmpty) 'q': _query.trim(),
                'active': ?_active,
              },
      );
      if (!mounted || generation != _generation) return;
      final items = itemList(response.data);
      if (widget.allowReorder) {
        items.sort(
          (a, b) => ((a['sortOrder'] ?? 0) as num).compareTo(
            (b['sortOrder'] ?? 0) as num,
          ),
        );
      }
      setState(() {
        if (more) {
          final seen = {for (final i in _items) i['id']};
          _items = [..._items, ...items.where((i) => !seen.contains(i['id']))];
        } else {
          _items = items;
        }
        _total = pageSize == null ? _items.length : itemTotal(response.data);
        _page = page;
        _summary = widget.summary?.call(response.data);
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        if (more) {
          _moreError = apiError(error);
        } else {
          _error = apiError(error);
        }
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _query = value;
      _load();
    });
  }

  Future<void> _openForm([Map<String, dynamic>? existing]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CrudFormDialog(
        title: existing == null ? 'Add $_entity' : 'Edit $_entity',
        fields: widget.fields,
        existing: existing,
        items: _items,
        formBuilder: widget.formBuilder,
        onSave: (data) async {
          final body = widget.prepareData?.call(data) ?? data;
          if (existing == null) {
            await widget.dio.post(widget.endpoint, data: body);
          } else {
            // Category/branch PATCH replaces the whole resource.
            for (final key in const ['sortOrder', 'isActive']) {
              if (existing.containsKey(key) && !body.containsKey(key)) {
                body[key] = existing[key];
              }
            }
            await widget.dio.patch(
              '${widget.endpoint}/${existing['id']}',
              data: body,
            );
          }
        },
      ),
    );
    if (saved == true) {
      if (mounted) {
        showSnack(
          context,
          existing == null ? '$_entityTitle added.' : 'Saved.',
        );
      }
      _load();
    }
  }

  Future<void> _deactivate(Map<String, dynamic> item) async {
    final yes = await confirmAction(
      context,
      title: 'Deactivate $_entity?',
      message: widget.deactivateMessage,
      confirmLabel: 'Deactivate',
      destructive: true,
    );
    if (!yes) return;
    try {
      await widget.dio.delete('${widget.endpoint}/${item['id']}');
      if (mounted) showSnack(context, '$_entityTitle deactivated.');
      _load();
    } catch (error) {
      if (mounted) showSnack(context, apiError(error));
    }
  }

  Future<void> _reactivate(Map<String, dynamic> item) async {
    try {
      await widget.dio.patch(
        '${widget.endpoint}/${item['id']}',
        data: widget.reactivateBody?.call(item) ?? {'isActive': true},
      );
      if (mounted) showSnack(context, '$_entityTitle reactivated.');
      _load();
    } catch (error) {
      if (mounted) showSnack(context, apiError(error));
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
      if (mounted) showSnack(context, apiError(error));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SliverPage(
      onRefresh: _load,
      onEndReached: () => _load(more: true),
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: widget.title,
            subtitle: widget.subtitle,
            action: FilledButton.icon(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ),
        ),
        if (_summary != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GlassPill(
                  label: _summary!,
                  color: Brand.primary,
                  icon: Icons.event_seat_outlined,
                ),
              ),
            ),
          ),
        if (widget.searchHint != null || widget.activeFilter)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (widget.searchHint != null)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: TextField(
                        onChanged: _onSearch,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: widget.searchHint,
                          prefixIcon: const Icon(Icons.search),
                        ),
                      ),
                    ),
                  if (widget.activeFilter)
                    SegmentedButton<bool?>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: null, label: Text('All')),
                        ButtonSegment(value: true, label: Text('Active')),
                        ButtonSegment(value: false, label: Text('Inactive')),
                      ],
                      selected: {_active},
                      onSelectionChanged: (value) {
                        _active = value.first;
                        _load();
                      },
                    ),
                ],
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
        if (_loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(),
            ),
          ),
        if (_error != null && _items.isEmpty)
          SliverToBoxAdapter(
            child: Card(
              child: ErrorPanel(message: _error!, onRetry: _load),
            ),
          )
        else if (!_loading && _items.isEmpty)
          SliverToBoxAdapter(
            child: Card(
              child: EmptyPanel(
                icon: widget.icon,
                title: _query.isNotEmpty || _active != null
                    ? 'Nothing matches'
                    : widget.emptyTitle,
                message: _query.isNotEmpty || _active != null
                    ? 'Try a different search or filter.'
                    : 'Use Add to create the first $_entity.',
              ),
            ),
          )
        else if (_items.isNotEmpty) ...[
          if (widget.allowReorder)
            SliverCard(
              sliver: SliverReorderableList(
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
              ),
            )
          else
            SliverCard(
              sliver: SliverList.separated(
                itemCount: _items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) => _tile(_items[index], index),
              ),
            ),
          SliverToBoxAdapter(
            child: LoadMoreFooter(
              loading: _loadingMore,
              error: _moreError,
              onRetry: () {
                setState(() => _moreError = null);
                _load(more: true);
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _tile(Map<String, dynamic> item, int index, {Key? key}) {
    final active = (item['active'] ?? item['isActive'] ?? true) == true;
    final name = (item['name'] ?? item['title'] ?? item['employeeCode'] ?? '')
        .toString();
    return Material(
      key: key,
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        leading: widget.allowReorder
            ? ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle),
              )
            : CircleAvatar(child: Text(initialOf(name, fallback: '#'))),
        title: Text(
          name.isEmpty ? 'Unnamed' : name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: active
                ? null
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        subtitle: Text(widget.itemSubtitle(item, _items)),
        onTap: () => _openForm(item),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.allowDeactivate || !active)
              StatusPill(active ? 'active' : 'inactive'),
            PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: (action) => switch (action) {
                'edit' => _openForm(item),
                'deactivate' => _deactivate(item),
                _ => _reactivate(item),
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text('Edit $_entity')),
                if (widget.allowDeactivate && active)
                  PopupMenuItem(
                    value: 'deactivate',
                    child: Text('Deactivate $_entity'),
                  ),
                if (widget.allowDeactivate && !active)
                  PopupMenuItem(
                    value: 'reactivate',
                    child: Text('Reactivate $_entity'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CrudFormDialog extends StatefulWidget {
  const _CrudFormDialog({
    required this.title,
    required this.fields,
    required this.existing,
    required this.items,
    required this.formBuilder,
    required this.onSave,
  });
  final String title;
  final List<String> fields;
  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> items;
  final FormBuilderCallback formBuilder;
  final Future<void> Function(Map<String, dynamic> data) onSave;

  @override
  State<_CrudFormDialog> createState() => _CrudFormDialogState();
}

class _CrudFormDialogState extends State<_CrudFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers = {
    for (final field in widget.fields)
      field: TextEditingController(
        text: widget.existing?[field]?.toString() ?? '',
      ),
  };
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.existing;
    final data = <String, dynamic>{
      for (final entry in _controllers.entries)
        if (entry.value.text.trim().isNotEmpty)
          entry.key: entry.value.text.trim()
        else if (existing != null)
          entry.key: null,
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(data);
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
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              widget.formBuilder(
                context,
                _controllers,
                CrudFormScope(existing: widget.existing, items: widget.items),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
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
        child: Text(_saving ? 'Saving…' : 'Save'),
      ),
    ],
  );
}

Widget requiredField(
  Map<String, TextEditingController> controllers,
  String key,
  String label, {
  TextInputType? keyboardType,
  String? Function(String? value)? validator,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 14),
  child: TextFormField(
    controller: controllers[key],
    keyboardType: keyboardType,
    decoration: InputDecoration(labelText: label),
    validator:
        validator ??
        (value) =>
            value == null || value.trim().isEmpty ? '$label is required' : null,
  ),
);
