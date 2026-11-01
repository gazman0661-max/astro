import 'package:flutter_test/flutter_test.dart';
import 'package:okey101/models/rewards.dart';
import 'package:okey101/models/table_models.dart';
import 'package:okey101/services/game_service.dart';
import 'package:okey101/services/mock_game_service.dart';

void main() {
  test('bilet sabitleri sunucuyla aynı: günlük 2, reklam 10 dk', () {
    expect(kDailyTickets, 2);
    expect(kAdTicketCooldown, const Duration(minutes: 10));
  });

  test('TicketStatus / TicketClaim sunucu JSON\'undan okunur', () {
    final s = TicketStatus.fromJson({
      'tickets': 4, 'max': 10, 'ad_wait_seconds': 120, 'daily_can_claim': true, 'daily_amount': 2,
      'xp': 80, 'league_points': 60,
    });
    expect([s.tickets, s.adWaitSeconds, s.dailyCanClaim, s.xp, s.leaguePoints], [4, 120, true, 80, 60]);
    final c = TicketClaim.fromJson({'amount': 1, 'tickets': 5, 'wait_seconds': 600});
    expect([c.amount, c.tickets, c.waitSeconds], [1, 5, 600]);
  });

  test('günlük bilet: 2, reklamla 4, günde bir kez, tavan yok', () async {
    final s = MockGameService();
    s.tickets = 3;
    final a = await s.claimDailyTickets();
    expect([a.amount, a.tickets], [2, 5]);
    expect(() => s.claimDailyTickets(), throwsA(isA<JoinException>()));
    final s2 = MockGameService()..tickets = 10;
    final b = await s2.claimDailyTickets(doubled: true);
    expect([b.amount, b.tickets], [4, 14]); // 10 bilet varken de eklenir
  });

  test('reklam bileti: +1, 10 dakika bekleme, 10 bilet varken de verilir', () async {
    final s = MockGameService()..tickets = 3;
    final a = await s.claimAdTicket();
    expect([a.amount, a.tickets, a.waitSeconds], [1, 4, 600]);
    expect(() => s.claimAdTicket(), throwsA(isA<JoinException>())); // bekleme
    final ten = MockGameService()..tickets = 10;
    final b = await ten.claimAdTicket();
    expect([b.amount, b.tickets], [1, 11]);
  });

  test('masa kurmak ve oturmak bilet düşürmez; bilet oyun BAŞLARKEN (beginMatch) düşer', () async {
    final s = MockGameService()..tickets = 3;
    final t = await s.createTable(name: 'x', settings: const TableSettings());
    expect(s.tickets, 3); // kurmak bedava
    await s.joinTable(tableId: t.id);
    expect(s.tickets, 3); // oturmak bedava (geri sayımda çıkan hiçbir şey kaybetmez)
    await s.beginMatch(); // geri sayım bitti, oyun başlıyor
    expect(s.tickets, 2);
  });

  test('TEKRAR OYNA: her yeni oyun 1 bilet, bilet yoksa masadan atılır (JoinException)', () async {
    final s = MockGameService()..tickets = 2;
    final t = await s.createTable(name: 'x', settings: const TableSettings());
    await s.joinTable(tableId: t.id);
    await s.beginMatch(); // 1. oyun
    expect(s.tickets, 1);
    await s.joinTable(quick: const TableSettings()); // tekrar oyna = yeni oturuş
    await s.beginMatch(); // 2. oyun
    expect(s.tickets, 0);
    expect(() => s.joinTable(quick: const TableSettings()), throwsA(isA<JoinException>())); // 3. oyun: bilet yok
    expect(() => s.beginMatch(), throwsA(isA<JoinException>()));
    expect(s.tickets, 0); // eksiye düşmez
  });

  test('masada reklamla bilet: 10 dk sınırı yok, yalnız kısa ara ve günlük sınır', () async {
    final s = MockGameService()..tickets = 0;
    final a = await s.claimTableAdTicket();
    expect([a.amount, a.tickets, a.waitSeconds], [1, 1, kTableAdGap.inSeconds]);
    // anasayfadaki 10 dk sayacı ayrı: masadaki reklam onu başlatmaz
    final lobby = await s.claimAdTicket();
    expect(lobby.tickets, 2);
    // art arda hemen ikinci talep: 30 sn ara dolmadan reddedilir (10 dk beklenmez, 30 sn yeter)
    expect(() => s.claimTableAdTicket(), throwsA(isA<JoinException>()));
    expect(s.tickets, 2);
  });

  test('bileti olmayan masa kuramaz ve oturamaz', () async {
    final s = MockGameService()..tickets = 0;
    expect(() => s.createTable(name: 'x', settings: const TableSettings()), throwsA(isA<JoinException>()));
    expect(() => s.joinTable(tableId: 't1'), throwsA(isA<JoinException>()));
    expect(s.tickets, 0);
  });

  test('seviye eğrisi: L → L+1 için 100×L XP, toplam 50×L×(L-1)', () {
    expect([for (var l = 2; l <= 6; l++) xpForLevel(l)], [100, 300, 600, 1000, 1500]);
    expect(xpForLevel(10), 4500);
    expect(xpForLevel(11), 5500);
    expect(xpForLevel(50), 122500);
    expect([0, 99, 100, 299, 300, 599, 600].map(levelOfXp).toList(), [1, 1, 2, 2, 3, 3, 4]);
    expect(levelOfXp(122499), 49);
    expect(levelOfXp(122500), 50);
  });

  test('TicketStatus: bekleyen seviye hediyesi ve ilerleme çubuğu', () {
    final s = TicketStatus.fromJson({
      'tickets': 3, 'ad_wait_seconds': 0, 'daily_can_claim': false,
      'xp': 450, 'level': 3, 'level_claimed': 1,
    });
    expect(s.pendingLevels, 2); // 2. ve 3. seviye hediyeleri bekliyor
    expect(s.levelProgress, closeTo((450 - 300) / 300, 1e-9));
    final none = TicketStatus.fromJson({'tickets': 0, 'xp': 0, 'level': 1, 'level_claimed': 1});
    expect(none.pendingLevels, 0);
  });

  test('seviye hediyesi: her atlanan seviye 1 bilet, çifte alınamaz', () async {
    final s = MockGameService()..tickets = 1;
    s.xp = 650; // seviye 4 (600+)
    final st = await s.fetchTicketStatus();
    expect([st.level, st.pendingLevels], [4, 3]);
    final r = await s.claimLevelRewards();
    expect([r.amount, r.tickets, r.level], [3, 4, 4]);
    expect(() => s.claimLevelRewards(), throwsA(isA<JoinException>()));
    s.xp = 1000; // seviye 5: 1 yeni hediye
    final r2 = await s.claimLevelRewards();
    expect([r2.amount, r2.tickets], [1, 5]);
  });
}
