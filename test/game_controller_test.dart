import 'package:flutter_test/flutter_test.dart';
import 'package:okey101/logic/game_controller.dart';
import 'package:okey101/logic/meld.dart';
import 'package:okey101/models/table_models.dart';
import 'package:okey101/models/tile.dart';

GameController make({bool team = false}) => GameController(
    names: const ['Ben', 'Sağ', 'Üst', 'Sol'],
    settings: TableSettings(team: team),
    seed: 7);

void main() {
  group('şampiyon / beraberlik', () {
    test('tekli: en düşük toplam kazanır', () {
      final c = make();
      c.totals.setAll(0, [10, -5, 30, 12]);
      expect(c.championSeat, 1);
      c.dispose();
    });
    test('tekli: eşitlikte son el puanı düşük olan kazanır', () {
      final c = make();
      c.totals.setAll(0, [10, 10, 30, 40]);
      c.lastDelta = [50, -101, 0, 0];
      expect(c.championSeat, 1);
      c.dispose();
    });
    test('tekli: tam eşitlikte null (beraberlik)', () {
      final c = make();
      c.totals.setAll(0, [10, 10, 30, 40]);
      c.lastDelta = [5, 5, 0, 0];
      expect(c.championSeat, isNull);
      c.dispose();
    });
    test('eşli: eşitlikte son el belirler, o da eşitse null', () {
      final c = make(team: true);
      c.totals.setAll(0, [10, 20, 30, 20]); // takım0=40, takım1=40
      c.lastDelta = [0, -101, 0, 0];
      expect(c.championTeam, 1);
      c.lastDelta = [0, 0, 0, 0];
      expect(c.championTeam, isNull);
      c.dispose();
    });
    test('eşli: toplamı düşük takım kazanır (eski <= hatası yok)', () {
      final c = make(team: true);
      c.totals.setAll(0, [50, 10, 50, 10]);
      expect(c.championTeam, 1);
      c.dispose();
    });
  });

  group('açılış barajı', () {
    test('katlamasız: hep 101', () {
      final c = GameController(
          names: const ['a', 'b', 'c', 'd'],
          settings: const TableSettings(folding: false),
          seed: 1);
      expect(c.requiredOpen(0), 101);
      c.dispose();
    });
  });

  group('el dağıtımı', () {
    test('başlayan 22, diğerleri 21 taş; çekilmeden 105 taş toplam', () {
      final c = make();
      final counts = [for (var s = 0; s < 4; s++) c.handCount(s)];
      expect(counts.reduce((a, b) => a + b) + c.deck.length, 105);
      expect(counts.where((n) => n == 22).length, 1);
      expect(counts.where((n) => n == 21).length, 3);
      c.dispose();
    });
  });

  group('kural kitapçığı', () {
    test('katlamalı: önceki açanın puanından 1 fazla; eşin açması baraj düşürmez', () {
      final c = GameController(
          names: const ['a', 'b', 'c', 'd'],
          settings: const TableSettings(team: true, folding: true),
          seed: 1);
      expect(c.requiredOpen(0), 101);
      c.opened[1] = OpenMode.series;
      c.openScore[1] = 110;
      expect(c.requiredOpen(0), 111);
      c.opened[2] = OpenMode.series; // eşi
      c.openScore[2] = 105;
      expect(c.requiredOpen(0), 111);
      c.dispose();
    });

    test('lig puanı: tekli oyunda sıralamaya göre 100/60/30/10', () {
      final c = make();
      c.totals.setAll(0, [10, -5, 30, 12]);
      final pts = c.rankPoints();
      expect(pts[1], 100);
      expect(pts[0], 60);
      expect(pts[3], 30);
      expect(pts[2], 10);
      expect(c.myXp, 20 + pts[GameController.me]);
      c.dispose();
    });

    test('lig puanı: eşlide kazanan takım 100, kaybeden 30', () {
      final c = make(team: true);
      c.totals.setAll(0, [50, 10, 50, 10]);
      final pts = c.rankPoints();
      expect(pts[1], 100);
      expect(pts[3], 100);
      expect(pts[0], 30);
      expect(pts[2], 30);
      c.dispose();
    });

    test('okey çalma: perdeki okey, yerine geçen gerçek taşla alınır', () {
      final c = make(); // ilk elde sıra bende, taş atma aşaması
      expect(c.canPlay, isTrue);
      final col = c.okey.color == TileColor.blue ? TileColor.red : TileColor.blue;
      Tile t(int id, int n) => Tile(id: id, number: n, color: col);
      final joker = Tile(id: 900, number: c.okey.number, color: c.okey.color);
      c.table = [
        Meld.fromGroup([t(901, 7), joker, t(902, 9)], c.okey, 1)!,
      ];
      c.opened[0] = OpenMode.series;
      final eight = t(903, 8);
      c.rack[31] = eight;
      c.layOff(eight, meldIndex: 0);
      expect(c.table[0].tiles.any((x) => x.id == 903), isTrue);
      expect(c.table[0].tiles.any((x) => x.id == 900), isFalse);
      expect(c.rack.any((x) => x?.id == 900), isTrue);
      expect(c.rack.any((x) => x?.id == 903), isFalse);
      c.dispose();
    });

    test('son taş çekilip atılınca el biter', () {
      final c = make();
      c.deck.clear();
      c.deck.add(Tile(id: 950, number: 1, color: TileColor.red));
      // ilk elde sıra bende ve atma aşamasında: atınca deste boşsa el biter
      final t = c.rack.whereType<Tile>().firstWhere((x) => !c.okey.isWild(x));
      c.deck.clear();
      c.discard(t);
      expect(c.result, isNotNull);
      expect(c.result!.winner, isNull);
      c.dispose();
    });
  });

  group('kalıp taşıma + elde kalan puan', () {
    Tile t(int id, int n) => Tile(id: id, number: n, color: TileColor.blue);

    test('kalıp bütün olarak taşınır, hedefteki taşlar boşalan yuvalara yerleşir', () {
      final c = make();
      c.rack.fillRange(0, c.rack.length, null);
      final a = t(800, 4), b = t(801, 5), d = t(802, 6), x = t(803, 9);
      c.rack[0] = a;
      c.rack[1] = b;
      c.rack[2] = d;
      c.rack[3] = x; // hedefte duran başka taş
      // [0,1,2] kalıbını 1 sağa kaydır: yeni yuvalar [1,2,3]
      c.moveRackGroup([0, 1, 2], [1, 2, 3]);
      expect(c.rack.sublist(0, 4).map((e) => e?.id).toList(), [803, 800, 801, 802]);
      expect(c.rack.whereType<Tile>().length, 4); // taş kaybolmadı
      c.dispose();
    });

    test('kalıp diğer satıra taşınır, geçersiz istek yok sayılır', () {
      final c = make();
      c.rack.fillRange(0, c.rack.length, null);
      final cols = GameController.cols;
      c.rack[2] = t(810, 1);
      c.rack[3] = t(811, 2);
      c.moveRackGroup([2, 3], [cols + 2, cols + 3]);
      expect(c.rack[2], isNull);
      expect(c.rack[cols + 2]?.id, 810);
      expect(c.rack[cols + 3]?.id, 811);
      final before = c.rack.map((e) => e?.id).toList();
      c.moveRackGroup([cols + 2], [999]); // sınır dışı
      c.moveRackGroup([cols + 2, cols + 3], [cols + 3]); // uzunluk uyuşmaz
      expect(c.rack.map((e) => e?.id).toList(), before);
      c.dispose();
    });

    test('elde kalan puan: okey hariç sayı toplamı; çift açınca çarpan 2', () {
      final c = make();
      c.rack.fillRange(0, c.rack.length, null);
      c.rack[0] = t(820, 5);
      c.rack[1] = t(821, 7);
      final wild = c.okey;
      final expected = (wild.isWild(c.rack[0]!) ? 0 : 5) + (wild.isWild(c.rack[1]!) ? 0 : 7);
      expect(c.myHandValue, expected);
      expect(c.myHandMultiplier, 1);
      c.opened[0] = OpenMode.pairs;
      expect(c.myHandMultiplier, 2);
      c.dispose();
    });
  });

  group('katlamalı çift baraj', () {
    GameController mk({required bool folding}) => GameController(
        names: const ['Ben', 'Sağ', 'Üst', 'Sol'],
        settings: TableSettings(folding: folding),
        seed: 7);

    test('önceki çift açıştan 1 fazla, en az 5', () {
      final c = mk(folding: true);
      expect(c.requiredPairs(0), 5);
      c.opened[1] = OpenMode.pairs;
      c.openPairCount[1] = 6;
      expect(c.requiredPairs(0), 7);
      expect(c.requiredPairs(1), 5); // kendi açışı kendine baraj olmaz
      c.opened[2] = OpenMode.pairs;
      c.openPairCount[2] = 8;
      expect(c.requiredPairs(0), 9); // en yüksek açış baz alınır
      c.dispose();
    });
    test('katlamasız masada hep 5 çift', () {
      final c = mk(folding: false);
      c.opened[1] = OpenMode.pairs;
      c.openPairCount[1] = 6;
      expect(c.requiredPairs(0), 5);
      c.dispose();
    });
  });

  group('deste bitince / herkes çift açınca (sunucu kuralı)', () {
    GameController mk({int hands = 1, bool team = false}) => GameController(
        names: const ['Ben', 'Sağ', 'Üst', 'Sol'],
        settings: TableSettings(hands: hands, team: team),
        seed: 7);

    /// İlk elde sıra bende ve atma aşamasındadır: desteyi boşaltıp okey olmayan bir taş atınca el biter.
    void deckOut(GameController c) {
      c.deck.clear();
      final t = c.rack.whereType<Tile>().firstWhere((x) => !c.okey.isWild(x));
      c.discard(t);
    }

    test('tek elli oyunda kimse açmadıysa hükümsüz: puan ve XP yok', () {
      final c = mk();
      deckOut(c);
      expect(c.result, isNotNull);
      expect(c.result!.deckOut, isTrue);
      expect(c.result!.voided, isTrue);
      expect(c.voided, isTrue);
      expect(c.result!.delta, [0, 0, 0, 0]);
      expect(c.rankPoints(), [0, 0, 0, 0]);
      expect(c.winners, isEmpty);
      expect(c.myXp, 0);
      c.dispose();
    });

    test('çok elli oyunda kimse açmadıysa herkese +202, hükümsüz değil', () {
      final c = mk(hands: 3);
      deckOut(c);
      expect(c.result!.deckOut, isTrue);
      expect(c.result!.voided, isFalse);
      expect(c.result!.delta, [202, 202, 202, 202]);
      expect(c.totals, [202, 202, 202, 202]);
      c.dispose();
    });

    test('biri açtıysa: açmayan 202, açan elde kalan sayı (okey kalırsa +101)', () {
      final c = mk();
      c.opened[0] = OpenMode.series;
      c.deck.clear();
      final t = c.rack.whereType<Tile>().firstWhere((x) => !c.okey.isWild(x));
      c.discard(t);
      final r = c.result!;
      expect(r.deckOut, isTrue);
      expect(r.winner, isNull);
      final okeyLeft = c.myHand.any((x) => c.okey.isWild(x));
      expect(r.delta[0], c.myHandValue + (okeyLeft ? 101 : 0) + c.penalty[0]);
      expect(r.delta[1], 202 + c.penalty[1]);
      expect(r.delta[2], 202 + c.penalty[2]);
      expect(r.delta[3], 202 + c.penalty[3]);
      expect(c.voided, isFalse);
      c.dispose();
    });

    test('çift açan elde kalan sayının 2 katını yazar', () {
      final c = mk();
      c.opened[0] = OpenMode.pairs;
      c.opened[1] = OpenMode.series; // herkes çift açmadı: el deste bitince sona erer
      deckOut(c);
      final okeyLeft = c.myHand.any((x) => c.okey.isWild(x));
      expect(c.result!.delta[0],
          c.myHandValue * 2 + (okeyLeft ? 101 : 0) + c.penalty[0]);
      c.dispose();
    });

    test('lig puanı: eşli oyunda tam beraberlikte dört koltuk da 100', () {
      final c = mk(team: true);
      c.totals.setAll(0, [10, 10, 10, 10]);
      c.lastDelta = [0, 0, 0, 0];
      expect(c.championTeam, isNull);
      expect(c.winners, [0, 1, 2, 3]);
      expect(c.rankPoints(), [100, 100, 100, 100]);
      c.dispose();
    });
  });
}
