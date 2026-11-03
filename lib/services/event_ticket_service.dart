import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network_time_service.dart';

/// BILET SISTEMI (etkinlik basina ayri sayilir):
/// - Etkinlik basladiginda 3 UCRETSIZ bilet verilir (bir kere).
/// - Bilet biterse: "Reklam izle +1 bilet" butonu cikar.
/// - Reklam izlenince +1 bilet verilir VE 30 DAKIKALIK bekleme baslar.
/// - Bekleme bitmeden bir daha reklamla bilet alinamaz (spam engeli).
/// - PASIF/OTOMATIK yenilenme YOK — sadece reklamla kazanilir.
/// - Sunucu zamanina (NetworkTimeService) gore hesaplanir; telefon saatini
///   ileri/geri almak bekleme suresini kisaltamaz/uzatamaz (hile korumasi).
class EventTicketService extends ChangeNotifier {
  EventTicketService._();
  static final EventTicketService instance = EventTicketService._();

  static const int freeTicketsOnStart = 3;
  static const Duration adCooldown = Duration(minutes: 30);

  SharedPreferences? _prefs;
  Timer? _tick;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    // Cooldown bittiginde UI'nin otomatik guncellenmesi icin her 1 sn'de bir uyar.
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
  }

  String _ticketsKey(String eventId) => 'evt_tickets_${eventId}_v1';
  String _initKey(String eventId) => 'evt_tickets_init_${eventId}_v1';
  String _cooldownKey(String eventId) => 'evt_ad_cooldown_until_ms_${eventId}_v1';

  /// Etkinlik ilk acildiginda CAGIR: daha once baslatilmadiysa 3 ucretsiz bilet verir.
  /// Zaten baslatilmissa hicbir sey yapmaz (tekrar 3'e sifirlamaz).
  Future<void> ensureStarted(String eventId) async {
    await init();
    final p = _prefs!;
    if (p.getBool(_initKey(eventId)) == true) return;
    await p.setBool(_initKey(eventId), true);
    await p.setInt(_ticketsKey(eventId), freeTicketsOnStart);
    notifyListeners();
  }

  int ticketsRemaining(String eventId) => _prefs?.getInt(_ticketsKey(eventId)) ?? 0;

  /// Bir deneme (120sn tur) baslatmak icin 1 bilet harcar. Yetersizse false doner.
  Future<bool> consumeTicket(String eventId) async {
    await init();
    final cur = ticketsRemaining(eventId);
    if (cur <= 0) return false;
    await _prefs!.setInt(_ticketsKey(eventId), cur - 1);
    notifyListeners();
    return true;
  }

  /// Bekleme bitti mi (reklamla yeni bilet alinabilir mi)?
  bool canWatchAdForTicket(String eventId) => cooldownRemaining(eventId) <= Duration.zero;

  /// Kalan bekleme suresi (sifirsa/negatifse reklam izlenebilir demektir).
  Duration cooldownRemaining(String eventId) {
    final untilMs = _prefs?.getInt(_cooldownKey(eventId)) ?? 0;
    if (untilMs == 0) return Duration.zero;
    final nowMs = NetworkTimeService.instance.nowUtc().millisecondsSinceEpoch;
    final rem = untilMs - nowMs;
    return rem > 0 ? Duration(milliseconds: rem) : Duration.zero;
  }

  /// Reklam basariyla izlendikten SONRA cagir: +1 bilet verir, 30dk sayaci baslatir.
  /// Bekleme hala suruyorken cagrilirsa hicbir sey yapmaz (false doner) — UI zaten
  /// butonu gizlemeli ama ikinci bir guvenlik katmani olarak burada da kontrol var.
  Future<bool> grantTicketFromAd(String eventId) async {
    await init();
    if (!canWatchAdForTicket(eventId)) return false;
    final cur = ticketsRemaining(eventId);
    await _prefs!.setInt(_ticketsKey(eventId), cur + 1);
    final until = NetworkTimeService.instance.nowUtc().add(adCooldown).millisecondsSinceEpoch;
    await _prefs!.setInt(_cooldownKey(eventId), until);
    notifyListeners();
    return true;
  }

  /// Etkinlik bitince (sonuclar aciklanip yeni etkinlik baslamadan once) CAGIR:
  /// bilet/cooldown kayitlarini temizler, bir sonraki etkinlik tekrar 3 bilet versin diye.
  Future<void> resetForNextEvent(String eventId) async {
    await init();
    await _prefs!.remove(_ticketsKey(eventId));
    await _prefs!.remove(_initKey(eventId));
    await _prefs!.remove(_cooldownKey(eventId));
    notifyListeners();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}
