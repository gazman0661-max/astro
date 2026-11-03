import 'dart:math';

import 'package:timezone/timezone.dart' as tz;

import 'event_bots.dart';
import 'event_clock.dart';

/// Etkinlik turu.
enum EventKind {
  /// Kuyruklu Yildiz Yarisi: PASIF puan, normal oyun oynarken otomatik birikir
  /// (mevcut "kuyruklu yildiz" mantigi gibi, suresi 2 gune cikti).
  cometRace,

  /// Puan Toplama Yarisi: BILETLI, her giris 120 saniyelik ayri bir tur.
  /// Turlardan alinan puanlar TOPLANIR (kumulatif).
  pointRace,

  /// Takimyildizi Savasi: Kara Delik Firtinasi turlari (120 sn, BILETLI:
  /// Puan Toplama ile ayni bilet sistemi). Oyuncu bir takimyildizi secer;
  /// turdan gelen puan takimin toplamina eklenir. Rakip takimlar botlardan olusur.
  teamWar,
}

class EventRewardTier {
  final int minRank; // dahil
  final int maxRank; // dahil (son basamak icin 999999 kullan)
  final int meteors;
  final int boosters;
  const EventRewardTier(this.minRank, this.maxRank, this.meteors, this.boosters);
}

/// Siralamali etkinliklerde (Kuyruklu Yildiz, Puan Toplama) bot sayisi.
/// 99 bot + oyuncu = ekranda gorunen ILK 100.
const int kLeaderboardBots = 99;

/// Liderlik ekraninda gosterilen en fazla satir sayisi (ilk 100).
const int kLeaderboardRows = 100;

class LiveEventDef {
  /// TEK KAYNAK: etkinlik dongusunun basladigi an. Baska hicbir dosyada bu
  /// tarihi TEKRAR YAZMA, hep buradan (LiveEventDef.cycleStartUtc) oku —
  /// yoksa "hangi etkinlik su an acik" hesaplari dosyalar arasinda kayabilir.
  ///
  /// v30: HAFTALIK takvim, OYUNCUNUN YEREL SAATIYLE. Her etkinlik yerel
  /// [startHourLocal] (10:00) baslar ve 48 saat surer. Referans: yerel
  /// Pazartesi 2026-10-26 10:00 (hafta bloklari buradan 7'ser gun ilerler).
  /// Getter: cihazin saat dilimine gore her cagrida yeniden hesaplanir.
  static const int startHourLocal = 10;
  ///
  /// v33: "yerel" = EventClock'un KILITLI saat dilimi (ilk acilista kaydedilir);
  /// cihazin saat dilimini sonradan degistirmek takvimi kaydirmaz.
  static DateTime get cycleStartUtc =>
      _utc(tz.TZDateTime(EventClock.location, 2026, 10, 26, startHourLocal));

  static DateTime _utc(DateTime d) =>
      DateTime.fromMillisecondsSinceEpoch(d.millisecondsSinceEpoch, isUtc: true);

  /// Haftalik takvim (yerel 10:00), hepsi 48 saat: Kuyruklu Yildiz Pzt-Sal,
  /// Puan Toplama (biletli) Car-Per, Takimyildizi Savasi (biletli) Cmt-Paz.
  /// Sadece Cuma gunu etkinlik yok.
  static const int weekDays = 7;
  static const int cometStartDay = 0; // Pazartesi
  static const int pointStartDay = 2; // Carsamba (Car 10:00 -> Cum 10:00)
  static const int teamStartDay = 5; // Cumartesi (Cmt 10:00 -> Pzt 10:00)
  final String id; // ornek: 'comet_2026_w44'
  final EventKind kind;
  final String titleKey;
  final String descKey;
  final DateTime startUtc;
  final Duration duration; // 2 gun
  final int botCount;
  final List<EventRewardTier> rewards;

  /// Sadece pointRace icin: tek tur suresi.
  final Duration attemptDuration;

