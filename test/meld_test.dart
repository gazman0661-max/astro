import 'package:flutter_test/flutter_test.dart';
import 'package:okey101/logic/meld.dart';
import 'package:okey101/logic/okey_rules.dart';
import 'package:okey101/models/tile.dart';

int _id = 1000;
Tile t(int n, TileColor c) => Tile(id: _id++, number: n, color: c);

void main() {
  // okey = sarı 5
  final okey = Okey.fromIndicator(t(4, TileColor.yellow));
  final y = TileColor.yellow, b = TileColor.blue, k = TileColor.black, r = TileColor.red;

  Meld run(List<Tile> g) => Meld.fromGroup(g, okey, 0)!;

  group('Meld.tryAdd seri', () {
    test('iki uca da eklenir', () {
      final m = run([t(4, b), t(5, b), t(6, b)]);
      expect(m.tryAdd(t(7, b), okey)!.tiles.length, 4);
      final front = m.tryAdd(t(3, b), okey)!;
      expect(front.number, 3);
      expect(front.tiles.length, 4);
    });
    test('yanlış renk / boşluklu sayı eklenmez', () {
      final m = run([t(4, b), t(5, b), t(6, b)]);
      expect(m.tryAdd(t(7, k), okey), isNull);
      expect(m.tryAdd(t(8, b), okey), isNull);
    });
    test('13 sonrası 1 eklenmez (1 sadece başta)', () {
      final m = run([t(11, b), t(12, b), t(13, b)]);
      expect(m.tryAdd(t(1, b), okey), isNull);
    });
    test('12-13-1 ve 13-1-2 seri olarak açılmaz', () {
      expect(Meld.fromGroup([t(12, b), t(13, b), t(1, b)], okey, 0), isNull);
      expect(Meld.fromGroup([t(13, b), t(1, b), t(2, b)], okey, 0), isNull);
    });
    test('1-2-3 başına bir şey eklenmez', () {
      final m = run([t(1, b), t(2, b), t(3, b)]);
      expect(m.tryAdd(t(13, b), okey), isNull);
      expect(m.tryAdd(t(4, b), okey), isNotNull);
    });
    test('okey: front=true başa, front=false sona', () {
      final joker = t(5, y);
      final m = run([t(7, b), t(8, b), t(9, b)]);
      expect(m.tryAdd(joker, okey, front: true)!.number, 6);
      expect(m.tryAdd(joker, okey, front: false)!.number, 7);
    });
    test('okey 13 ile biten seride başa eklenir', () {
      final joker = t(5, y);
      final m = run([t(11, b), t(12, b), t(13, b)]);
      expect(m.tryAdd(joker, okey)!.number, 10);
    });
  });

  group('okey çalma (trySwap)', () {
    final joker = t(5, y);
    test('seride okeyin yerindeki taş okeyi alır', () {
      final m = run([t(7, b), joker, t(9, b)]);
      final sw = m.trySwap(t(8, b), okey)!;
      expect(sw.joker.id, joker.id);
      expect(okey.isWild(sw.meld.tiles[1]), isFalse);
      expect(sw.meld.value, 24);
    });
    test('yanlış taş okeyi alamaz', () {
      final m = run([t(7, b), joker, t(9, b)]);
      expect(m.trySwap(t(8, k), okey), isNull);
      expect(m.trySwap(t(6, b), okey), isNull);
      expect(m.trySwap(t(5, y), okey), isNull); // okey okeyi çalamaz
    });
    test('kütte perde olmayan renkten aynı sayı okeyi alır', () {
      final m = run([t(7, b), t(7, k), joker]);
      expect(m.trySwap(t(7, r), okey), isNotNull);
      expect(m.trySwap(t(7, b), okey), isNull);
      expect(m.trySwap(t(8, r), okey), isNull);
    });
    test('çift perde aynı sayı+renkteki taş okeyi alır', () {
      final p = Meld.pairFrom([t(8, b), joker], okey, 0)!;
      final sw = p.trySwap(t(8, b), okey)!;
      expect(sw.joker.id, joker.id);
      expect(sw.meld.kind, MeldKind.pair);
      expect(sw.meld.tiles.any((x) => okey.isWild(x)), isFalse);
      expect(sw.meld.value, 16);
    });
    test('çift perde yanlış renk/sayı veya okeysiz çift çalınamaz', () {
      final p = Meld.pairFrom([t(8, b), joker], okey, 0)!;
      expect(p.trySwap(t(8, k), okey), isNull);
      expect(p.trySwap(t(9, b), okey), isNull);
      final real = Meld.pairFrom([t(8, b), t(8, b)], okey, 0)!;
      expect(real.trySwap(t(8, b), okey), isNull);
    });
    test('11-12-okey serisinde okey 13 yerindedir', () {
      final m = run([t(11, b), t(12, b), joker]);
      expect(m.trySwap(t(13, b), okey), isNotNull);
      expect(m.trySwap(t(1, b), okey), isNull);
    });
  });

  group('Meld.tryAdd küt', () {
    test('dördüncü renk eklenir, aynı renk eklenmez', () {
      final m = run([t(7, b), t(7, k), t(7, r)]);
      expect(m.tryAdd(t(7, y), okey), isNotNull);
      expect(m.tryAdd(t(7, b), okey), isNull);
    });
    test('4 taşlı küte eklenmez', () {
      final m = run([t(7, b), t(7, k), t(7, r), t(7, y)]);
      expect(m.tryAdd(t(7, b), okey), isNull);
      expect(m.tryAdd(t(5, y), okey), isNull); // okey de olsa
    });
  });

  group('çift', () {
    test('aynı sayı+renk çift olur; okeyle de olur', () {
      expect(Meld.pairFrom([t(8, b), t(8, b)], okey, 0), isNotNull);
      expect(Meld.pairFrom([t(8, b), t(5, y)], okey, 0), isNotNull);
      expect(Meld.pairFrom([t(8, b), t(8, k)], okey, 0), isNull);
    });
    test('çifte taş işlenmez', () {
      final p = Meld.pairFrom([t(8, b), t(8, b)], okey, 0)!;
      expect(p.tryAdd(t(8, b), okey), isNull);
    });
  });

  test('değer: seri ve küt', () {
    expect(run([t(4, b), t(5, b), t(6, b)]).value, 15);
    expect(run([t(7, b), t(7, k), t(7, r)]).value, 21);
  });
}
