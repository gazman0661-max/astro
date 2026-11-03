import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../game/live_events_config.dart';
import 'localization.dart';
import 'network_time_service.dart';

/// Sunucusuz (backend'siz) yerel bildirim sistemi. Su turleri yonetir:
///
/// 1) "Kozmik Ikmal hazir" — oyuncu odulu topladiginda baslayan 2 saatlik
///    bekleme suresi dolunca tetiklenir (bkz. PlayerProgress.
///    grantResupplyReward).
/// 2) "Gunluk seri hatirlatmasi" — oyuncu o gun henuz oynamadiysa, GECE
///    RAHATSIZ ETMEMEK icin sabit bir sabah saatinde (10:00,
///    cihazin kendi saat dilimine gore) günde en fazla 1 kez gonderilir.
/// 3) "Geri cagirma" — oyuncu 3 gundur uygulamayi hic acmadiysa.
/// 4) "Kuyruklu Yildiz acildi" — periyodik event penceresi TAM olarak
///    acildigi anda (deterministik, herkeste ayni an) tetiklenir (bkz.
///    PlayerProgress.nextCometWindowOpen).
/// 5) "Haftalik/aylik gorev hatirlatmasi" — donem bitmeden (haftalikta
///    2, aylikta 3 gun once) hedef henuz tutturulmadiysa bir kez
///    hatirlatir; hedef tutturulup odul alinirsa hemen iptal edilir
///    (bkz. PlayerProgress.refreshPeriodicEventNotifications).
///
/// Tum bildirimler sabit bir ID kullanir (cancel + yeniden schedule),
/// boylece ayni bildirimden asla birden fazla kuyrukta kalmaz.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _resupplyNotificationId = 1001;
  static const _streakNotificationId = 2001;
  static const _comebackNotificationId = 3001;
  static const _cometNotificationId = 4001;
  static const _weeklyQuestNotificationId = 5001;
  static const _monthlyQuestNotificationId = 6001;
  static const _weeklyRuleNotificationId = 7001;

  /// Etkinlik baslangic/bitis bildirimleri: id = taban + tur*10 + tekrar*2 +
  /// (0 baslangic | 1 bitis). Her tur icin sonraki [_eventLookahead] tekrar
  /// onceden kurulur (uygulama bir hafta acilmasa da bildirim gelir).
  static const _eventNotificationBase = 8000;
  static const _eventLookahead = 2;

  /// Gunluk seri / etkinlik / gorev / haftalik kural bildirimlerinin
  /// gonderilecegi saat (24 saat formati). Oyuncunun BOLGESININ (saat
  /// dilimi) yerel saatine gore 10:00; "simdi" cihaz saatine DEGIL,
  /// internetten (NTP) alinan dogru zamana gore hesaplanir — boylece cihaz
  /// saatini degistirmek bildirim saatini oynatamaz.
  static const _sendHour = 10;

  /// Gece sessiz saatleri: yerel 00:00 - 09:00 arasina denk gelen hicbir
  /// bildirim gonderilmez; o gunun [_sendHour] saatine ertelenir.
  static const _quietEndHour = 9;

  /// "Geri cagirma" bildirimi, oyuncu uygulamayi acmadan bu kadar sure
  /// gecince gonderilir. Her acilista/resumed'de yeniden 3 gune
  /// ertelenir (bkz. refreshComebackReminder) — yani sadece GERCEKTEN
  /// 3 gundur hic acilmadiysa tetiklenir.
  static const _comebackAfter = Duration(days: 3);

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Future<void>? _initFuture;

  /// main() / splash_screen.dart boot akisinda, diger arka plan
  /// kurulumlarinin (ses, reklam SDK'si) yaninda cagirilir. Web'de ya da
  /// herhangi bir hata durumunda sessizce devre disi kalir — bildirimler
  /// olmadan da oyun tamamen calisir durumda kalmali. Ayni anda birden
  /// fazla yerden cagirilirsa (orn. resupply odulu + streak hatirlatmasi
  /// ayni anda tetiklenirse) tek bir init calismasini paylasir.
  Future<void> init() {
    return _initFuture ??= _doInit();
  }

  Future<void> _doInit() async {
    if (kIsWeb) return;
    try {
      tz_data.initializeTimeZones();
      final localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz.identifier));
    } catch (_) {
      // Cihaz saat dilimi alinamazsa UTC'ye duser; bildirim yine de
      // gonderilir, sadece saat hesaplamasi cihaz yerelinden sapabilir.
    }

    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _plugin.initialize(
        settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      );

      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();

      // NOT: DarwinInitializationSettings/DarwinNotificationDetails iOS ve
      // macOS icin ortak ayar siniflaridir, ancak resolvePlatformSpecific
      // Implementation icin hala platforma ozel sinif kullanilir: iOS icin
      // IOSFlutterLocalNotificationsPlugin (macOS icin ayrica
      // MacOSFlutterLocalNotificationsPlugin var).
      final iosImpl = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);

      _ready = true;
    } catch (e) {
      debugPrint('[NotificationService] init basarisiz: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Zaman yardimcilari (internet saati + bolge saat dilimi + sessiz saatler)
  // ---------------------------------------------------------------------

  /// Internetten (NTP) dogrulanmis "simdi", oyuncunun bolgesinin yerel saatinde.
  tz.TZDateTime _trueNow() =>
      tz.TZDateTime.from(NetworkTimeService.instance.nowUtc(), tz.local);

  /// [t] gece sessiz araligina (00:00-09:00) denk geliyorsa ayni gunun
  /// 10:00'una kaydirir; degilse oldugu gibi birakir.
  tz.TZDateTime _avoidQuietHours(tz.TZDateTime t) {
    if (t.hour < _quietEndHour) {
      return tz.TZDateTime(tz.local, t.year, t.month, t.day, _sendHour);
    }
    return t;
  }

  /// DOGRU (internet) zaman cizgisindeki bir ani, isletim sisteminin alarmi
  /// icin cihaz saatine cevirir (cihaz saati kaymis olsa bile bildirim
  /// gercekte hedeflenen anda calar).
  tz.TZDateTime _toDeviceClock(tz.TZDateTime trueTime) => tz.TZDateTime.from(
      trueTime.subtract(NetworkTimeService.instance.offset), tz.local);

  /// Kozmik Ikmal bildirimi: hazir olma ani sessiz saate denk gelirse
  /// o gunun 10:00'una ertelenir.
  tz.TZDateTime _resupplyTime(DateTime readyAt) {
    final trueReady = tz.TZDateTime.from(
        readyAt.toUtc().add(NetworkTimeService.instance.offset), tz.local);
    return _toDeviceClock(_avoidQuietHours(trueReady));
  }

  /// "Kozmik Ikmal" odulu toplandiginda cagirilir. [readyAt] tam olarak
  /// bekleme suresinin (2 saat) bitecegi zaman damgasidir.
  Future<void> scheduleResupplyReady(DateTime readyAt) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _resupplyNotificationId);
      await _plugin.zonedSchedule(
        id: _resupplyNotificationId,
        title: t('notif_resupplyTitle'),
        body: t('notif_resupplyBody'),
        scheduledDate: _resupplyTime(readyAt),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'resupply_channel',
            t('notifch_resupplyName'),
            channelDescription: t('notifch_resupplyDesc'),
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('[NotificationService] resupply schedule basarisiz: $e');
    }
  }

  /// Oyuncu Kozmik Ikmal odulunu bildirim gelmeden ONCE, uygulama
  /// icindeyken zaten aldiysa (normal akis) bekleyen bildirimi iptal eder.
  Future<void> cancelResupplyReady() async {
    await init();
    if (!_ready) return;
    await _plugin.cancel(id: _resupplyNotificationId);
  }

  /// Gunluk seri hatirlatmasini yeniden hesaplar/kurar. Su noktalarda
  /// cagirilmali: uygulama acilista (splash bitince), uygulama on plana
  /// donduğünde (resumed) ve gunluk bulmaca tamamlandiginda.
  ///
  /// [playedToday] true ise (bugunku gunluk bulmaca zaten tamamlandiysa)
  /// hatirlatma YARINKI 10:00'a ertelenir. False ise ve saat henuz
  /// 10:00'u gecmediyse BUGUN 10:00'a, gectiyse yine YARINA kurulur.
  Future<void> refreshDailyStreakReminder({required bool playedToday}) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _streakNotificationId);

      final now = _trueNow();
      var target =
          tz.TZDateTime(tz.local, now.year, now.month, now.day, _sendHour);
      final todayWindowPassed = now.isAfter(target);
      if (playedToday || todayWindowPassed) {
        target =
            tz.TZDateTime(tz.local, now.year, now.month, now.day + 1, _sendHour);
      }

      await _plugin.zonedSchedule(
        id: _streakNotificationId,
        title: t('notif_streakTitle'),
        body: t('notif_streakBody'),
        scheduledDate: _toDeviceClock(target),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_streak_channel',
            t('notifch_streakName'),
            channelDescription:
                t('notifch_streakDesc'),
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('[NotificationService] streak reminder basarisiz: $e');
    }
  }

  /// Geri cagirma bildirimini yeniden 3 gune erteler. Splash acilista
  /// VE uygulama on plana her donduğünde (didChangeAppLifecycleState ->
  /// resumed) cagrilmali — boylece oyuncu duzenli aciyorsa bildirim
  /// HICBIR ZAMAN tetiklenmez, sadece gercekten 3 gundur hic acmadiysa
  /// ("uzun sureli sessiz kullanici") gonderilir. Gunluk seri
  /// hatirlatmasindan (10:00, ayni gun icin) farkli olarak burada saat
  /// onemli degil, sadece "3 gun gecti mi" onemli.
  Future<void> refreshComebackReminder() async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _comebackNotificationId);
      final target = _avoidQuietHours(_trueNow().add(_comebackAfter));
      await _plugin.zonedSchedule(
        id: _comebackNotificationId,
        title: t('notif_comebackTitle'),
        body: t('notif_comebackBody'),
        scheduledDate: _toDeviceClock(target),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'comeback_channel',
            t('notifch_comebackName'),
            channelDescription:
                t('notifch_comebackDesc'),
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('[NotificationService] comeback reminder basarisiz: $e');
    }
  }

  /// [dateUtc]'nin sadece YIL/AY/GUN kismini alip cihazin YEREL saat
  /// diliminde _sendHour'a (10:00) oturtur. Bu an zaten gecmisse (ör.
  /// uygulama o gun/o an gec acildiysa, ya da donem bitmesine 2-3 gunden
  /// az kalmisken ilk kez kuruluyorsa) hatirlatma sessizce kaybolmasin
  /// diye "simdi + birkac dakika"ya kaydirilir.
  tz.TZDateTime _resolveReminderTime(DateTime dateUtc) {
    final now = _trueNow();
    var target = tz.TZDateTime(
      tz.local,
      dateUtc.year,
      dateUtc.month,
      dateUtc.day,
      _sendHour,
    );
    if (target.isBefore(now)) {
      target = _avoidQuietHours(now.add(const Duration(minutes: 5)));
    }
    return _toDeviceClock(target);
  }

  String _eventEmoji(EventKind k) => switch (k) {
        EventKind.cometRace => '☄️',
        EventKind.pointRace => '🎟️',
        EventKind.teamWar => '🌌',
      };

  /// TUM etkinliklerin (Kuyruklu Yildiz, Puan Toplama, Takimyildizi Savasi)
  /// BASLANGIC ve BITIS bildirimlerini kurar. Her etkinlik oyuncunun kilitli
  /// bolgesinde 10:00'da baslar/biter (bkz. EventClock); bildirim tam o anda
  /// calar. Cihazin yerel saatine gore gece sessiz araligina (00-09) denk
  /// gelirse o gunun 10:00'una ertelenir. Uygulama her acildiginda/on plana
  /// geldiginde yeniden kurulur (ayni id'ler uzerine yazilir).
  Future<void> refreshEventNotifications() async {
    await init();
    if (!_ready) return;
    try {
      // Eski surumun tek-bildirimli kuyruklu yildiz kaydini temizle.
      await _plugin.cancel(id: _cometNotificationId);
      final now = NetworkTimeService.instance.nowUtc();
      for (final kind in EventKind.values) {
        final occ = LiveEventDef.upcomingOccurrences(kind, now,
            count: _eventLookahead);
        for (var i = 0; i < _eventLookahead; i++) {
          final startId = _eventNotificationBase + kind.index * 10 + i * 2;
          final endId = startId + 1;
          await _plugin.cancel(id: startId);
          await _plugin.cancel(id: endId);
          if (i >= occ.length) continue;
          final ev = occ[i];
          final name = '${_eventEmoji(kind)} ${t(ev.titleKey)}';
          if (ev.startUtc.isAfter(now)) {
            await _scheduleEventNote(
              startId,
              t('notif_evtStartTitle', {'name': name}),
              t('notif_evtStartBody'),
              ev.startUtc,
            );
          }
          await _scheduleEventNote(
            endId,
            t('notif_evtEndTitle', {'name': name}),
            t('notif_evtEndBody'),
            ev.endUtc,
          );
        }
      }
    } catch (e) {
      debugPrint('[NotificationService] etkinlik bildirimleri basarisiz: $e');
    }
  }

  Future<void> _scheduleEventNote(
      int id, String title, String body, DateTime instantUtc) async {
    final local = tz.TZDateTime.from(instantUtc, tz.local);
    final target = _toDeviceClock(_avoidQuietHours(local));
    if (!target.isAfter(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: target,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'event_channel',
          t('notifch_eventName'),
          channelDescription:
              t('notifch_eventDesc'),
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Haftalık görev bu hafta içinde HENÜZ tamamlanmadıysa, hafta bitmeden
  /// [remindOnUtc] gününde (saat _sendHour = 10:00, bolge yereli) bir kez
  /// hatırlatır. Hedef tutturulup ödül alınırsa (bkz. PlayerProgress.
  /// refreshPeriodicEventNotifications) cancelWeeklyQuestReminder ile
  /// hemen iptal edilir.
  Future<void> scheduleWeeklyQuestReminder(DateTime remindOnUtc) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _weeklyQuestNotificationId);
      await _plugin.zonedSchedule(
        id: _weeklyQuestNotificationId,
        title: t('notif_weeklyQuestTitle'),
        body: t('notif_weeklyQuestBody'),
        scheduledDate: _resolveReminderTime(remindOnUtc),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'weekly_quest_channel',
            t('notifch_weeklyQuestName'),
            channelDescription:
                t('notifch_weeklyQuestDesc'),
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('[NotificationService] weekly quest reminder basarisiz: $e');
    }
  }

  /// Her Pazartesi 10:00 (yerel saat) tekrar eden "yeni haftalik kural"
  /// bildirimi. Metin sabit (kural adi icermez); acilista/devam ederken
  /// yeniden kurulur, boylece tek bir zamanlanmis kayit kalir.
  Future<void> scheduleWeeklyRuleNotice() async {
    await init();
    if (!_ready) return;
    try {
      final now = _trueNow();
      var target =
          tz.TZDateTime(tz.local, now.year, now.month, now.day, _sendHour);
      while (target.weekday != DateTime.monday || !target.isAfter(now)) {
        target = tz.TZDateTime(
            tz.local, target.year, target.month, target.day + 1, _sendHour);
      }
      await _plugin.cancel(id: _weeklyRuleNotificationId);
      await _plugin.zonedSchedule(
        id: _weeklyRuleNotificationId,
        title: t('notif_weeklyRuleTitle'),
        body: t('notif_weeklyRuleBody'),
        scheduledDate: _toDeviceClock(target),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'weekly_rule_channel',
            t('notifch_weeklyRuleName'),
            channelDescription:
                t('notifch_weeklyRuleDesc'),
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    } catch (e) {
      debugPrint('[NotificationService] weekly rule notice basarisiz: $e');
    }
  }

  Future<void> cancelWeeklyQuestReminder() async {
    await init();
    if (!_ready) return;
    await _plugin.cancel(id: _weeklyQuestNotificationId);
  }

  /// scheduleWeeklyQuestReminder ile birebir ayni mantik, sadece aylik
  /// donem/kanal/metin uzerinden.
  Future<void> scheduleMonthlyQuestReminder(DateTime remindOnUtc) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _monthlyQuestNotificationId);
      await _plugin.zonedSchedule(
        id: _monthlyQuestNotificationId,
        title: t('notif_monthlyQuestTitle'),
        body: t('notif_monthlyQuestBody'),
        scheduledDate: _resolveReminderTime(remindOnUtc),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'monthly_quest_channel',
            t('notifch_monthlyQuestName'),
            channelDescription:
                t('notifch_monthlyQuestDesc'),
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint(
          '[NotificationService] monthly quest reminder basarisiz: $e');
    }
  }

  Future<void> cancelMonthlyQuestReminder() async {
    await init();
    if (!_ready) return;
    await _plugin.cancel(id: _monthlyQuestNotificationId);
  }
}
