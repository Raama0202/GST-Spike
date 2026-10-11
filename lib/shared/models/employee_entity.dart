import 'package:equatable/equatable.dart';

class EmployeeEntity extends Equatable {
  const EmployeeEntity({
    required this.id,
    required this.name,
    required this.mobile,
    required this.companyId,
    required this.companyName,
    required this.branchId,
    required this.branchName,
    this.employeeCode,
  });

  final String id;
  final String name;
  final String mobile;
  final String companyId;
  final String companyName;
  final String branchId;
  final String branchName;
  final String? employeeCode;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mobile': mobile,
    'companyId': companyId,
    'companyName': companyName,
    'branchId': branchId,
    'branchName': branchName,
    'employeeCode': employeeCode,
  };

  factory EmployeeEntity.fromJson(Map<String, dynamic> json) {
    return EmployeeEntity(
      id: json['id'] as String? ?? json['employeeId'] as String,
      name: json['name'] as String? ?? json['employeeName'] as String? ?? '',
      mobile:
          json['mobile'] as String? ?? json['mobileNumber'] as String? ?? '',
      companyId: json['companyId'] as String,
      companyName: json['companyName'] as String? ?? '',
      branchId: json['branchId'] as String? ?? '',
      branchName: json['branchName'] as String? ?? '',
      employeeCode:
          json['employeeCode'] as String? ?? json['employeeId'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, companyId, mobile];
}

class AuthTokens extends Equatable {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.expiresInSeconds,
  });

  final String accessToken;
  final String refreshToken;
  final int? expiresInSeconds;

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken:
          json['accessToken'] as String? ?? json['access_token'] as String,
      refreshToken:
          json['refreshToken'] as String? ?? json['refresh_token'] as String,
      expiresInSeconds: json['expiresIn'] as int? ?? json['expires_in'] as int?,
    );
  }

  @override
  List<Object?> get props => [accessToken, refreshToken];
}

class AuthSession extends Equatable {
  const AuthSession({required this.tokens, required this.employee});

  final AuthTokens tokens;
  final EmployeeEntity employee;

  @override
  List<Object?> get props => [tokens, employee];
}