  const LiveEventDef({
    required this.id,
    required this.kind,
    required this.titleKey,
    required this.descKey,
    required this.startUtc,
    this.duration = const Duration(days: 2),
    this.botCount = 60,
    this.rewards = const [
      EventRewardTier(1, 1, 300, 5),
      EventRewardTier(2, 2, 200, 4),
      EventRewardTier(3, 3, 150, 3),
      EventRewardTier(4, 10, 80, 2),
      EventRewardTier(11, 50, 30, 1),
      EventRewardTier(51, 999999, 10, 0),
    ],
    this.attemptDuration = const Duration(seconds: 120),
  });

  DateTime get endUtc => startUtc.add(duration);

  /// Puan Toplama ve Takimyildizi Savasi BILETLIDIR (3 ucretsiz, sonra reklam +1,
  /// 30 dk'da bir). Kuyruklu Yildiz pasiftir, bilet yok.
  bool get usesTickets => kind != EventKind.cometRace;
  bool isActive(DateTime nowUtc) => !nowUtc.isBefore(startUtc) && nowUtc.isBefore(endUtc);
  double elapsedHours(DateTime nowUtc) =>
      nowUtc.difference(startUtc).inMinutes / 60.0;

  static const _kindOrder = [EventKind.cometRace, EventKind.pointRace, EventKind.teamWar];

  static int _startDayOf(EventKind k) => switch (k) {
        EventKind.cometRace => cometStartDay,
        EventKind.teamWar => teamStartDay,
        EventKind.pointRace => pointStartDay,
      };

  static String _prefixOf(EventKind k) => switch (k) {
        EventKind.cometRace => 'comet',
        EventKind.teamWar => 'team',
        EventKind.pointRace => 'point',
      };

  /// [cycleStartUtc]'nin yerel takvim gununden [days] gun sonrasi, yerel 10:00.
  /// (DateTime(...) yerel kurucusu yaz/kis saati gecislerini kendisi halleder.)
  static DateTime _localStart(DateTime cycleStartUtc, int days) {
    final loc = EventClock.location;
    final c = tz.TZDateTime.from(cycleStartUtc, loc);
    return _utc(tz.TZDateTime(loc, c.year, c.month, c.day + days, startHourLocal));
  }

  /// Haftalik etkinlik: [weekIndex]. haftanin [kind] etkinligi.
  static LiveEventDef _build(EventKind kind, int weekIndex, DateTime cycleStartUtc) {
    final p = _prefixOf(kind);
    return LiveEventDef(
      id: '${p}_$weekIndex',
      kind: kind,
      titleKey: 'event_${p}_title',
      descKey: 'event_${p}_desc',
      startUtc: _localStart(
          cycleStartUtc, weekIndex * weekDays + _startDayOf(kind)),
      // v32: siralamali etkinliklerde liste ILK 100 kisi gosterir (99 bot +
      // oyuncu = tam 100 satir). Takimyildizi Savasi 60 bot (3x20) kalir:
      // takim puani dengesi (teamBotScale) 20 botluk takima gore ayarli.
      botCount: kind == EventKind.teamWar ? 60 : kLeaderboardBots,
    );
  }

  /// Etkinlik takvimi (v29, haftalik): Kuyruklu Yildiz Pzt-Sal, Puan Toplama
  /// Car-Per, Takimyildizi Savasi Cmt-Paz (her biri 48 saat). Ayni anda ikisi
  /// birden acik olmaz.
  ///
  /// SU AN ACIK etkinligi dondurur; hicbiri acik degilse (Cuma) SIRADAKINI
  /// dondurur — bu durumda [isActive] false'tur, arayuz "X sonra basliyor"
  /// gostermeli, bilet/puan islemi YAPMAMALI.
  static LiveEventDef current(DateTime nowUtc, DateTime cycleStartUtc) {
    final week = (nowUtc.difference(cycleStartUtc).inMinutes / (24 * 60 * weekDays)).floor();
    // Hafta siniri yaz/kis saati yuzunden +-1 saat kayabilir; bu yuzden
    // onceki haftanin Takimyildizi Savasi da aday (Pzt 10:00'a kadar surer).
    final candidates = <LiveEventDef>[
      _build(EventKind.teamWar, week - 1, cycleStartUtc),
      for (final k in _kindOrder) _build(k, week, cycleStartUtc),
      _build(EventKind.cometRace, week + 1, cycleStartUtc),
    ];
    for (final e in candidates) {
      if (e.isActive(nowUtc)) return e;
    }
    for (final e in candidates) {
      if (e.startUtc.isAfter(nowUtc)) return e;
    }
    return candidates.last;
  }

