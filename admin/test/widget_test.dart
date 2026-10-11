import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gst_expense_admin/core/constants.dart';
import 'package:gst_expense_admin/core/theme.dart';

void main() {
  testWidgets('admin product identity renders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.light,
        home: const Scaffold(body: Text(AppConstants.appName)),
      ),
    );
    expect(find.text('GST Expense Admin'), findsOneWidget);
    expect(
      Theme.of(
        tester.element(find.text(AppConstants.appName)),
      ).colorScheme.primary,
      isNotNull,
    );
  });
}
