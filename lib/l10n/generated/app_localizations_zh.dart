// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get stock => '股市';

  @override
  String get asset => '資產';

  @override
  String get report => '報表';

  @override
  String get setting => '設定';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get stock => '股市';

  @override
  String get asset => '資產';

  @override
  String get report => '報表';

  @override
  String get setting => '設定';
}
