import 'package:flutter_test/flutter_test.dart';
import 'package:gst_expense_admin/core/format.dart';
import 'package:gst_expense_admin/features/categories/category_tree.dart';
import 'package:gst_expense_admin/features/employees/employees_screen.dart';
import 'package:gst_expense_admin/features/invoices/invoice_repository.dart';

void main() {
  group('category tree', () {
    final categories = [
      {'id': 'travel', 'name': 'Travel', 'parentId': null},
      {'id': 'air', 'name': 'Air', 'parentId': 'travel'},
      {'id': 'domestic', 'name': 'Domestic', 'parentId': 'air'},
      {'id': 'food', 'name': 'Food', 'parentId': null},
      {'id': 'old', 'name': 'Old', 'parentId': null, 'isActive': false},
    ];

    test('finds descendants at any depth', () {
      expect(categoryDescendants(categories, 'travel'), {'air', 'domestic'});
      expect(categoryDescendants(categories, 'food'), isEmpty);
    });

    test('parent candidates exclude self, descendants and inactive', () {
      final ids = parentCandidates(
        categories,
        selfId: 'travel',
      ).map((c) => c['id']).toList();
      expect(ids, ['food']);
    });

    test('keeps an inactive parent that is already selected', () {
      final ids = parentCandidates(
        categories,
        selfId: 'domestic',
        currentParentId: 'old',
      ).map((c) => c['id']).toList();
      expect(ids, ['air', 'food', 'old', 'travel']);
    });
  });

  group('format', () {
    test('formatInr uses Indian grouping', () {
      expect(formatInr(123456.5), '₹1,23,456.50');
      expect(formatInr('2500', whole: true), '₹2,500');
      expect(formatInr(null), '—');
    });

    test('fieldLabel title-cases keys', () {
      expect(fieldLabel('invoiceNumber'), 'Invoice Number');
      expect(fieldLabel('vendor_gstin'), 'Vendor Gstin');
      expect(fieldLabel('totals.cgst'), 'Totals Cgst');
    });

    test('dispositionFilename reads plain and encoded names', () {
      expect(
        dispositionFilename('attachment; filename="invoices.csv"'),
        'invoices.csv',
      );
      expect(
        dispositionFilename("attachment; filename*=UTF-8''Mar%202026.xlsx"),
        'Mar 2026.xlsx',
      );
      expect(dispositionFilename('attachment'), isNull);
      expect(dispositionFilename(null), isNull);
    });
  });

  test('seatsSummary', () {
    expect(
      seatsSummary({
        'seats': {'used': 12, 'limit': 15},
      }),
      '12 of 15 seats used',
    );
    expect(
      seatsSummary({
        'seats': {'used': 3},
      }),
      '3 active employees',
    );
    expect(seatsSummary({'items': []}), isNull);
  });

  group('InvoiceFilters', () {
    test('default query lists pending invoices', () {
      expect(const InvoiceFilters().toQuery(), {
        'status': 'pending',
        'sort': 'uploaded_desc',
      });
    });

    test('includes every set filter', () {
      final filters = const InvoiceFilters().copyWith(
        status: 'all',
        query: '  acme ',
        dateFrom: DateTime(2026, 4, 1),
        dateTo: DateTime(2026, 4, 30),
        branchId: 'b1',
        categoryId: 'c1',
      );
      expect(filters.toQuery(), {
        'q': 'acme',
        'sort': 'uploaded_desc',
        'dateFrom': '2026-04-01',
        'dateTo': '2026-04-30',
        'branchId': 'b1',
        'categoryId': 'c1',
      });
    });

    test('copyWith can clear nullable filters', () {
      final filters = const InvoiceFilters(
        branchId: 'b1',
      ).copyWith(branchId: null);
      expect(filters.branchId, isNull);
      expect(filters, const InvoiceFilters());
    });
  });
}
