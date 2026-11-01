import 'package:flutter_test/flutter_test.dart';
import 'package:okey101/logic/game_controller.dart' show OpenMode;
import 'package:okey101/logic/scoring.dart';

void main() {
  const S = OpenMode.series, P = OpenMode.pairs;
  final none = List<int>.filled(4, 0);

  List<int> run({
    int winner = 0,
    bool joker = false,
    bool elden = false,
    bool team = false,
    required List<OpenMode?> opened,
    List<int>? hand,
    List<int>? penalty,
    List<bool>? okeyLeft,
  }) =>
      RoundScoring.compute(
        winner: winner,
        joker: joker,
        elden: elden,
        teamMode: team,
        opened: opened,
        handValues: hand ?? none,
        penalty: penalty ?? none,
        okeyLeft: okeyLeft,
      );

  test('normal bitiş: -101, seri açan x1, çift açan x2, açmayan 202', () {
    final d = run(opened: [S, S, P, null], hand: [0, 30, 20, 99]);
    expect(d, [-101, 30, 40, 202]);
  });

  test('okeyle bitiş: -202, seri x2, çift x4, açmayan 404', () {
    final d = run(joker: true, opened: [S, S, P, null], hand: [0, 30, 20, 99]);
    expect(d, [-202, 60, 80, 404]);
  });

  test('çiftle bitiş ayrı çarpan getirmez: kitapçık tablosu geçerli', () {
    final d = run(opened: [P, S, P, null], hand: [0, 30, 20, 99]);
    expect(d, [-101, 30, 40, 202]);
  });

  test('elden bitiş okeyle bitişle aynı sütundur: -202; açmayan 404; açan x2/x4', () {
    final d = run(elden: true, opened: [S, S, P, null], hand: [0, 30, 20, 99]);
    expect(d, [-202, 60, 80, 404]);
  });

  test('elden + okeyle bitiş tek kat sayılır', () {
    final d = run(elden: true, joker: true, opened: [S, null, null, null]);
    expect(d, [-202, 404, 404, 404]);
  });

  test('açmış oyuncunun elinde okey kalırsa +101 ekstra (okeyle bitişte +202)', () {
    final d = run(
        opened: [S, S, P, null],
        hand: [0, 30, 20, 99],
        okeyLeft: [false, true, true, true]);
    // açmayanın okeyi ayrıca yazılmaz
    expect(d, [-101, 131, 141, 202]);
    final j = run(
        joker: true,
        opened: [S, S, P, null],
        hand: [0, 30, 20, 99],
        okeyLeft: [false, true, true, true]);
    expect(j, [-202, 262, 282, 404]);
  });

  test('ceza her zaman sahibine yazılır', () {
    final d = run(opened: [S, S, S, S], hand: [0, 10, 10, 10], penalty: [101, 0, 202, 0]);
    expect(d, [0, 10, 212, 10]);
  });

  group('eşli oyun', () {
    test('bitirenin eşi ne ceza ne ödül alır', () {
      final d = run(team: true, opened: [S, S, S, null], hand: [0, 30, 50, 99]);
      // eş = koltuk 2; el değeri yazılmaz
      expect(d, [-101, 30, 0, 202]);
    });
    test('eşin kendi +101 cezası da silinir', () {
      final d = run(
          team: true,
          opened: [S, S, S, null],
          hand: [0, 30, 50, 99],
          penalty: [0, 0, 101, 0]);
      expect(d[2], 0);
    });
    test('eşli değilken eş normal ceza alır', () {
      final d = run(opened: [S, S, S, null], hand: [0, 30, 50, 99]);
      expect(d[2], 50);
    });
    test('açamayan rakip okeyle bitişte +404', () {
      final d = run(team: true, joker: true, opened: [S, S, S, null]);
      expect(d[3], 404);
    });
  });
}
