import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okey101/models/table_models.dart';
import 'package:okey101/services/mock_game_service.dart';
import 'package:okey101/widgets/presence_widgets.dart';

void main() {
  test('Presence: varsayılan kimse away değil, koltuk sırası ben-sağ-karşı-sol', () {
    for (final s in Seat.values) {
      expect(Presence.none.isAway(s), isFalse);
      expect(Presence.none.isAfk(s), isFalse);
    }
    const p = Presence(
      away: [false, true, false, true],
      afk: [false, false, false, true],
    );
    expect(p.isAway(Seat.right), isTrue);
    expect(p.isAfk(Seat.right), isFalse); // bağlantısı koptu, boşta değil
    expect(p.isAway(Seat.left), isTrue);
    expect(p.isAfk(Seat.left), isTrue); // boşta
    expect(p.isAway(Seat.me), isFalse);
  });

  test('sahte servis: hep bağlı, olay yok, imHere sessiz', () async {
    final s = MockGameService();
    expect(s.isConnected, isTrue);
    s.imHere(); // hata atmamalı
    expect(await s.presence.isEmpty, isTrue);
    expect(await s.connection.isEmpty, isTrue);
  });

  testWidgets('AwayOverlay: OYUNA DÖN dokununca onBack çağrılır', (tester) async {
    var back = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AwayOverlay(onBack: () => back++))));
    expect(find.text('BOŞTASIN'), findsOneWidget);
    expect(find.text('OYUNA DÖN'), findsOneWidget);
    await tester.tap(find.text('OYUNA DÖN'));
    expect(back, 1);
  });

  testWidgets('ConnectionBanner: bağlantı koptu yazısı görünür ve dokunmayı engellemez', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(fit: StackFit.expand, children: [
          GestureDetector(onTap: () => taps++, child: const ColoredBox(color: Colors.green)),
          const ConnectionBanner(),
        ]),
      ),
    ));
    expect(find.textContaining('Bağlantı koptu'), findsOneWidget);
    await tester.tapAt(const Offset(100, 300)); // şeridin altındaki alana dokun
    expect(taps, 1);
  });
}
