import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/generated/app_localizations.dart';
import 'ui/views/asset_view.dart';
import 'ui/views/report_view.dart';
import 'ui/views/setting_view.dart';
import 'ui/views/stock_view.dart';

void main() {
  runApp(const AssetraApp());
}

class AssetraApp extends StatelessWidget {
  final Locale? locale;

  const AssetraApp({super.key, this.locale});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('zh', 'TW')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: _resolveLocale,
      home: const _AppShell(),
    );
  }

  Locale _resolveLocale(Locale? requestedLocale, Iterable<Locale> supported) {
    if (requestedLocale?.languageCode == 'zh' ||
        requestedLocale?.languageCode == 'yue') {
      return const Locale('zh', 'TW');
    }
    return const Locale('en');
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final labels = [
      localizations.stock,
      localizations.asset,
      localizations.report,
      localizations.setting,
    ];
    final views = [
      StockView(title: labels[0]),
      AssetView(title: labels[1]),
      ReportView(title: labels[2]),
      SettingView(title: labels[3]),
    ];

    return Scaffold(
      body: views[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.show_chart),
            label: labels[0],
          ),
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet),
            label: labels[1],
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart),
            label: labels[2],
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings),
            label: labels[3],
          ),
        ],
      ),
    );
  }
}
