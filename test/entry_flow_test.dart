import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:okey101/screens/entry_flow.dart';
import 'package:okey101/services/account_service.dart';

Widget _app(AccountService a) => MaterialApp(
    home: EntryFlow(
        account: a,
        splash: const Duration(milliseconds: 200),
        builder: (_) => const Scaffold(body: Text('OYUN'))));

void main() {
  testWidgets('ilk açılış: splash -> giriş ekranı -> misafir -> oyun', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(_app(MockAccountService()));
    expect(find.text('MİSAFİR GİRİŞİ'), findsNothing);
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    expect(find.text('GOOGLE İLE GİRİŞ'), findsOneWidget);
    expect(find.text('MİSAFİR GİRİŞİ'), findsOneWidget);
    await t.tap(find.text('MİSAFİR GİRİŞİ'));
    await t.pumpAndSettle();
    expect(find.text('OYUN'), findsOneWidget);
  });

  testWidgets('Google ile giriş: oyuna geçer ve hesap Google olur', (t) async {
    SharedPreferences.setMockInitialValues({});
    final a = MockAccountService();
    await t.pumpWidget(_app(a));
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    await t.tap(find.text('GOOGLE İLE GİRİŞ'));
    await t.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('OYUN'), findsOneWidget);
    expect(a.mode, AccountMode.google);
  });

  testWidgets('daha önce seçilmişse splash sonrası doğrudan oyun', (t) async {
    SharedPreferences.setMockInitialValues({'entry_done': true});
    await t.pumpWidget(_app(MockAccountService()));
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    expect(find.text('OYUN'), findsOneWidget);
    expect(find.text('MİSAFİR GİRİŞİ'), findsNothing);
  });
}
