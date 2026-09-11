import 'package:assetra/data/data.dart';
import 'package:assetra/data/src/ledger/arithmetic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public money units are actual currency amounts', () {
    expect(Money(currencyCode: 'USD', units: 12.5).units, 12.5);
    expect(Money(currencyCode: 'TWD', units: -123).units, -123);
    expect(
      () => Money(currencyCode: 'TWD', units: 1.2),
      throwsA(isA<DataApiException>()),
    );
    expect(
      () => Money(currencyCode: 'GBP', units: 1),
      throwsA(isA<DataApiException>()),
    );
  });

  test('public share units support up to four decimal places', () {
    expect(ShareQuantity(units: 10.1234).units, 10.1234);
    expect(
      () => ShareQuantity(units: 10.12345),
      throwsA(isA<DataApiException>()),
    );
  });
  test('half units round away from zero with exact rational arithmetic', () {
    expect(roundRatio(BigInt.from(101), BigInt.two), 51);
    expect(roundRatio(BigInt.from(-101), BigInt.two), -51);
    expect(
      roundRatio(BigInt.from(1000) * BigInt.from(600), BigInt.from(1200)),
      500,
    );
  });
}
