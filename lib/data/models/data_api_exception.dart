enum DataErrorCode {
  validation,
  notFound,
  conflict,
  closed,
  storage,
  incompatibleBackup,
  authentication,
  unavailable,
}

class DataApiException implements Exception {
  final DataErrorCode code;
  final String message;
  const DataApiException(this.code, this.message);
  @override
  String toString() => 'DataApiException(${code.name}): $message';
}
