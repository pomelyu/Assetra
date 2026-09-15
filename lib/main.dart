import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:forui/forui.dart';
import 'package:path_provider/path_provider.dart';

import 'data/data.dart';
import 'l10n/generated/app_localizations.dart';
import 'ui/views/account_edit_view.dart';
import 'ui/views/account_detail_view.dart';
import 'ui/views/account_manager_view.dart';
import 'ui/views/account_transaction_view.dart';
import 'ui/views/asset_view.dart';
import 'ui/views/category_manager_view.dart';
import 'ui/views/report_view.dart';
import 'ui/views/setting_view.dart';
import 'ui/views/stock_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final documentsDirectory = await getApplicationDocumentsDirectory();
  final api = await PortfolioDataApi.open(
    databasePath:
        '${documentsDirectory.path}${Platform.pathSeparator}assetra.sqlite',
  );
  runApp(AssetraApp(api: api));
}

class AssetraApp extends StatelessWidget {
  final Locale? locale;
  final PortfolioDataApi? api;

  const AssetraApp({super.key, this.locale, this.api});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: locale,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff059669),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xffF6F8FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xffF6F8FB),
          foregroundColor: Color(0xff14213A),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          titleTextStyle: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xffF7F9FC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xffE8EDF4)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xffE8EDF4)),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: Color(0xffE8FAF2),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xff00B87A),
          foregroundColor: Colors.white,
          elevation: 8,
          shape: CircleBorder(),
        ),
      ),
      supportedLocales: const [Locale('en'), Locale('zh', 'TW')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: _resolveLocale,
      home: FTheme(
        data: FTheme.neutral.light.touch,
        child: _AppShell(api: api),
      ),
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
  final PortfolioDataApi? api;

  const _AppShell({this.api});

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
      AssetView(
        title: labels[1],
        api: widget.api,
        onAddTransaction: () async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) =>
                  AccountTransactionView(api: widget.api),
            ),
          );
        },
        onOpenAccount: widget.api == null
            ? null
            : (String accountId) async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => AccountDetailView(
                      api: widget.api!,
                      accountId: accountId,
                      onAddTransaction: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) =>
                                AccountTransactionView(
                                  api: widget.api,
                                  accountId: accountId,
                                ),
                          ),
                        );
                      },
                      onEditTransaction: (String transactionId) async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) =>
                                AccountTransactionView(
                                  api: widget.api,
                                  transactionId: transactionId,
                                  accountId: accountId,
                                ),
                          ),
                        );
                      },
                      onEditAccount: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) => AccountEditView(
                              api: widget.api,
                              accountId: accountId,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
      ),
      ReportView(title: labels[2]),
      SettingView(
        title: labels[3],
        onManageAccounts: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => AccountManagerView(
                api: widget.api,
                onCreateAccount: () async {
                  await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (BuildContext context) =>
                          AccountEditView(api: widget.api),
                    ),
                  );
                },
                onEditAccount: (String accountId) async {
                  await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (BuildContext context) => AccountEditView(
                        api: widget.api,
                        accountId: accountId,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
        onManageCategories: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) =>
                  CategoryManagerView(api: widget.api),
            ),
          );
        },
      ),
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
