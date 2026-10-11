import 'package:equatable/equatable.dart';

sealed class AppFailure extends Equatable {
  const AppFailure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  List<Object?> get props => [message, code];
}

class NetworkFailure extends AppFailure {
  const NetworkFailure([
    String message = 'No internet connection.',
    String? code,
  ]) : super(message, code: code);
}

class ServerFailure extends AppFailure {
  const ServerFailure(super.message, {super.code, this.statusCode});

  final int? statusCode;

  @override
  List<Object?> get props => [...super.props, statusCode];
}

class AuthFailure extends AppFailure {
  const AuthFailure(super.message, {super.code});
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {super.code});
}

class StorageFailure extends AppFailure {
  const StorageFailure(super.message, {super.code});
}

class OcrFailure extends AppFailure {
  const OcrFailure(super.message, {super.code});
}

class SyncFailure extends AppFailure {
  const SyncFailure(super.message, {super.code});
}

class CacheFailure extends AppFailure {
  const CacheFailure(super.message, {super.code});
}

class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure([
    String message = 'Something went wrong. Please try again.',
    String? code,
  ]) : super(message, code: code);
}
