import 'package:flutter_test/flutter_test.dart';
import 'package:okey101/services/telemetry.dart';

class _Fake implements TelemetryBackend {
  final bool failInit;
  final bool throwOnCall;
  final List<String> events = [];
  final List<Object> errors = [];
  _Fake({this.failInit = false, this.throwOnCall = false});

  @override
  Future<void> init() async {
    if (failInit) throw StateError('google-services.json yok');
  }

  @override
  void event(String name, [Map<String, Object>? params]) {
    if (throwOnCall) throw StateError('patladı');
    events.add(name);
  }

  @override
  void error(Object error, StackTrace? stack, {bool fatal = false}) {
    if (throwOnCall) throw StateError('patladı');
    errors.add(error);
  }
}

void main() {
  setUp(Telemetry.reset);

  test('varsayılan Noop: hiçbir çağrı fırlatmaz', () async {
    await Telemetry.init();
    Telemetry.event('masa_kur');
    Telemetry.error('x', null);
    expect(Telemetry.active, isFalse);
  });

  test('init başarısız olursa (json yok) sessizce kapanır, sonraki çağrılar güvenli', () async {
    final f = _Fake(failInit: true);
    Telemetry.use(f);
    await Telemetry.init(); // fırlatmamalı
    expect(Telemetry.active, isFalse);
    Telemetry.event('masa_kur');
    Telemetry.error('x', null);
    expect(f.events, isEmpty);
    expect(f.errors, isEmpty);
  });

  test('init başarılıysa olay ve hata arka uca gider', () async {
    final f = _Fake();
    Telemetry.use(f);
    await Telemetry.init();
    expect(Telemetry.active, isTrue);
    Telemetry.event('gunluk_odul');
    Telemetry.error('boom', null);
    expect(f.events, ['gunluk_odul']);
    expect(f.errors, ['boom']);
  });

  test('arka uç çağrıda patlarsa oyun etkilenmez', () async {
    Telemetry.use(_Fake(throwOnCall: true));
    await Telemetry.init();
    Telemetry.event('masa_kur'); // fırlatmamalı
    Telemetry.error('x', null, fatal: true);
  });

  test('oturum başına hata sınırı: fırtınada raporlanan sayı sınırlı, ölümcül hata yine geçer', () async {
    final f = _Fake();
    Telemetry.use(f);
    await Telemetry.init();
    for (var i = 0; i < Telemetry.maxErrorsPerSession + 50; i++) {
      Telemetry.error('e$i', null);
    }
    expect(f.errors.length, Telemetry.maxErrorsPerSession);
    Telemetry.error('ölümcül', null, fatal: true);
    expect(f.errors.length, Telemetry.maxErrorsPerSession + 1);
  });
}
