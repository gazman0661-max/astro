import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okey101/models/player.dart';
import 'package:okey101/models/table_models.dart';
import 'package:okey101/models/tile.dart';
import 'package:okey101/widgets/game_start_popup.dart';

TableSnapshot _snap() => TableSnapshot(
      tableId: 't',
      settings: const TableSettings(),
      me: const Player(id: 'me', name: 'Ben', chipCount: 0, avatar: 1),
      left: const Player(id: 'p2', name: 'Elif', chipCount: 0, avatar: 2),
      top: const Player(id: 'p3', name: 'Murat', chipCount: 0, avatar: 3),
      right: const Player(id: 'p4', name: 'Deniz', chipCount: 0, avatar: 4),
      rack: List<Tile?>.filled(32, null),
      indicator: const Tile(id: -1, number: 1, color: TileColor.yellow),
      deckCount: 54,
      discards: {for (final s in Seat.values) s: null},
      openedMelds: const [],
      activeSeat: Seat.me,
    );

void main() {
  test('başlama geri sayımı 8 saniye', () => expect(kStartCountdownSeconds, 8));

  testWidgets('OYUN BAŞLIYOR penceresi sayıyı ve oyuncuları gösterir', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: GameStartPopup(seconds: 8, table: _snap()))));
    expect(find.text('OYUN BAŞLIYOR'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('Elif'), findsOneWidget);
    expect(find.text('Bilet oyun başlayınca düşer'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: GameStartPopup(seconds: 7, table: _snap()))));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('7'), findsOneWidget);
  });
}
