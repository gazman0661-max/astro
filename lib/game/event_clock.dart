import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Etkinlik takviminin (LiveEventDef) kullandigi KILITLI saat dilimi.
///
/// Etkinlikler oyuncunun yerel 10:00'unda baslar. Ama "yerel"i cihazin o anki
/// saat dilimine baglarsak, saat dilimini degistiren biri bitmis bir etkinligi
/// yeniden acabilir ya da suresini uzatabilir. Bu yuzden saat dilimi ILK
/// acilista (internet/NTP zamani degil, cihazin o andaki bolgesi) diske
/// KAYDEDILIR ve bundan sonra hep o kullanilir: sonradan saat dilimini
/// degistirmek etkinlik pencerelerini KAYDIRMAZ. Yaz/kis saati (DST) yine
/// dogru islenir, cunku sabit bir bolge adi (orn. Europe/Istanbul) saklanir.
///
/// [init] splash'te (LiveEventDef kullanilmadan once) beklenmelidir.
class EventClock {
  EventClock._();

  static const String _prefsKey = 'event_tz_lock_v1';
  static tz.Location _location = tz.UTC;
  static Future<void>? _initFuture;

  /// Etkinlik takviminin kullandigi (kilitli) saat dilimi.
  static tz.Location get location => _location;

  static Future<void> init() => _initFuture ??= _doInit();

  static bool _exists(String name) {
    try {
      tz.getLocation(name);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _doInit() async {
    try {
      // Saat dilimi veritabani henuz yuklenmediyse yukle (NotificationService
      // de yukler; ikisi de zararsiz).
      if (!_exists('UTC')) tz_data.initializeTimeZones();

      final prefs = await SharedPreferences.getInstance();
      var name = prefs.getString(_prefsKey);
      if (name == null || !_exists(name)) {
        name = 'UTC';
        if (!kIsWeb) {
          final info = await FlutterTimezone.getLocalTimezone();
          if (_exists(info.identifier)) name = info.identifier;
        }
        await prefs.setString(_prefsKey, name);
      }
      _location = tz.getLocation(name);
    } catch (_) {
      // Alinamazsa UTC ile devam et (kaydedilmedi: sonraki acilista tekrar dener).
      _location = tz.UTC;
    }
  }

  @visibleForTesting
  static void setLocationForTest(tz.Location l) => _location = l;
}
