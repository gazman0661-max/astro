/// Kara Delik Firtinasi (Takimyildizi Savasi etkinligi) — tahtada gecici bir
/// kara delik acilir: once UYARI halkasi, sonra aktif (komsulari ceker, kucuk
/// gezegenleri YUTAR). Aktifken deligin cekim alaninda yapilan birlesmeler
/// 2 KATI puan verir. Sadece [PlanetMergeWorld.blackHoles] acikken calisir.
class BlackHoleConfig {
  BlackHoleConfig._();

  /// Oyun basladiktan kac sn sonra ilk kara delik uyarisi.
  static const double firstDelay = 8.0;

  /// Bir delik kapandiktan sonra sonraki uyariya kadar bekleme (sn).
  static const double interval = 12.0;

  /// Uyari suresi (delik henuz cekmez/yutmaz) ve aktif sure (sn).
  static const double warnSeconds = 1.6;
  static const double activeSeconds = 5.0;

  /// Delik yaricapi ve cekim alani (govde yuzeyinden, dunya birimi).
  static const double radius = 7.0;
  static const double pullReach = 36.0;

  /// Cekim ivmesi (singularityAccel ile ayni mertebe).
  static const double pullAccel = 100.0;

  /// Bu kademe ve altindaki gezegenler deligin icine girince yutulur.
  static const int eatMaxTier = 2;

  /// Cekim alaninda yapilan birlesmelerin puan carpani.
  static const int bonusMult = 2;
}

class BlackHole {
  final double x, y;
  double age = 0;
  BlackHole(this.x, this.y);

  double get total => BlackHoleConfig.warnSeconds + BlackHoleConfig.activeSeconds;

  /// Uyari bitti, delik cekiyor/yutuyor.
  bool get armed => age >= BlackHoleConfig.warnSeconds;

  /// 0..1 uyari ilerlemesi (1 = aktif).
  double get warnT =>
      (age / BlackHoleConfig.warnSeconds).clamp(0.0, 1.0).toDouble();

  /// Kapanmaya kalan sure (sn).
  double get remaining => total - age;
}

enum HoleEventKind { warn, open, eat, close, bonus }

class HoleEvent {
  final HoleEventKind kind;
  final double x, y;
  final int tier; // eat: yutulan gezegenin kademesi
  const HoleEvent(this.kind, this.x, this.y, [this.tier = 0]);
}
