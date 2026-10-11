import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class ExpenseCategory extends Equatable {
  const ExpenseCategory({
    required this.id,
    required this.name,
    this.parentId,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String? parentId;
  final int sortOrder;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'parentId': parentId,
    'sortOrder': sortOrder,
  };

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    return ExpenseCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      parentId: json['parentId'] as String?,
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [id, name, parentId];
}

class BranchEntity extends Equatable {
  const BranchEntity({required this.id, required this.name, this.code});

  final String id;
  final String name;
  final String? code;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'code': code};

  factory BranchEntity.fromJson(Map<String, dynamic> json) {
    return BranchEntity(
      id: json['id'] as String,
      name: json['name'] as String,
      code: json['code'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, name];
}

class CompanyConfig extends Equatable {
  const CompanyConfig({
    required this.companyId,
    required this.companyName,
    required this.industry,
    required this.categories,
    required this.branches,
    required this.features,
    this.logoUrl,
    this.primaryColorHex,
    this.requiresGps = false,
    this.duplicateCheckEnabled = true,
    this.minOcrConfidenceWarn = 0.55,
    this.updatedAt,
  });

  final String companyId;
  final String companyName;
  final String industry;
  final String? logoUrl;
  final String? primaryColorHex;
  final List<ExpenseCategory> categories;
  final List<BranchEntity> branches;
  final Map<String, bool> features;
  final bool requiresGps;
  final bool duplicateCheckEnabled;
  final double minOcrConfidenceWarn;
  final DateTime? updatedAt;

  Color? get brandColor {
    final hex = primaryColorHex;
    if (hex == null || hex.isEmpty) return null;
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length != 6) return null;
    return Color(int.parse('FF$cleaned', radix: 16));
  }

  Map<String, dynamic> toJson() => {
    'companyId': companyId,
    'companyName': companyName,
    'industry': industry,
    'logoUrl': logoUrl,
    'primaryColorHex': primaryColorHex,
    'categories': categories.map((e) => e.toJson()).toList(),
    'branches': branches.map((e) => e.toJson()).toList(),
    'features': features,
    'requiresGps': requiresGps,
    'duplicateCheckEnabled': duplicateCheckEnabled,
    'minOcrConfidenceWarn': minOcrConfidenceWarn,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory CompanyConfig.fromJson(Map<String, dynamic> json) {
    return CompanyConfig(
      companyId: json['companyId'] as String,
      companyName: json['companyName'] as String? ?? '',
      industry: json['industry'] as String? ?? '',
      logoUrl: json['logoUrl'] as String?,
      primaryColorHex:
          json['primaryColorHex'] as String? ?? json['themeColor'] as String?,
      categories: ((json['categories'] as List?) ?? [])
          .map(
            (e) => ExpenseCategory.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList(),
      branches: ((json['branches'] as List?) ?? [])
          .map((e) => BranchEntity.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      features: ((json['features'] as Map?) ?? {}).map(
        (k, v) => MapEntry(k.toString(), v == true),
      ),
      requiresGps: json['requiresGps'] as bool? ?? false,
      duplicateCheckEnabled: json['duplicateCheckEnabled'] as bool? ?? true,
      minOcrConfidenceWarn:
          (json['minOcrConfidenceWarn'] as num?)?.toDouble() ?? 0.55,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [companyId, updatedAt, categories.length];
}