  /// [kind] etkinliginin, [nowUtc] aninda henuz BITMEMIS en yakin [count]
  /// tekrari (su an aciksa o da dahil), baslangic sirasiyla. Bildirim
  /// planlamasi icin (baslangic + bitis).
  static List<LiveEventDef> upcomingOccurrences(EventKind kind, DateTime nowUtc,
      {int count = 2}) {
    final c = cycleStartUtc;
    final week =
        (nowUtc.difference(c).inMinutes / (24 * 60 * weekDays)).floor();
    final out = <LiveEventDef>[];
    for (var w = week - 1; w <= week + count + 1 && out.length < count; w++) {
      final e = _build(kind, w, c);
      if (e.endUtc.isAfter(nowUtc)) out.add(e);
    }
    return out;
  }

  /// [ev]'den hemen ONCE biten etkinlik (odul toplama icin geriye yuruyus).
  /// Takimyildizi Savasi -> ayni haftanin Puan Toplamasi; Puan Toplama -> ayni
  /// haftanin Kuyruklu Yildizi; Kuyruklu Yildiz -> onceki haftanin Takimyildizi
  /// Savasi.
  static LiveEventDef previousOf(LiveEventDef ev, DateTime cycleStartUtc) {
    // +12 saat payi: yaz/kis saati kaymasi gunu sinirdan tasimasin.
    final week = ((ev.startUtc.difference(cycleStartUtc).inHours + 12) / (24 * weekDays)).floor();
    return switch (ev.kind) {
      EventKind.teamWar => _build(EventKind.pointRace, week, cycleStartUtc),
      EventKind.pointRace => _build(EventKind.cometRace, week, cycleStartUtc),
      EventKind.cometRace => _build(EventKind.teamWar, week - 1, cycleStartUtc),
    };
  }

  // ---- Kuyruklu Yildiz penceresi (PlayerProgress bunu kullanir; tek kaynak) ----

  /// [nowUtc] anina denk gelen (ya da en son baslamis) kuyruklu yildiz haftasi.
  static int cometWeekAt(DateTime nowUtc) {
    final c = cycleStartUtc;
    var w = (nowUtc.difference(c).inMinutes / (24 * 60 * weekDays)).floor();
    while (_build(EventKind.cometRace, w + 1, c).startUtc.compareTo(nowUtc) <= 0) {
      w++;
    }
    while (_build(EventKind.cometRace, w, c).startUtc.isAfter(nowUtc)) {
      w--;
    }
    return w;
  }

  /// [nowUtc] icin kuyruklu yildiz etkinligi (acik olan ya da son baslamis).
  static LiveEventDef cometAt(DateTime nowUtc) =>
      _build(EventKind.cometRace, cometWeekAt(nowUtc), cycleStartUtc);

  /// Sonraki kuyruklu yildiz etkinligi.
  static LiveEventDef cometAfter(DateTime nowUtc) =>
      _build(EventKind.cometRace, cometWeekAt(nowUtc) + 1, cycleStartUtc);

  /// Takimyildizi Savasi odulleri: TAKIM sirasina gore (1-3) + takim ici
  /// KISISEL katkiya gore. Ikisi toplanir.
  static const List<EventRewardTier> teamRewards = [
    EventRewardTier(1, 1, 250, 4),
    EventRewardTier(2, 2, 120, 2),
    EventRewardTier(3, 3, 60, 1),
  ];
  static const List<EventRewardTier> teamPersonalRewards = [
    EventRewardTier(1, 1, 100, 2),
    EventRewardTier(2, 3, 60, 1),
    EventRewardTier(4, 10, 30, 1),
    EventRewardTier(11, 999999, 10, 0),
  ];
}

