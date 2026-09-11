import '../../models/data_api_exception.dart';

int roundRatio(BigInt numerator, BigInt denominator) {
  if (denominator <= BigInt.zero) {
    throw const DataApiException(
      DataErrorCode.validation,
      'Invalid denominator',
    );
  }
  final absolute = numerator.abs();
  var rounded = absolute ~/ denominator;
  if ((absolute % denominator) * BigInt.two >= denominator) {
    rounded += BigInt.one;
  }
  if (numerator.isNegative) rounded = -rounded;
  if (!rounded.isValidInt) {
    throw const DataApiException(DataErrorCode.validation, 'Amount overflow');
  }
  return rounded.toInt();
}

int checkedAdd(int a, int b) =>
    roundRatio(BigInt.from(a) + BigInt.from(b), BigInt.one);
