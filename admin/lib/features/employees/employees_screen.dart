import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../shared/crud_page.dart';

class EmployeesScreen extends ConsumerWidget {
  const EmployeesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => CrudPage(
    dio: ref.watch(dioProvider),
    endpoint: ApiPaths.employees,
    title: 'Employees',
    subtitle: 'Provision staff accounts and control upload access.',
    emptyTitle: 'No employees yet',
    fields: const ['name', 'mobile', 'branchId', 'employeeCode'],
    allowDeactivate: true,
    itemSubtitle: (item) =>
        '${item['employeeCode'] ?? 'No code'} • ${item['mobile'] ?? 'No mobile'} • ${item['branchName'] ?? item['branchId'] ?? 'No branch'}',
    formBuilder: (_, c) => Column(
      children: [
        requiredField(c, 'name', 'Full name'),
        requiredField(
          c,
          'mobile',
          'Mobile number',
          keyboardType: TextInputType.phone,
        ),
        requiredField(c, 'employeeCode', 'Employee code'),
        TextFormField(
          controller: c['branchId'],
          decoration: const InputDecoration(
            labelText: 'Branch ID (optional)',
          ),
        ),
      ],
    ),
  );
}
