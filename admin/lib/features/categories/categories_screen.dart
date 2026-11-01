import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../shared/crud_page.dart';
import 'category_tree.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => CrudPage(
    dio: ref.watch(dioProvider),
    endpoint: ApiPaths.categories,
    title: 'Categories',
    subtitle: 'Define expense categories and drag them into display order.',
    entityName: 'category',
    emptyTitle: 'No categories yet',
    icon: Icons.category_outlined,
    fields: const ['name', 'parentId'],
    allowReorder: true,
    allowDeactivate: true,
    deactivateMessage:
        'Employees will no longer be able to pick it. Existing invoices '
        'keep their category.',
    reactivateBody: (item) => {
      'name': item['name'],
      'parentId': item['parentId'],
      'sortOrder': item['sortOrder'] ?? 0,
      'isActive': true,
    },
    itemSubtitle: (item, items) {
      final parentId = item['parentId'];
      if (parentId == null) return 'Top-level category';
      final parent = items.where((c) => c['id'] == parentId).firstOrNull;
      return 'Under ${parent?['name'] ?? 'another category'}';
    },
    formBuilder: (_, c, scope) => Column(
      children: [
        requiredField(c, 'name', 'Category name'),
        _ParentPicker(controller: c['parentId']!, scope: scope),
      ],
    ),
  );
}

class _ParentPicker extends StatelessWidget {
  const _ParentPicker({required this.controller, required this.scope});
  final TextEditingController controller;
  final CrudFormScope scope;

  @override
  Widget build(BuildContext context) {
    final current = controller.text.isEmpty ? null : controller.text;
    final options = parentCandidates(
      scope.items,
      selfId: scope.existing?['id']?.toString(),
      currentParentId: current,
    );
    final known = options.any((c) => c['id'] == current);
    return DropdownButtonFormField<String>(
      initialValue: known ? current : '',
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Parent category'),
      items: [
        const DropdownMenuItem(value: '', child: Text('None (top level)')),
        for (final c in options)
          DropdownMenuItem(
            value: c['id'].toString(),
            child: Text(
              c['name']?.toString() ?? '—',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) => controller.text = value ?? '',
    );
  }
}