/// Takimyildizi Savasi takimlari.
class EventTeam {
  final int index;
  final String nameKey;
  final String emoji;
  final int color; // ARGB
  const EventTeam(this.index, this.nameKey, this.emoji, this.color);
}

class EventTeams {
  EventTeams._();
  static const List<EventTeam> all = [
    EventTeam(0, 'team_sun', '🔥', 0xFFF59E0B),
    EventTeam(1, 'team_moon', '🌙', 0xFF60A5FA),
    EventTeam(2, 'team_star', '⭐', 0xFFA78BFA),
  ];
  static int get count => all.length;
}

/// Bir takimin toplam puani.
class TeamStanding {
  final EventTeam team;
  final double score;
  final bool isPlayerTeam;
  const TeamStanding(this.team, this.score, this.isPlayerTeam);
}

/// Botlardan + oyuncudan olusan tek bir siralama satiri.
class EventStanding {
  final bool isPlayer;
  final String name;
  final BotProfile? profile;
  final double score;
  const EventStanding({required this.isPlayer, required this.name, this.profile, required this.score});
}

/// SIRALAMA AYARI (v23): botlar OYUNCUDAN BAGIMSIZ.
///
/// Her botun etkinlik SONUNDAKI puani, asagidaki "sira -> guc" tablosundan
/// gelir ve oyuncunun puanina hic bakmaz. Oyuncunun sirasi = puaninin botlar
/// arasindaki yeri. Yani iyi oynayan gercekten yukari cikar.
///
/// ZORLUK EGRISI bu tablodur: guc, "ortalama bir oyuncunun kac tur / kac
/// hedef karsiligi" puan yaptigi olarak yazilir. Ornek (Puan Toplama):
///   - 3 ucretsiz tur oynayan ortalama oyuncu  -> ~10. sira
///   - 5 tur -> ~6-7. sira,  8 tur -> ~3. sira,  13+ tur -> 1. sira
/// Beceri iyiyse ayni turla daha yukari, kotuyse asagi. Tabloyu degistirmek
/// zorlugu degistirir; botlar zaten oyuncudan bagimsiz oldugu icin baska
/// hicbir seye dokunmak gerekmez.
class EventTuning {
  EventTuning._();

  /// !!! KALIBRE ET !!! Ortalama bir oyuncunun 120 sn'lik BIR TURDA yaptigi
  /// puan. Gercek degeri bul: bir kac oyun-ici tur oyna, ya da cihazdaki
  /// `evt_points_<id>_v1 / evt_attempts_<id>_v1` degerine bak.
  /// Bu sayi botlarin puan olcegini belirler (tablo x bu sayi).
  static const double pointRoundScore = 500;

  /// !!! KALIBRE ET !!! Takimyildizi Savasi'nda bot puanlarinin carpani.
  /// Dusuk = oyuncunun katkisi takim sirasini daha cok etkiler. Bot takim
  /// toplami ~ (20 bot x ortalama guc x pointRoundScore) x bu carpan.
  static const double teamBotScale = 0.8;

  /// Takim gucleri arasi +-% sapma (hangi takimin onde oldugu etkinlige gore degisir).
  static const double teamJitter = 0.10;

  /// Kuyruklu Yildiz'da birim = 1 hedef.
  static const double cometUnit = 1;

  /// Bot sirasi (1 = en guclu) -> guc. Aradaki siralar log-dogrusal
  /// interpolasyonla bulunur. Puan Toplama: birim = ortalama tur.
  static const List<(int rank, double power)> pointAnchors = [
    (1, 13.0), (2, 9.5), (3, 8.0), (4, 7.0), (5, 6.2), (6, 5.5), (7, 4.9),
    (8, 4.4), (10, 3.0), (15, 2.2), (20, 1.7), (30, 1.1), (40, 0.7),
    (50, 0.45), (60, 0.25), (80, 0.12), (99, 0.06),
  ];

