import 'package:flutter_test/flutter_test.dart';
import 'package:okey101/logic/hand_scorer.dart';
import 'package:okey101/logic/okey_rules.dart';
import 'package:okey101/models/tile.dart';

int _id = 2000;
Tile t(int n, TileColor c) => Tile(id: _id++, number: n, color: c);

void main() {
  final okey = Okey.fromIndicator(t(1, TileColor.red)); // okey kırmızı 2
  final b = TileColor.blue, k = TileColor.black, y = TileColor.yellow;
  const cols = 8;

  List<Tile?> row(List<Tile?> items) =>
      [...items, ...List<Tile?>.filled(cols - items.length, null)];

  test('boş yuva grupları ayırır', () {
    final slots = row([t(4, b), t(5, b), t(6, b), null, t(9, k), t(9, y), t(9, b)]);
    expect(HandScorer.segments(slots, cols).length, 2);
    expect(HandScorer.score(slots, cols, okey), 15 + 27);
  });

  test('bitişik ama geçersiz gruplar sayılmaz', () {
    // 4-5-6 ile 9 bitişik: tek grup, geçersiz
    final slots = row([t(4, b), t(5, b), t(6, b), t(9, k)]);
    expect(HandScorer.score(slots, cols, okey), 0);
  });

  test('gruplar satır sınırını geçmez', () {
    final slots = [
      ...List<Tile?>.filled(cols - 1, null),
      t(4, b), // satır 1 son yuva
      t(5, b), t(6, b), // satır 2 başı
      ...List<Tile?>.filled(cols - 2, null),
    ];
    expect(HandScorer.score(slots, cols, okey), 0);
  });

  test('çift sayısı', () {
    final slots = row([t(3, b), t(3, b), null, t(8, k), t(8, k), null, t(8, k)]);
    expect(HandScorer.pairCount(slots, cols, okey), 2);
  });
}
