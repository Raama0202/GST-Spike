import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/format.dart';

const invoicePageSize = 25;

const invoiceStatuses = [
  ('all', 'All'),
  ('pending', 'Pending'),
  ('approved', 'Approved'),
  ('rejected', 'Rejected'),
  ('returned', 'Returned'),
];

const invoiceSorts = [
  ('uploaded_desc', 'Newest first'),
  ('uploaded_asc', 'Oldest first'),
  ('amount_desc', 'Amount: high to low'),
  ('amount_asc', 'Amount: low to high'),
];

const _unset = Object();

class InvoiceFilters extends Equatable {
  const InvoiceFilters({
    this.status = 'pending',
    this.query = '',
    this.sort = 'uploaded_desc',
    this.dateFrom,
    this.dateTo,
    this.branchId,
    this.categoryId,
  });

  final String status;
  final String query;
  final String sort;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? branchId;
  final String? categoryId;

  InvoiceFilters copyWith({
    String? status,
    String? query,
    String? sort,
    Object? dateFrom = _unset,
    Object? dateTo = _unset,
    Object? branchId = _unset,
    Object? categoryId = _unset,
  }) => InvoiceFilters(
    status: status ?? this.status,
    query: query ?? this.query,
    sort: sort ?? this.sort,
    dateFrom: dateFrom == _unset ? this.dateFrom : dateFrom as DateTime?,
    dateTo: dateTo == _unset ? this.dateTo : dateTo as DateTime?,
    branchId: branchId == _unset ? this.branchId : branchId as String?,
    categoryId: categoryId == _unset ? this.categoryId : categoryId as String?,
  );

  Map<String, dynamic> toQuery() => {
    if (status != 'all') 'status': status,
    if (query.trim().isNotEmpty) 'q': query.trim(),
    'sort': sort,
    if (dateFrom != null) 'dateFrom': isoDate(dateFrom!),
    if (dateTo != null) 'dateTo': isoDate(dateTo!),
    if (branchId != null) 'branchId': branchId,
    if (categoryId != null) 'categoryId': categoryId,
  };

  @override
  List<Object?> get props => [
    status,
    query,
    sort,
    dateFrom,
    dateTo,
    branchId,
    categoryId,
  ];
}

class InvoicePage {
  const InvoicePage(this.items, this.total);
  final List<Map<String, dynamic>> items;
  final int total;
}

class InvoiceExport {
  const InvoiceExport(this.bytes, this.filename);
  final Uint8List bytes;
  final String filename;
}

class InvoiceRepository {
  InvoiceRepository(this._dio);
  final Dio _dio;

  Future<InvoicePage> list(InvoiceFilters filters, int page) async {
    final response = await _dio.get(
      ApiPaths.invoices,
      queryParameters: {
        ...filters.toQuery(),
        'page': page,
        'pageSize': invoicePageSize,
      },
    );
    return InvoicePage(itemList(response.data), itemTotal(response.data));
  }

