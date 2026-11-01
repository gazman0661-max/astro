import 'package:flutter_test/flutter_test.dart';
import 'package:okey101/logic/okey_rules.dart';
import 'package:okey101/models/tile.dart';

int _id = 0;
Tile t(int n, TileColor c) => Tile(id: _id++, number: n, color: c);

void main() {
  // Gösterge sarı 4 => okey sarı 5.
  final okey = Okey.fromIndicator(t(4, TileColor.yellow));
  final y = TileColor.yellow, b = TileColor.blue, k = TileColor.black, r = TileColor.red;

  test('okey göstergenin bir fazlası; 13 göstergesinde okey 1', () {
    expect(okey.number, 5);
    expect(okey.color, y);
    final o13 = Okey.fromIndicator(t(13, r));
    expect(o13.number, 1);
    expect(o13.color, r);
  });

  test('seri: 1-2-3 geçerli, 12-13-1 ve 13-1-2 geçersiz', () {
    expect(GroupRules.valueOf([t(1, b), t(2, b), t(3, b)], okey), 6);
    expect(GroupRules.valueOf([t(12, b), t(13, b), t(1, b)], okey), 0);
    expect(GroupRules.valueOf([t(13, b), t(1, b), t(2, b)], okey), 0);
  });

  test('okey 12-13 yanında 1 yerine geçemez', () {
    final joker = t(5, y); // gerçek okey
    expect(GroupRules.valueOf([t(11, b), t(12, b), joker], okey), 36);
    expect(GroupRules.valueOf([t(12, b), t(13, b), joker], okey), 0);
    expect(GroupRules.valueOf([joker, t(13, b), t(1, b)], okey), 0);
  });

  test('küt: farklı renk şart, aynı renk tekrarı geçersiz', () {
    expect(GroupRules.valueOf([t(7, b), t(7, k), t(7, r)], okey), 21);
    expect(GroupRules.valueOf([t(7, b), t(7, b), t(7, r)], okey), 0);
    expect(GroupRules.valueOf([t(7, b), t(7, k), t(7, r), t(7, y)], okey), 28);
  });

  test('okey joker eksik taşın puanını taşır', () {
    final joker = t(5, y); // gerçek okey
    expect(okey.isWild(joker), isTrue);
    expect(GroupRules.valueOf([t(8, b), joker, t(10, b)], okey), 27);
  });

  test('sahte okey okeyin kendi sayı/rengindeki taştır', () {
    final fake = Tile.fake(_id++);
    expect(okey.isWild(fake), isFalse);
    expect(okey.numberOf(fake), 5);
    expect(okey.colorOf(fake), y);
    expect(GroupRules.valueOf([t(4, y), fake, t(6, y)], okey), 15);
  });

  test('elde kalan taş değeri: okey 101, diğerleri yüz değeri', () {
    expect(tileValue(t(5, y), okey), 101);
    expect(tileValue(t(9, b), okey), 9);
    expect(tileValue(Tile.fake(_id++), okey), 5);
  });
}
