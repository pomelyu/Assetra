import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:assetra/main.dart';

void main() {
  testWidgets('底部導航預設顯示股市並可切換四個主要 view', (WidgetTester tester) async {
    await tester.pumpWidget(const AssetraApp(locale: Locale('zh', 'TW')));

    expect(find.text('股市'), findsNWidgets(2));
    expect(find.text('資產'), findsOneWidget);
    expect(find.text('報表'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);

    for (final tab in ['資產', '報表', '設定']) {
      await tester.tap(find.text(tab));
      await tester.pump();
      expect(find.text(tab), findsNWidgets(2));
    }
  });

  testWidgets('底部導航依 locale 顯示中文或英文並套用 fallback', (WidgetTester tester) async {
    await tester.pumpWidget(const AssetraApp(locale: Locale('en')));
    expect(find.text('Stock'), findsNWidgets(2));
    expect(find.text('Asset'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Setting'), findsOneWidget);

    await tester.pumpWidget(const AssetraApp(locale: Locale('zh', 'CN')));
    expect(find.text('股市'), findsNWidgets(2));

    await tester.pumpWidget(const AssetraApp(locale: Locale('yue', 'HK')));
    expect(find.text('股市'), findsNWidgets(2));

    await tester.pumpWidget(const AssetraApp(locale: Locale('ja', 'JP')));
    expect(find.text('Stock'), findsNWidgets(2));
  });
}
