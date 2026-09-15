// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get stock => 'Stock';

  @override
  String get asset => 'Asset';

  @override
  String get report => 'Report';

  @override
  String get setting => 'Setting';

  @override
  String get allTransactions => 'All';

  @override
  String get incomingTransactions => 'In (+)';

  @override
  String get outgoingTransactions => 'Out (-)';
}
