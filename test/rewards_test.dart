import 'package:flutter_test/flutter_test.dart';
import 'package:okey101/models/rewards.dart';
import 'package:okey101/services/game_service.dart';
import 'package:okey101/services/mock_game_service.dart';

void main() {
  test('günlük ödül tablosu: 2000 ... 4000', () {
    expect([for (var d = 1; d <= 7; d++) dailyAmount(d)],
        [2000, 2250, 2500, 2750, 3000, 3500, 4000]);
    expect(kAdChips, 4000);
    expect(kAdCooldown, const Duration(minutes: 15));
  });

  test('gün sırası: 7. günde kalır (başa dönmez)', () {
    expect(nextDay(1), 2);
    expect(nextDay(6), 7);
    expect(nextDay(7), 7);
  });

  test('sahte servis: günlük ödül günde bir kez, 2x iki katı', () async {
    final s = MockGameService();
    final before = s.chipCount;
    final st = await s.fetchDailyStatus();
    expect(st.canClaim, isTrue);
    expect(st.day, 1);
    expect(st.amount, 2000);
    final c = await s.claimDaily(doubled: true);
    expect(c.amount, 4000);
    expect(s.chipCount, before + 4000);
    expect((await s.fetchDailyStatus()).canClaim, isFalse);
    expect(() => s.claimDaily(), throwsA(isA<JoinException>()));
  });

  test('sahte servis: reklam çipi 4000, 15 dk bekletir', () async {
    final s = MockGameService();
    final before = s.chipCount;
    expect((await s.fetchAdStatus()).waitSeconds, 0);
    final r = await s.claimAdChips();
    expect(r.waitSeconds, 900);
    expect(s.chipCount, before + 4000);
    expect((await s.fetchAdStatus()).waitSeconds, greaterThan(0));
    expect(() => s.claimAdChips(), throwsA(isA<JoinException>()));
  });
}