  /// Kuyruklu Yildiz: birim = ulasilan hedef sayisi (en az 1'e sabitlenir).
  static const List<(int rank, double power)> cometAnchors = [
    (1, 14.0), (2, 11.0), (3, 9.0), (4, 7.5), (5, 6.5), (6, 5.7), (7, 5.0),
    (8, 4.4), (10, 3.4), (15, 2.6), (20, 2.0), (30, 1.4), (40, 1.0),
    (60, 1.0), (99, 1.0),
  ];

  /// Her botun gucune kosuya ozgu +-%10 oynama (etkinlikler birbirine benzemesin).
  static const double jitter = 0.10;

  /// [rank]. (1 = en guclu) botun gucu; tablo noktalari arasi log-dogrusal.
  static double powerAtRank(List<(int rank, double power)> anchors, int rank) {
    if (rank <= anchors.first.$1) return anchors.first.$2;
    if (rank >= anchors.last.$1) return anchors.last.$2;
    for (var i = 1; i < anchors.length; i++) {
      final a = anchors[i - 1], b = anchors[i];
      if (rank <= b.$1) {
        final t = (rank - a.$1) / (b.$1 - a.$1);
        return exp(log(a.$2) + (log(b.$2) - log(a.$2)) * t);
      }
    }
    return anchors.last.$2;
  }
}

/// Sabit (surumler/cihazlar arasi ayni) metin hash'i — String.hashCode'a
/// guvenme, Dart surumune gore degisebilir.
int stableHash(String s) {
  var h = 0x811C9DC5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 16777619) & 0x7FFFFFFF;
  }
  return h;
}

/// Bir botun etkinlik SONUNDAKI puani (oyuncudan bagimsiz, deterministik).
double botFinalScore(LiveEventDef event, int botIndex, int botCount) {
  final isComet = event.kind == EventKind.cometRace;
  final rank = botCount - botIndex; // botIndex 0 = en yavas -> en kotu sira
  final power = EventTuning.powerAtRank(
      isComet ? EventTuning.cometAnchors : EventTuning.pointAnchors, rank);
  final j = Random(stableHash('${event.id}#j$botIndex')).nextDouble();
  final mul = 1.0 + (j * 2 - 1) * EventTuning.jitter;
  final unit = isComet ? EventTuning.cometUnit : EventTuning.pointRoundScore;
  final v = power * unit * mul;
  return isComet ? max(1.0, v) : max(10.0, v);
}

/// Verilen etkinlik icin siralamayi SU ANA GORE uretir (deterministik).
/// [playerScore]: oyuncunun su ana kadarki toplam puani (pointRace: turlarin
/// toplami; cometRace: ulasilan hedef sayisi).
///
/// Botlar oyuncunun puanina BAKMAZ. Sira, oyuncunun puaninin botlar arasindaki
/// yeridir; esit puanda (puan > 0) oyuncu onde, puani 0 ise en sonda.
List<EventStanding> _buildBots(LiveEventDef event, DateTime nowUtc) {
  final seed = stableHash(event.id);
  final rnd = Random(seed);
  final used = <String>{};
  final hours = event.duration.inHours;
  final elapsed = event.elapsedHours(nowUtc).clamp(0.0, hours.toDouble()).toDouble();
  final isComet = event.kind == EventKind.cometRace;
  final n = event.botCount;

  final list = <EventStanding>[];
  for (var i = 0; i < n; i++) {
    final fast01 = n <= 1 ? 1.0 : i / (n - 1); // 0 (yavas) .. 1 (hizli)
    final profile = makeBotProfile(rnd, used, fast01: fast01);
    final finalScore = botFinalScore(event, i, n);
    var s = botScoreAtHour(seed, i, finalScore, elapsed,
        awakeAdj: profile.awakeAdj, startHour: LiveEventDef.startHourLocal, eventHours: hours);
    if (isComet) s = s.floorToDouble(); // hedef sayisi tam sayi
    list.add(EventStanding(isPlayer: false, name: profile.name, profile: profile, score: s));
  }
  return list;
}

