import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okey101/models/rewards.dart';
import 'package:okey101/services/mock_game_service.dart';
import 'package:okey101/widgets/level_up_dialog.dart';

void main() {
  testWidgets('seviye penceresi: AL\'a basınca 1 bilet geçer ve pencere kapanır', (tester) async {
    final s = MockGameService()
      ..tickets = 3
      ..xp = 100; // seviye 2 -> 1 bekleyen hediye
    LevelClaim? got;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => got = await showLevelUp(ctx, service: s, level: 2, pending: 1),
              child: const Text('ac'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('ac'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300)); // açılış animasyonu

    expect(find.text('SEVİYE ATLADIN!'), findsOneWidget);
    expect(find.text('+1 BİLET HEDİYE'), findsOneWidget);
    expect(got, isNull); // AL'a basmadan teslim edilmez

    await tester.tap(find.text('AL'));
    await tester.pump(const Duration(seconds: 2)); // sahte servis gecikmesi + kutlama bekleme süresi
    await tester.pump(const Duration(seconds: 1)); // kapanış geçişi

    expect(got?.amount, 1);
    expect(got?.level, 2);
    expect(s.tickets, 4);
    expect(find.text('SEVİYE ATLADIN!'), findsNothing);
  });
}
