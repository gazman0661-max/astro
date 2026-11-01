import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:okey101/models/nick_words.dart';
import 'package:okey101/models/profile.dart';
import 'package:okey101/services/auth_service.dart';
import 'package:okey101/services/profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('takma ad: serbest yazı yok, kelime listesi', () {
    test('liste geçerli: benzersiz, harf, en çok 11 karakter (ad en çok 16)', () {
      final seen = <String>{};
      for (final w in kNickWords) {
        expect(w.length, lessThanOrEqualTo(11), reason: w);
        expect(RegExp(r'^[A-Za-zÇĞİÖŞÜçğıöşüÂâÎîÛû]+$').hasMatch(w), isTrue, reason: w);
        expect(seen.add(w.toLowerCase()), isTrue, reason: 'tekrar: $w');
        expect('${w}_9999'.length, lessThanOrEqualTo(16), reason: w);
      }
      expect(kNickWords.length, greaterThan(100));
    });
    test('kayıtlı addan kelime sırası bulunur', () {
      final i = kNickWords.indexOf('Kartal');
      expect(nickWordIndex('Kartal_4821'), i);
      expect(nickWordIndex('Kartal'), i);
      expect(nickWordIndex('Bilinmeyen_1234'), isNull);
      expect(nickWordIndex('Oyuncu'), isNull);
    });
    test('sunucu hata kodları Türkçe karşılık bulur', () {
      expect(profileErrorText('gecersiz_isim'), contains('Listeden'));
      expect(profileErrorText('ad_sik_degisti'), contains('haftada'));
      expect(profileErrorText('bilinmeyen'), contains('kaydedilemedi'));
    });
  });

  group('LocalProfileService', () {
    test('kaydet + yükle: ad = kelime + 4 haneli sayı', () async {
      SharedPreferences.setMockInitialValues({});
      final s = LocalProfileService();
      expect((await s.load()).named, isFalse);
      final w = kNickWords.indexOf('Kartal');
      final p = await s.save(word: w, avatar: 5);
      expect(p.name, matches(RegExp(r'^Kartal_[0-9]{4}$')));
      final again = await LocalProfileService().load();
      expect(again.name, p.name);
      expect(again.avatar, 5);
      expect(again.named, isTrue);
    });
    test('aynı kelime yeniden seçilirse sayı korunur; yalnız avatar değişir', () async {
      SharedPreferences.setMockInitialValues({});
      final s = LocalProfileService();
      final w = kNickWords.indexOf('Kartal');
      final p = await s.save(word: w, avatar: 1);
      final q = await s.save(word: w, avatar: 2);
      expect(q.name, p.name);
      final r = await s.save(word: null, avatar: 3);
      expect(r.name, p.name);
      expect(r.avatar, 3);
    });
    test('isim seçilmeden ya da geçersiz sırayla kaydedilemez', () async {
      SharedPreferences.setMockInitialValues({});
      expect(() => LocalProfileService().save(word: null, avatar: 0), throwsA(isA<ProfileException>()));
      expect(() => LocalProfileService().save(word: 99999, avatar: 0), throwsA(isA<ProfileException>()));
    });
  });

  group('GuestAuthService', () {
    String tokenBody(String uid) => jsonEncode({
          'access_token': 'tok-$uid',
          'expires_in': 3600,
          'user': {'id': uid}
        });

    test('hesap yoksa açar, sonra aynı oturumu önbellekten verir', () async {
      SharedPreferences.setMockInitialValues({});
      final calls = <String>[];
      final emails = <String>[];
      final client = MockClient((req) async {
        calls.add(req.url.path);
        emails.add((jsonDecode(req.body) as Map)['email'] as String);
        if (req.url.path.endsWith('/token')) {
          return http.Response('{"error_code":"invalid_credentials"}', 400);
        }
        return http.Response(tokenBody('u1'), 200);
      });
      final a = GuestAuthService(
          supabaseUrl: 'https://x.supabase.co', anonKey: 'k', guestDomain: 'test.dev', client: client);
      expect(await a.accessToken(), 'tok-u1');
      expect(a.userId, 'u1');
      expect(calls, ['/auth/v1/token', '/auth/v1/signup']);
      expect(emails.first, matches(RegExp(r'^g-[0-9a-f]{32}@test\.dev$')));
      expect(emails.first, emails.last); // aynı cihaz = aynı e-posta
      await a.accessToken(); // önbellek: yeni istek yok
      expect(calls.length, 2);
    });

    test('hesap varsa doğrudan girer (kayıt açmaz)', () async {
      SharedPreferences.setMockInitialValues({});
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add(req.url.path);
        return http.Response(tokenBody('u2'), 200);
      });
      final a = GuestAuthService(
          supabaseUrl: 'https://x.supabase.co', anonKey: 'k', guestDomain: 'test.dev', client: client);
      expect(await a.accessToken(), 'tok-u2');
      expect(calls, ['/auth/v1/token']);
    });

    test('e-posta onayı açıksa anlaşılır hata verir', () async {
      SharedPreferences.setMockInitialValues({});
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/token')) return http.Response('{}', 400);
        return http.Response(jsonEncode({'id': 'u3'}), 200); // oturum yok
      });
      final a = GuestAuthService(
          supabaseUrl: 'https://x.supabase.co', anonKey: 'k', guestDomain: 'test.dev', client: client);
      expect(a.accessToken(), throwsA(isA<AuthException>()));
    });

    test('aynı anda gelen çağrılar tek giriş yapar', () async {
      SharedPreferences.setMockInitialValues({});
      var n = 0;
      final client = MockClient((req) async {
        n++;
        return http.Response(tokenBody('u4'), 200);
      });
      final a = GuestAuthService(
          supabaseUrl: 'https://x.supabase.co', anonKey: 'k', guestDomain: 'test.dev', client: client);
      await Future.wait([a.accessToken(), a.accessToken(), a.accessToken()]);
      expect(n, 1);
    });
  });
}