List<EventStanding> buildStandings(
  LiveEventDef event,
  DateTime nowUtc,
  double playerScore,
) {
  final list = _buildBots(event, nowUtc);
  list.add(EventStanding(isPlayer: true, name: 'player', score: playerScore));
  list.sort((a, b) {
    final c = b.score.compareTo(a.score);
    if (c != 0) return c;
    // Esitlikte: puani olan oyuncu onde, 0 ise botlar onde.
    if (a.isPlayer != b.isPlayer) {
      final playerFirst = playerScore > 0;
      return (a.isPlayer == playerFirst) ? -1 : 1;
    }
    return 0;
  });
  return list;
}

// ---------------------------------------------------------------------------
// Takimyildizi Savasi (EventKind.teamWar)
// ---------------------------------------------------------------------------

/// Botun takimi (guclu/zayif botlar takimlara dengeli bolunur).
int botTeamOf(int botIndex) {
  // Yilan dagitimi (0,1,2,2,1,0,...): takimlarin bot gucu birbirine yakin kalir.
  final block = botIndex ~/ EventTeams.count;
  final pos = botIndex % EventTeams.count;
  return block.isEven ? pos : EventTeams.count - 1 - pos;
}

/// Takimin bot gucu carpani (etkinlige ozgu +-teamJitter, deterministik).
double _teamPower(LiveEventDef event, int team) {
  final j = Random(stableHash('${event.id}#team$team')).nextDouble();
  return EventTuning.teamBotScale * (1.0 + (j * 2 - 1) * EventTuning.teamJitter);
}

/// Takim ici uyeler (botlar + oyuncu), puana gore sirali. Bot puanlari
/// oyuncudan BAGIMSIZDIR.
List<EventStanding> buildTeamMembers(
  LiveEventDef event,
  DateTime nowUtc,
  int team,
  double playerScore,
) {
  final bots = _buildBots(event, nowUtc);
  final mul = _teamPower(event, team);
  final list = <EventStanding>[
    for (var i = 0; i < bots.length; i++)
      if (botTeamOf(i) == team)
        EventStanding(
            isPlayer: false,
            name: bots[i].name,
            profile: bots[i].profile,
            score: (bots[i].score * mul).floorToDouble()),
    EventStanding(isPlayer: true, name: 'player', score: playerScore),
  ];
  list.sort((a, b) {
    final c = b.score.compareTo(a.score);
    if (c != 0) return c;
    if (a.isPlayer != b.isPlayer) return (a.isPlayer == (playerScore > 0)) ? -1 : 1;
    return 0;
  });
  return list;
}

/// Takim siralamasi (toplam puana gore, buyukten kucuge). [playerTeam]: oyuncunun
/// takimi (null = henuz secmedi, katki eklenmez).
List<TeamStanding> buildTeamStandings(
  LiveEventDef event,
  DateTime nowUtc,
  int? playerTeam,
  double playerScore,
) {
  final bots = _buildBots(event, nowUtc);
  final totals = List<double>.filled(EventTeams.count, 0);
  for (var i = 0; i < bots.length; i++) {
    final t = botTeamOf(i);
    totals[t] += (bots[i].score * _teamPower(event, t)).floorToDouble();
  }
  if (playerTeam != null) totals[playerTeam] += playerScore;
  final list = [
    for (final t in EventTeams.all)
      TeamStanding(t, totals[t.index], playerTeam == t.index),
  ]..sort((a, b) => b.score.compareTo(a.score));
  return list;
}

// küçük yardımcı: BotIdentity.make çağrısını kısaltmak için
BotProfile makeBotProfile(Random r, Set<String> used, {double fast01 = -1}) =>
    BotIdentity.make(r, used, fast01: fast01);
