import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/ad_service.dart';
import '../services/app_update_service.dart';
import '../services/analytics_service.dart';
import '../services/cloud_progress_sync.dart';
import '../services/gdpr_service.dart';
import '../services/haptic_service.dart';
import '../game/event_clock.dart';
import '../services/localization.dart';
import '../services/network_time_service.dart';
import '../services/notification_service.dart';
import '../services/planet_images.dart';
import '../services/play_games_service.dart';
import '../services/player_progress.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';
import 'language_select_screen.dart';

/// Galaxy Puzzle acilis ekrani: gulen Uranus gezegeni (yuzen, isildayan),
/// etrafinda donen mini gezegenler, parlayan yildiz tozu + kayan yildiz,
/// ışıltılı "Galaxy Puzzle" basligi ve slogan. Yukleme bitince ana ekrana
/// geciyor.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// Surekli donen animasyon (yildizlar, yuzme, yorunge, baslik isiltisi).
  late final AnimationController _loop;

  /// Acilista bir kez calisan giris animasyonu (gezegen buyuyerek gelir).
  late final AnimationController _intro;

  late final List<_Star> _stars;
  bool _navigated = false;
  bool _ready = false;

  static const List<String> _orbitPlanets = [
    'assets/planets/1_earth.png',
    'assets/planets/5_mars.png',
    'assets/planets/7_pink.png',
    'assets/planets/9_neptune.png',
  ];

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
    final rnd = math.Random(42);
    _stars = List.generate(
      120,
      (_) => _Star(
        x: rnd.nextDouble(),
        y: rnd.nextDouble(),
        radius: 0.5 + rnd.nextDouble() * 1.6,
        phase: rnd.nextDouble(),
        cycles: 1 + rnd.nextInt(3),
      ),
    );
    // DUZELTME (v10): Ses/reklam SDK'si kurulumu ARTIK ana gecis akisini
    // (_boot -> _goHome) hicbir sekilde BEKLEMIYOR / BLOKLAMIYOR. Ikisi de
    // bagimsiz olarak, paralel calisiyor. Boylece reklam SDK'si yavas/
    // sorunlu olsa bile oyuncu splash'te fazladan beklemez, direkt ana
    // menuye gecer; reklamlar arka planda kendi hazirlanir.
    unawaited(_bootAudioAndAds());
    _boot();
  }

  /// Ses sistemini kurar ve (varsa) reklam SDK'sini baslatir. Bu islemler
  /// navigasyonu ETKILEMEZ — main.dart artik runApp()'i hicbir sey
  /// beklemeden en basta cagiriyor (native acilis ikonu aninda kayboluyor),
  /// bu metod ise Flutter arayuzu ZATEN EKRANDAYKEN arka planda calisir.
  Future<void> _bootAudioAndAds() async {
    unawaited(HapticService.instance.init());
    try {
      await SoundService.instance.init().timeout(
            const Duration(seconds: 5),
            onTimeout: () {},
          );
    } catch (_) {
      // Ses sistemi kurulamasa bile oyun etkilenmesin.
    }
    // Yerel bildirim sistemi (Kozmik Ikmal hazir / gunluk seri
    // hatirlatmasi) de navigasyonu bloklamayan arka plan kurulumlarindan
    // biri. Basarisiz olursa oyun bildirimsiz calismaya devam eder.
    try {
      await NotificationService.instance.init().timeout(
            const Duration(seconds: 5),
            onTimeout: () {},
          );
    } catch (_) {}
    // Play'de yeni surum varsa tam ekran zorunlu "Guncelle" penceresi (sadece
    // Play'den kurulu surumde; hata olursa sessizce atlanir). Navigasyonu
    // bloklamaz, sadece reklam SDK'sinin baslamasi bunu bekler.
    if (!kIsWeb) {
      try {
        await AppUpdateService.instance.check();
      } catch (_) {}
    }
    // Appodeal Mobile Ads SDK sadece Android/iOS icindir. Web'de (orn.
    // FlutLab "preview" veya "flutter run -d chrome") native eklenti
    // bulunamadigi icin bu cagri hata firlatir; try/catch ile sarmalaniyor.
    if (!kIsWeb) {
      try {
        // AdService.initializeSdk(): Appodeal SDK'sini kurar VE (AB/AEA/
        // Isvicre/UK/CCPA bolgesindeyse) Appodeal'in KENDI resmi/otomatik
        // onay ekranini (Google UMP tabanli Stack Consent Manager)
        // tetikler — bkz. ad_service.dart.
        await AdService.instance.initializeSdk().timeout(
              const Duration(seconds: 8),
              onTimeout: () {},
            );
        // Kullanim Sartlari onayi / bolge tespiti (Appodeal'den bagimsiz,
        // kendi yerel Terms/Privacy akisimiz icin) — GDPR popup'i ana
        // ekranda (henuz onaylanmadiysa) ayrica gosterilir.
        await GdprService.instance.load().timeout(
              const Duration(seconds: 3),
              onTimeout: () {},
            );
        // Ilk odullu + ilk gecis (interstitial) reklam isteginin
        // beklemeden gosterilebilmesi icin arka planda onceden yuklemeyi
        // baslat (hata olursa sessizce yutulur; AdService.preload() /
        // preloadInterstitial() zaten kendi icinde tekrar deniyor).
        unawaited(AdService.instance.preload());
        unawaited(AdService.instance.preloadInterstitial());
      } catch (_) {
        // Reklam SDK'si baslatilamasa bile oyun asla etkilenmesin.
      }
      // Firebase Analytics — Appodeal panelinde gorunmeyen yeni/eski
      // kullanici ve reklam izleme detaylarini Firebase Console'a
      // gonderir. Diger tum kurulumlar gibi navigasyonu BLOKLAMAZ ve
      // google-services.json eksikse (henuz eklenmediyse) sessizce
      // atlanir, oyun Analytics olmadan normal calismaya devam eder.
      try {
        await AnalyticsService.instance.init().timeout(
              const Duration(seconds: 5),
              onTimeout: () {},
            );
      } catch (_) {}
    }
  }

  Future<void> _boot() async {
    final loadFuture = PlayerProgress.instance.load();
    final localeFuture = AppLocale.instance.load();
    final planetsFuture = PlanetImages.preload();
    // Haftalik gorev sinirlarinin (bkz. NetworkTimeService) diskteki en
    // son bilinen offset ile hazir olmasi icin — gercek NTP sorgusu
    // kendi icinde arka planda devam eder, burasi BEKLEMEZ/BLOKLAMAZ.
    final ntpFuture = NetworkTimeService.instance.init();
    // Etkinlik takviminin kilitli saat dilimi (LiveEventDef'ten ONCE hazir olmali).
    final clockFuture = EventClock.init();
    await Future.wait([
      clockFuture,
      loadFuture,
      localeFuture,
      planetsFuture,
      ntpFuture,
      Future.delayed(const Duration(milliseconds: 2800)),
    ]);
    // Yerel ilerleme yuklendikten SONRA Play Games'e sessizce baglanmayi
    // dene; basariliysa buluttaki (varsa) daha ileri kaydi uygula.
    await PlayGamesService.instance.signInSilently();
    if (PlayGamesService.instance.isSignedIn) {
      await CloudProgressSync.instance.syncAfterSignIn();
    }
    // Gunluk seri hatirlatmasini, ilerleme yuklendikten hemen sonra
    // (bugun oynanip oynanmadigi artik bilindigi icin) yeniden kur.
    // NotificationService kendi init'ini gerekirse burada tamamlar,
    // navigasyonu (_goHome) BEKLEMEDEN arka planda calisir.
    unawaited(NotificationService.instance.refreshDailyStreakReminder(
      playedToday: PlayerProgress.instance.dailyCompletedToday,
    ));
    // Uygulama acildi: "3 gundur ugramadin" geri cagirma bildirimini de
    // simdiden 3 gun ileriye ertele.
    unawaited(NotificationService.instance.refreshComebackReminder());
    unawaited(NotificationService.instance.scheduleWeeklyRuleNotice());
    // Kuyruklu Yıldız / haftalık / aylık görev bildirimlerini de acilista
    // guncel ilerlemeyle kur (bkz. PlayerProgress.
    // refreshPeriodicEventNotifications).
    unawaited(PlayerProgress.instance.refreshPeriodicEventNotifications());
    _ready = true;
    _goHome();
  }

  void _goHome() {
    if (_navigated || !mounted) return;
    _navigated = true;
    final needsLanguage = !AppLocale.instance.hasChosenLanguage;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => needsLanguage
            ? const LanguageSelectScreen()
            : const HomeScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _loop.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final heroSize = math.min(size.width * 0.78, 330.0);
    final boxW = heroSize * 1.3;
    final boxH = heroSize * 1.15;

    return Scaffold(
      backgroundColor: AppColors.spaceTop,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_ready) _goHome();
        },
        child: AnimatedBuilder(
          animation: Listenable.merge([_loop, _intro]),
          builder: (context, _) {
            final tt = _loop.value; // 0..1, kesintisiz dongu
            final intro = Curves.easeOutBack.transform(_intro.value);
            final introFade = Curves.easeOut.transform(_intro.value);
            final titleT = ((_intro.value - 0.35) / 0.65).clamp(0.0, 1.0).toDouble();
            final titleEase = Curves.easeOutCubic.transform(titleT);
            final twoPi = 2 * math.pi;

            final float = math.sin(twoPi * tt) * 8;
            final tilt = math.sin(twoPi * tt) * 0.025;
            final pulse = 0.5 + 0.5 * math.sin(twoPi * tt * 2);

            // Basligin uzerinden gecen isilti seridi.
            final sweep = (tt * 2) % 1.0;
            final c = sweep * 1.8 - 0.4;
            final titleGradient = LinearGradient(
              colors: const [
                Color(0xFF7DD3FC),
                Color(0xFF7DD3FC),
                Colors.white,
                Color(0xFFF0ABFC),
                Color(0xFFF0ABFC),
              ],
              stops: [
                0.0,
                (c - 0.18).clamp(0.0, 1.0).toDouble(),
                c.clamp(0.0, 1.0).toDouble(),
                (c + 0.18).clamp(0.0, 1.0).toDouble(),
                1.0,
              ],
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                // Derin uzay gradyani
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF05061A),
                        Color(0xFF160B38),
                        Color(0xFF0A1A44),
                      ],
                    ),
                  ),
                ),
                // Nebula parlamalari
                Align(
                  alignment: const Alignment(-1.0, -0.6),
                  child: _glowBlob(const Color(0xFF7C3AED),
                      size.width * 0.9, 0.22 + 0.06 * pulse),
                ),
                Align(
                  alignment: const Alignment(1.1, 0.7),
                  child: _glowBlob(const Color(0xFF06B6D4),
                      size.width * 0.9, 0.18 + 0.05 * (1 - pulse)),
                ),
                // Yildizlar + kayan yildiz
                CustomPaint(
                  painter: _StarfieldPainter(progress: tt, stars: _stars),
                  size: Size.infinite,
                ),
                SafeArea(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: boxW,
                          height: boxH,
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              // Gezegenin arkasindaki nefes alan isik
                              Opacity(
                                opacity: introFade,
                                child: _glowBlob(
                                  const Color(0xFF38BDF8),
                                  heroSize * 1.05,
                                  0.30 + 0.14 * pulse,
                                ),
                              ),
                              // Yorungede, gezegenin ARKASINDAN gecen mini gezegenler
                              ..._orbiters(tt, boxW, boxH, introFade,
                                  front: false),
                              // Gulen Uranus
                              Transform.translate(
                                offset: Offset(0, float),
                                child: Transform.rotate(
                                  angle: tilt,
                                  child: Transform.scale(
                                    scale: (0.55 + 0.45 * intro)
                                        .clamp(0.0, 1.2).toDouble(),
                                    child: Opacity(
                                      opacity: introFade,
                                      child: Image.asset(
                                        'assets/splash/uranus_hero.png',
                                        width: heroSize,
                                        height: heroSize,
                                        filterQuality: FilterQuality.high,
                                        gaplessPlayback: true,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Gezegenin ONUNDEN gecen mini gezegenler
                              ..._orbiters(tt, boxW, boxH, introFade,
                                  front: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Opacity(
                          opacity: titleEase,
                          child: Transform.translate(
                            offset: Offset(0, 18 * (1 - titleEase)),
                            child: ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: (rect) =>
                                  titleGradient.createShader(rect),
                              child: const Text(
                                'Galaxy Puzzle',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 40,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                  shadows: [
                                    Shadow(
                                      color: Color(0x887C5CFF),
                                      blurRadius: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Opacity(
                          opacity: titleEase * (0.75 + 0.25 * pulse),
                          child: Text(
                            t('splashTagline'),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 15,
                              letterSpacing: 2.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 36),
                        Opacity(
                          opacity: titleEase,
                          child: SizedBox(
                            width: 190,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: const LinearProgressIndicator(
                                backgroundColor: Color(0x33FFFFFF),
                                valueColor: AlwaysStoppedAnimation(
                                    Color(0xFF7DD3FC)),
                                minHeight: 5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _glowBlob(Color color, double diameter, double alpha) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha.clamp(0.0, 1.0).toDouble()),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }

  /// Gezegenin etrafinda eliptik yorungede donen mini gezegenler.
  /// [front] true ise yorungenin on yarisindakiler (gezegenin ustunde),
  /// false ise arka yarisindakiler (gezegenin arkasinda) cizilir.
  List<Widget> _orbiters(double tt, double boxW, double boxH, double fade,
      {required bool front}) {
    final widgets = <Widget>[];
    final rx = boxW * 0.5 - 6;
    final ry = rx * 0.30;
    final cx = boxW / 2;
    final cy = boxH / 2 + boxH * 0.12;
    for (var i = 0; i < _orbitPlanets.length; i++) {
      final a = 2 * math.pi * (tt + i / _orbitPlanets.length);
      final depth = math.sin(a); // >0: on, <0: arka
      final isFront = depth > 0;
      if (isFront != front) continue;
      final x = math.cos(a) * rx;
      final y = depth * ry;
      final sz = 30.0 + 12.0 * (0.5 + 0.5 * depth);
      widgets.add(
        Positioned(
          left: cx + x - sz / 2,
          top: cy + y - sz / 2,
          child: Opacity(
            opacity: (fade * (isFront ? 1.0 : 0.65)).clamp(0.0, 1.0).toDouble(),
            child: Image.asset(
              _orbitPlanets[i],
              width: sz,
              height: sz,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}

class _Star {
  final double x;
  final double y;
  final double radius;
  final double phase;
  final int cycles;
  const _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.phase,
    required this.cycles,
  });
}

/// Parildayan yildiz tozu + periyodik olarak gecen iki kayan yildiz.
class _StarfieldPainter extends CustomPainter {
  final double progress;
  final List<_Star> stars;
  _StarfieldPainter({required this.progress, required this.stars});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final s in stars) {
      final tw = 0.5 +
          0.5 * math.sin(2 * math.pi * (progress * s.cycles + s.phase));
      paint.color = Colors.white.withValues(alpha: 0.18 + 0.82 * tw);
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.radius * (0.8 + 0.4 * tw),
        paint,
      );
    }

    // Kayan yildizlar: dongunun farkli anlarinda baslar.
    _shootingStar(canvas, size, (progress * 2 + 0.05) % 1.0,
        const Offset(0.95, 0.08), const Offset(0.45, 0.30));
    _shootingStar(canvas, size, (progress * 2 + 0.55) % 1.0,
        const Offset(0.75, 0.55), const Offset(0.15, 0.80));
  }

  void _shootingStar(
      Canvas canvas, Size size, double s, Offset from, Offset to) {
    const window = 0.14;
    if (s > window) return;
    final p = s / window;
    final a = Offset(from.dx * size.width, from.dy * size.height);
    final b = Offset(to.dx * size.width, to.dy * size.height);
    final head = Offset.lerp(a, b, p)!;
    final tail = Offset.lerp(a, b, (p - 0.28).clamp(0.0, 1.0).toDouble())!;
    final fade = math.sin(p * math.pi);
    final rect = Rect.fromPoints(tail, head);
    final line = Paint()
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.9 * fade),
        ],
      ).createShader(rect.inflate(1));
    canvas.drawLine(tail, head, line);
    canvas.drawCircle(
        head, 2.4, Paint()..color = Colors.white.withValues(alpha: fade));
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter old) =>
      old.progress != progress;
}
