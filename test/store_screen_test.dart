import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okey101/models/store_pack.dart';
import 'package:okey101/screens/store_screen.dart';

void main() {
  test('paketler: 5-10-15-30-50, ürün kimlikleri benzersiz', () {
    expect(kStorePacks.map((p) => p.tickets).toList(), [5, 10, 15, 30, 50]);
    expect(kStorePacks.map((p) => p.productId).toSet().length, kStorePacks.length);
  });

  testWidgets('mağaza: 5 paket listelenir, fiyat yoksa SATIN AL yazar, dokununca onBuy çağrılır', (tester) async {
    tester.view.physicalSize = const Size(1400, 720); // 700x360 dp, uygulamanın en küçük tasarım alanı
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    StorePack? bought;
    await tester.pumpWidget(MaterialApp(home: StoreScreen(tickets: 7, onBuy: (p) => bought = p)));
    await tester.pump(const Duration(milliseconds: 1500)); // açılış animasyonu (sonsuz parıltı yüzünden pumpAndSettle yok)

    expect(find.text('MAĞAZA'), findsOneWidget);
    for (final n in [5, 10, 15, 30, 50]) {
      expect(find.text('$n BİLET'), findsOneWidget);
    }
    expect(find.text('SATIN AL'), findsNWidgets(5));
    expect(find.text('POPÜLER'), findsOneWidget);
    expect(find.text('AVANTAJLI'), findsOneWidget);
    expect(tester.takeException(), isNull); // taşma yok

    await tester.tap(find.text('SATIN AL').at(2));
    expect(bought?.tickets, 15);
  });

  testWidgets('Play fiyatı verilirse butonda görünür', (tester) async {
    await tester.pumpWidget(MaterialApp(home: StoreScreen(prices: const {'ticket_5': '₺24,99'})));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('₺24,99'), findsOneWidget);
    expect(find.text('SATIN AL'), findsNWidgets(4));
  });
}
