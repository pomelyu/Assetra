import 'data_api_exception.dart';

const moneyMultipliers = {'TWD': 1, 'JPY': 1, 'USD': 100, 'EUR': 100};
const shareMultiplier = 10000;
const exchangeRateMultiplier = 100;

/// An amount expressed in the currency identified by [currencyCode].
///
/// Input: [units] is the actual amount seen by the caller, such as `12.5` for
/// USD 12.50. Output: [units] remains that actual amount. Database scaling is
/// deliberately hidden from callers.
class Money {
  final String currencyCode;
  final double units;

  /// Creates a monetary amount from an actual currency value.
  ///
  /// Parameters
  /// ----------
  /// currencyCode : `String`
  ///     Supported ISO 4217 currency code.
  /// units : `num`
  ///     Actual amount; TWD and JPY accept integers, while USD and EUR accept
  ///     at most two decimal places.
  ///
  /// Returns
  /// -------
  /// `Money`
  ///     Immutable money value whose [units] remains the caller-facing amount.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the currency, numeric value, or decimal precision is invalid.
  Money({required String currencyCode, required num units})
    : currencyCode = currencyCode,
      units = units.toDouble() {
    _scaleExact(this.units, _moneyMultiplier(currencyCode), 'money');
  }

  /// Creates a money value from its database representation.
  ///
  /// Parameters
  /// ----------
  /// currencyCode : `String`
  ///     Supported currency that determines the storage multiplier.
  /// units : `int`
  ///     Scaled integer read from SQLite.
  ///
  /// Returns
  /// -------
  /// `Money`
  ///     Money converted back to its actual caller-facing amount.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If [currencyCode] is unsupported.
  ///
  /// This constructor is reserved for the data-layer implementation.
  Money.fromScaledUnits({required String currencyCode, required int units})
    : currencyCode = currencyCode,
      units = units / _moneyMultiplier(currencyCode);

  /// Returns the integer representation used by SQLite.
  ///
  /// This is for the data-layer implementation; application code should read
  /// [units] instead.
  int get scaledUnits =>
      _scaleExact(units, _moneyMultiplier(currencyCode), 'money');

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.units == units &&
      other.currencyCode == currencyCode;
  @override
  int get hashCode => Object.hash(currencyCode, units);
}

class ShareQuantity {
  final double units;

  /// Creates a share quantity from the actual number of shares.
  ///
  /// Parameters
  /// ----------
  /// units : `num`
  ///     Actual share count with at most four decimal places.
  ///
  /// Returns
  /// -------
  /// `ShareQuantity`
  ///     Immutable quantity whose [units] remains the caller-facing share count.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the value is non-finite or has more than four decimal places.
  ///
  /// Market-specific fractional-share rules are validated by transaction APIs.
  ShareQuantity({required num units}) : units = units.toDouble() {
    _scaleExact(this.units, shareMultiplier, 'share quantity');
  }

  /// Creates a share quantity from its database representation.
  ///
  /// Parameters
  /// ----------
  /// units : `int`
  ///     Scaled integer read from SQLite.
  ///
  /// Returns
  /// -------
  /// `ShareQuantity`
  ///     Quantity converted back to its actual caller-facing share count.
  ///
  /// Raises
  /// ------
  /// `None`
  ///
  /// This constructor is reserved for the data-layer implementation.
  ShareQuantity.fromScaledUnits(int units) : units = units / shareMultiplier;

  /// Returns the integer representation used by SQLite.
  int get scaledUnits => _scaleExact(units, shareMultiplier, 'share quantity');
}

int _moneyMultiplier(String currencyCode) {
  final multiplier = moneyMultipliers[currencyCode];
  if (multiplier == null) {
    throw const DataApiException(
      DataErrorCode.validation,
      'Unsupported currency',
    );
  }
  return multiplier;
}

int _scaleExact(double value, int multiplier, String label) {
  if (!value.isFinite) {
    throw DataApiException(DataErrorCode.validation, 'Invalid $label');
  }
  final scaled = value * multiplier;
  final rounded = scaled.round();
  if ((scaled - rounded).abs() > 0.0000001) {
    throw DataApiException(
      DataErrorCode.validation,
      'Too many decimal places for $label',
    );
  }
  return rounded;
}
