import 'package:assetra/data/data.dart';
import 'package:assetra/data/src/ledger/arithmetic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Money.units 使用實際貨幣金額', () {
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

  test('ShareQuantity.units 支援最多四位小數', () {
    expect(ShareQuantity(units: 10.1234).units, 10.1234);
    expect(
      () => ShareQuantity(units: 10.12345),
      throwsA(isA<DataApiException>()),
    );
  });
  test('剛好半個最小單位時以遠離零方向四捨五入', () {
    expect(roundRatio(BigInt.from(101), BigInt.two), 51);
    expect(roundRatio(BigInt.from(-101), BigInt.two), -51);
    expect(
      roundRatio(BigInt.from(1000) * BigInt.from(600), BigInt.from(1200)),
      500,
    );
  });
}
