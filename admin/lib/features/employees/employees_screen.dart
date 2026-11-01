import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/format.dart';
import '../../core/validators.dart';
import '../../shared/crud_page.dart';

/// "12 of 15 seats used" from the list response's `seats` block.
String? seatsSummary(dynamic data) {
  final seats = data is Map && data['seats'] is Map
      ? data['seats'] as Map
      : null;
  if (seats == null) return null;
  final used = asNum(seats['used'])?.toInt() ?? 0;
  final limit = asNum(seats['limit'])?.toInt();
  return limit == null
      ? '$used active employees'
      : '$used of $limit seats used';
}

class EmployeesScreen extends ConsumerWidget {
  const EmployeesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dio = ref.watch(dioProvider);
    return CrudPage(
      dio: dio,
      endpoint: ApiPaths.employees,
      title: 'Employees',
      subtitle: 'Provision staff accounts and control upload access.',
      entityName: 'employee',
      emptyTitle: 'No employees yet',
      icon: Icons.people_outline,
      fields: const ['name', 'mobile', 'email', 'branchId', 'employeeCode'],
      allowDeactivate: true,
      deactivateMessage:
          'They will be signed out and can no longer upload expenses. '
          'Their past invoices stay. You can reactivate them later.',
      pageSize: 50,
      searchHint: 'Search name, mobile, code or email',
      activeFilter: true,
      summary: seatsSummary,
      prepareData: (data) => {
        ...data,
        if (data['mobile'] != null)
          'mobile': normalizeMobile(data['mobile'] as String),
        if (data['email'] != null)
          'email': (data['email'] as String).toLowerCase(),
      },
      itemSubtitle: (item, _) => [
        item['employeeCode'] ?? 'No code',
        item['mobile'] ?? 'No mobile',
        item['email'] ?? 'No email: add one for login codes',
        item['branchName'] ?? 'No branch',
      ].join(' • '),
      formBuilder: (_, c, _) => Column(
        children: [
          requiredField(c, 'name', 'Full name'),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextFormField(
              controller: c['mobile'],
              keyboardType: TextInputType.phone,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                prefixText: '+91 ',
                helperText: 'Employees sign in with this number.',
              ),
              validator: mobileError,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextFormField(
              controller: c['email'],
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Email (recommended)',
                helperText: 'Login codes are emailed here for free.',
              ),
              validator: (value) {
                final email = (value ?? '').trim();
                return email.isEmpty || isValidEmail(email)
                    ? null
                    : 'Enter a valid email address';
              },
            ),
          ),
          requiredField(c, 'employeeCode', 'Employee code'),
          _BranchPicker(dio: dio, controller: c['branchId']!),
        ],
      ),
    );
  }
}

class _BranchPicker extends StatefulWidget {
  const _BranchPicker({required this.dio, required this.controller});
  final Dio dio;
  final TextEditingController controller;

  @override
  State<_BranchPicker> createState() => _BranchPickerState();
}

class _BranchPickerState extends State<_BranchPicker> {
  late final Future<List<Map<String, dynamic>>> _branches = widget.dio
      .get(ApiPaths.branches)
      .then((r) => itemList(r.data));

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _branches,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }
          if (snapshot.hasError) {
            return Text(
              'Branches could not be loaded: ${apiError(snapshot.error!)}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            );
          }
          final current = widget.controller.text;
          final branches = [
            for (final b in snapshot.data ?? const <Map<String, dynamic>>[])
              if (b['isActive'] != false || b['id'] == current) b,
          ];
          final known = branches.any((b) => b['id'] == current);
          return DropdownButtonFormField<String>(
            initialValue: known ? current : '',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Branch'),
            items: [
              const DropdownMenuItem(value: '', child: Text('No branch')),
              for (final b in branches)
                DropdownMenuItem(
                  value: b['id'].toString(),
                  child: Text(b['name']?.toString() ?? 'Branch'),
                ),
            ],
            onChanged: (value) => widget.controller.text = value ?? '',
          );
        },
      );
}
