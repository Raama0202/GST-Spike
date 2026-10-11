import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../shared/crud_page.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => CrudPage(
    dio: ref.watch(dioProvider),
    endpoint: ApiPaths.categories,
    title: 'Categories',
    subtitle: 'Define expense categories and drag them into display order.',
    emptyTitle: 'No categories yet',
    fields: const ['name', 'parentId'],
    allowReorder: true,
    itemSubtitle: (item) => item['parentId'] == null
        ? 'Top-level category'
        : 'Under ${item['parentId']}',
    formBuilder: (_, c) => Column(
      children: [
        requiredField(c, 'name', 'Category name'),
        TextFormField(
          controller: c['parentId'],
          decoration: const InputDecoration(
            labelText: 'Parent category ID (optional)',
          ),
        ),
      ],
    ),
  );
}
