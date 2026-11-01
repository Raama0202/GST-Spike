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
    entityName: 'branch',
    emptyTitle: 'No branches yet',
    icon: Icons.location_on_outlined,
    fields: const ['name', 'code'],
    allowDeactivate: true,
    deactivateMessage:
        'It will no longer be offered when assigning employees. Existing '
        'invoices keep their branch.',
    reactivateBody: (item) => {
      'name': item['name'],
      'code': item['code'],
      'isActive': true,
    },
    itemSubtitle: (item, _) => 'Code: ${item['code'] ?? '—'}',
    formBuilder: (_, c, _) => Column(
      children: [
        requiredField(c, 'name', 'Branch name'),
        requiredField(c, 'code', 'Branch code'),
      ],
    ),
  );
}
