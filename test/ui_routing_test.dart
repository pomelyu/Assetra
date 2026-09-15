import 'dart:io';

import 'package:assetra/data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:assetra/main.dart';
import 'package:assetra/ui/views/account_transaction_view.dart';

void main() {
  testWidgets('資產交易 FAB 與帳戶管理可導向正確編輯頁', (WidgetTester tester) async {
    await tester.pumpWidget(const AssetraApp(locale: Locale('zh', 'TW')));

    await tester.tap(find.text('資產'));
    await tester.pumpAndSettle();
    expect(find.text('尚未建立資料'), findsOneWidget);
    await tester.tap(find.byKey(const Key('asset-add-transaction')));
    await tester.pumpAndSettle();
    expect(find.text('新增交易紀錄'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('帳戶管理'));
    await tester.pumpAndSettle();
    expect(find.text('尚未建立資料'), findsOneWidget);
    await tester.tap(find.byKey(const Key('account-manager-add-account')));
    await tester.pumpAndSettle();
    expect(find.text('新增一般帳戶'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('分類管理'));
    await tester.pumpAndSettle();
    expect(find.text('分類管理'), findsOneWidget);
  });

  testWidgets('資產帳戶可進入詳情，再進入一般帳戶交易編輯頁', (WidgetTester tester) async {
    final directory = Directory.systemTemp.createTempSync('assetra-ui-test-');
    final api = await PortfolioDataApi.open(
      databasePath: '${directory.path}/db.sqlite',
    );
    await api.createAccount(
      const CreateAccountInput(
        name: '日常帳戶',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 120.25,
        initialValue: 95.75,
      ),
    );

    await tester.pumpWidget(
      AssetraApp(locale: const Locale('zh', 'TW'), api: api),
    );
    await tester.tap(find.text('資產'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日常帳戶'));
    await tester.pumpAndSettle();
    expect(find.text('交易紀錄'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('新增交易紀錄'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('交易紀錄'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await api.close();
    directory.deleteSync(recursive: true);
  });

  testWidgets('從帳戶詳情新增交易時會帶入當前帳戶', (WidgetTester tester) async {
    final directory = Directory.systemTemp.createTempSync('assetra-ui-test-');
    final api = await PortfolioDataApi.open(
      databasePath: '${directory.path}/db.sqlite',
    );
    await api.createAccount(
      const CreateAccountInput(
        name: '其他帳戶',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 0,
        initialValue: 0,
      ),
    );
    final currentAccountId = await api.createAccount(
      const CreateAccountInput(
        name: '當前帳戶',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 0,
        initialValue: 0,
      ),
    );

    await tester.pumpWidget(
      AssetraApp(locale: const Locale('zh', 'TW'), api: api),
    );
    await tester.tap(find.text('資產'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('當前帳戶'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    void expectSelectedAccount(Key key, String accountId) {
      final dropdown = tester.widget<DropdownButton<String>>(find.byKey(key));
      expect(dropdown.value, accountId);
    }

    expectSelectedAccount(
      const Key('account-transaction-target-account'),
      currentAccountId,
    );

    await tester.tap(find.byType(DropdownButton<AccountTransactionFormKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('支出').last);
    await tester.pumpAndSettle();
    expectSelectedAccount(
      const Key('account-transaction-source-account'),
      currentAccountId,
    );

    await tester.tap(find.byType(DropdownButton<AccountTransactionFormKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('轉帳').last);
    await tester.pumpAndSettle();
    expectSelectedAccount(
      const Key('account-transaction-source-account'),
      currentAccountId,
    );

    await tester.pumpWidget(const SizedBox());
    await api.close();
    directory.deleteSync(recursive: true);
  });
}
