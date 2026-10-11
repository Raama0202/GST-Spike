import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../shared/crud_page.dart';

class BranchesScreen extends ConsumerWidget {
  const BranchesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => CrudPage(
    dio: ref.watch(dioProvider),
    endpoint: ApiPaths.branches,
    title: 'Branches',
    subtitle: 'Manage offices, sites and other expense locations.',
    emptyTitle: 'No branches yet',
    fields: const ['name', 'code'],
    itemSubtitle: (item) => 'Code: ${item['code'] ?? '—'}',
    formBuilder: (_, c) => Column(
      children: [
        requiredField(c, 'name', 'Branch name'),
        requiredField(c, 'code', 'Branch code'),
      ],
    ),
  );
}