  Future<Map<String, dynamic>> detail(String id) async {
    final response = await _dio.get('${ApiPaths.invoices}/$id');
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Re-checks the supplier GSTIN with the GST portal; returns the updated invoice.
  Future<Map<String, dynamic>> verifyGstin(String id) async {
    final response = await _dio.post('${ApiPaths.invoices}/$id/verify-gstin');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> decide(String id, String action, String? remarks) => _dio.post(
    '${ApiPaths.invoices}/$id/$action',
    data: {
      if (remarks != null && remarks.trim().isNotEmpty)
        'remarks': remarks.trim(),
    },
  );

  Future<Map<String, dynamic>> update(
    String id, {
    Map<String, dynamic>? editedData,
    bool setCategory = false,
    String? categoryId,
  }) async {
    final response = await _dio.patch(
      '${ApiPaths.invoices}/$id',
      data: {
        if (editedData != null && editedData.isNotEmpty)
          'editedData': editedData,
        if (setCategory) 'categoryId': categoryId,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// [status] is the target status: approved, rejected or returned.
  Future<({int updated, int skipped})> bulkDecision(
    List<String> ids,
    String status,
    String? remarks,
  ) async {
    final response = await _dio.post(
      ApiPaths.invoicesBulkDecision,
      data: {
        'ids': ids,
        'status': status,
        if (remarks != null && remarks.trim().isNotEmpty)
          'remarks': remarks.trim(),
      },
    );
    final data = response.data is Map ? response.data as Map : const {};
    return (
      updated: (data['updated'] as num?)?.toInt() ?? 0,
      skipped: (data['skipped'] as num?)?.toInt() ?? 0,
    );
  }

  Future<InvoiceExport> export(InvoiceFilters filters, String format) async {
    final response = await _dio.get<List<int>>(
      ApiPaths.invoicesExport,
      queryParameters: {...filters.toQuery(), 'format': format},
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 3),
      ),
    );
    final filename =
        dispositionFilename(response.headers.value('content-disposition')) ??
        'invoices-${isoDate(DateTime.now()).replaceAll('-', '')}.$format';
    return InvoiceExport(
      Uint8List.fromList(response.data ?? const []),
      filename,
    );
  }

  Future<List<Map<String, dynamic>>> categories() async =>
      itemList((await _dio.get(ApiPaths.categories)).data);

  Future<List<Map<String, dynamic>>> branches() async =>
      itemList((await _dio.get(ApiPaths.branches)).data);
}

final invoiceRepositoryProvider = Provider(
  (ref) => InvoiceRepository(ref.watch(dioProvider)),
);

class InvoiceFiltersController extends Notifier<InvoiceFilters> {
  @override
  InvoiceFilters build() => const InvoiceFilters();
  void set(InvoiceFilters value) => state = value;
  void update(InvoiceFilters Function(InvoiceFilters) change) =>
      state = change(state);
}

final invoiceFiltersProvider =
    NotifierProvider<InvoiceFiltersController, InvoiceFilters>(
      InvoiceFiltersController.new,
    );

class InvoiceListState {
  const InvoiceListState({
    required this.items,
    required this.total,
    required this.page,
    this.loadingMore = false,
    this.moreError,
  });
  final List<Map<String, dynamic>> items;
  final int total;
  final int page;
  final bool loadingMore;
  final String? moreError;
  bool get hasMore => items.length < total;

  InvoiceListState copyWith({
    List<Map<String, dynamic>>? items,
    int? total,
    int? page,
    bool? loadingMore,
    String? moreError,
  }) => InvoiceListState(
    items: items ?? this.items,
    total: total ?? this.total,
    page: page ?? this.page,
    loadingMore: loadingMore ?? this.loadingMore,
    moreError: moreError,
  );
}

/// First page on build (and whenever filters change), more pages on demand.
class InvoiceListController extends AsyncNotifier<InvoiceListState> {
  @override
  Future<InvoiceListState> build() async {
    final filters = ref.watch(invoiceFiltersProvider);
    final page = await ref.read(invoiceRepositoryProvider).list(filters, 1);
    return InvoiceListState(items: page.items, total: page.total, page: 1);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        state.isLoading ||
        current.loadingMore ||
        current.moreError != null ||
        !current.hasMore) {
      return;
    }
    await _fetchNext(current);
  }

  Future<void> retryMore() async {
    final current = state.value;
    if (current == null || current.loadingMore) return;
    await _fetchNext(current);
  }

  Future<void> _fetchNext(InvoiceListState current) async {
    final filters = ref.read(invoiceFiltersProvider);
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await ref
          .read(invoiceRepositoryProvider)
          .list(filters, current.page + 1);
      if (!ref.mounted || ref.read(invoiceFiltersProvider) != filters) return;
      final seen = {for (final item in current.items) item['id']};
      state = AsyncData(
        current.copyWith(
          items: [
            ...current.items,
            ...next.items.where((item) => !seen.contains(item['id'])),
          ],
          total: next.total,
          page: current.page + 1,
        ),
      );
    } catch (error) {
      if (!ref.mounted || ref.read(invoiceFiltersProvider) != filters) return;
      state = AsyncData(current.copyWith(moreError: apiError(error)));
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {
      // The screen renders the error state.
    }
  }
}

final invoiceListProvider =
    AsyncNotifierProvider.autoDispose<InvoiceListController, InvoiceListState>(
      InvoiceListController.new,
    );

final invoiceDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, id) => ref.watch(invoiceRepositoryProvider).detail(id),
    );

final invoiceCategoriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref.watch(invoiceRepositoryProvider).categories(),
    );

final invoiceBranchesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref.watch(invoiceRepositoryProvider).branches(),
    );

/// Values the admin sees: their corrections over the OCR result.
Map<String, dynamic> invoiceFields(Map<String, dynamic> item) {
  final ocr = item['ocrData'] is Map
      ? Map<String, dynamic>.from(item['ocrData'] as Map)
      : <String, dynamic>{};
  final edited = item['editedData'] is Map
      ? Map<String, dynamic>.from(item['editedData'] as Map)
      : <String, dynamic>{};
  return {...ocr, ...edited};
}

String invoiceStatus(Map<String, dynamic> item) =>
    (item['approvalStatus'] ?? item['status'] ?? 'pending').toString();

String invoiceVendor(Map<String, dynamic> item) {
  final fields = invoiceFields(item);
  return (fields['vendorName'] ??
          item['vendorName'] ??
          item['invoiceNumber'] ??
          'Invoice')
      .toString();
}

dynamic invoiceAmount(Map<String, dynamic> item) {
  final fields = invoiceFields(item);
  return item['netAmount'] ?? fields['totalAmount'] ?? fields['netAmount'];
}
