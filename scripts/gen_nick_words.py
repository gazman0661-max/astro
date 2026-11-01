#!/usr/bin/env python3
# Takma ad kelime listesi TEK yerde: burası. Çalıştır: python3 scripts/gen_nick_words.py
# Üretir: lib/models/nick_words.dart ve okey101-server/supabase/migration-011.sql (+ schema.sql sonuna eklenmez, elle bkz. YAPILACAKLAR)
# KURAL: var olan sıranın ORTASINA ekleme/silme YAPMA (oyuncuların seçimi sıra numarasıyla tutulmaz ama
# Dart ve SQL listesi AYNI sırada olmalı). Yeni kelimeyi SONA ekle, sonra iki dosyayı da yeniden üret.
# Her kelime en fazla 11 karakter (ad = kelime + "_" + 4 hane = en fazla 16).
WORDS = """
Kartal Şahin Doğan Atmaca Pars Vaşak Ceylan Kuğu Turna Leylek Serçe Bülbül Kırlangıç Martı Yunus Balina
Gelincik Papatya Lale Sümbül Menekşe Yasemin Nergis Zambak Kardelen Çınar Meşe Selvi Ihlamur Söğüt Defne Akasya Orkide Nilüfer
Yıldız Güneş Bulut Yağmur Fırtına Rüzgar Şimşek Gökkuşağı Şafak Samanyolu Gezegen Meltem Poyraz Lodos Karayel Bora
Bozkır Dağ Deniz Nehir Göl Ova Vadi Orman Çöl Ada Pınar Çağlayan Şelale Kıyı Zirve Yayla Tuna Ege Aras Dicle Fırat
Cesur Yürek Vefa Umut Dürüst Mert Yiğit Bilge Kudret Erdem Onur Sakin Zarif Asil Özgür Gönül Huzur Neşe Sefa Safa Cömert Dost Sadık
Badem Nar Çilek Kiraz Vişne Erik Elma Limon Zeytin İncir Üzüm Karpuz Şeftali Kayısı Nane Biberiye Lavanta
Ahenk Ezgi Nağme Türkü Saz Keman Ney Bağlama Davul Zurna Kaval
Pusula Fener Kervan Mavi Turkuaz Lacivert Zümrüt Yakut Elmas İnci Mercan Kehribar Gümüş Altın Bakır
CesurKartal AltınKartal GümüşKurt KarKaplanı MaviTurna SessizGöl NeşeliSerçe UmutYıldızı GeceKuşu GüneşKuşu BozkırKedi
KaraBulut AkŞahin CoşkuRüzgar SakinDeniz GizliBahçe AltınBaşak YeşilÇınar DağÇiçeği KutupYıldız UçanKaplan HızlıAtmaca
YalnızKurt TatlıKiraz MutluBaykuş SarıLale MorMenekşe BeyazKuğu KızılElma GökTurna DenizKızı RüzgarGülü Ayışığı Gündoğumu
Baykuş Karaca Geyik Tilki Sincap Kunduz Yaban Doğa Çimen Çiçek Bahar Yaz Güz Kış Gece Sabah Akşam Gün Ay Tan Seher
Kuzey Güney Doğu Batı Anadolu Toros Ağrı Erciyes Uludağ Munzur Kaçkar Palandöken
Kuzgun Albatros Flamingo Pelikan Karakuş Doğru Kardan Buzul Kutup Yelken Kaptan Dümen Liman Fırtınalı Usta Çırak Ozan Âşık
""".split()

import re, sys
seen=set(); out=[]; bad=[]
for w in WORDS:
    k=w.replace('İ','i').replace('I','ı').lower()
    if k in seen: continue
    seen.add(k)
    if len(w)>11: bad.append(w); continue
    if not re.fullmatch(r'[A-Za-zÇĞİÖŞÜçğıöşüÂâÎîÛû]+', w): sys.exit(f'izinsiz karakter: {w}')
    out.append(w)

if bad: sys.exit('çok uzun: '+', '.join(bad))
dart = "// OTOMATİK ÜRETİLDİ: scripts/gen_nick_words.py — elle düzenleme. Sunucudaki (migration-011.sql) liste AYNI sıradadır.\n"
dart += "// Takma ad serbest yazı DEĞİL: oyuncu bu listeden bir kelime seçer, sunucu sonuna sayı ekler (Kartal_4821).\n\n"
dart += "const List<String> kNickWords = [\n"
line="  "
for w in out:
    item=f"'{w}', "
    if len(line)+len(item)>96:
        dart+=line.rstrip()+"\n"; line="  "
    line+=item
dart+=line.rstrip()+"\n];\n\n"
dart += """/// Kayıtlı addan (Kartal_4821) kelimenin sırasını bulur; bulunamazsa null.
int? nickWordIndex(String name) {
  final base = name.replaceFirst(RegExp(r'_[0-9]{4}$'), '');
  final i = kNickWords.indexOf(base);
  return i < 0 ? null : i;
}
"""
open('lib/models/nick_words.dart','w',encoding='utf-8').write(dart)

arr=",".join("'"+w.replace("'","''")+"'" for w in out)
sql=f"""-- migration-011: TAKMA AD SERBEST YAZI DEĞİL. Oyuncu kelime listesinden seçer, sunucu sonuna 4 haneli sayı ekler (Kartal_4821).
-- Çalıştırma: SQL Editor'e olduğu gibi yapıştır (migration-004'ten SONRA; yeniden çalıştırılabilir).
-- Kelime listesi Dart'ta lib/models/nick_words.dart ile AYNI SIRADADIR (scripts/gen_nick_words.py ikisini birlikte üretir).

-- Eski serbest metin fonksiyonu KALDIRILIR: yamalı bir istemci bile istediği adı yazamasın.
drop function if exists public.set_profile(text, int);

-- p_word: kelime sırası (0'dan başlar). null = adı değiştirme, yalnız avatarı güncelle.
-- Hata kodları: giris_gerekli, gecersiz_avatar, gecersiz_isim, ad_sik_degisti (kelime 7 günde bir değişir), ad_alinmis
create or replace function public.set_profile(p_word int, p_avatar int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_words text[] := array[{arr}];
  v_old record;
  v_name text;
  v_try int;
begin
  if v_uid is null then raise exception 'giris_gerekli'; end if;
  if p_avatar is null or p_avatar < 0 or p_avatar > 19 then raise exception 'gecersiz_avatar'; end if;
  select named, name, name_changed_at into v_old from profiles where id = v_uid for update;
  if not found then raise exception 'giris_gerekli'; end if;

  -- yalnız avatar
  if p_word is null then
    if not v_old.named then raise exception 'gecersiz_isim'; end if;
    update profiles set avatar = p_avatar where id = v_uid;
    return jsonb_build_object('name', v_old.name, 'avatar', p_avatar);
  end if;

  if p_word < 0 or p_word >= array_length(v_words, 1) then raise exception 'gecersiz_isim'; end if;

  -- aynı kelime yeniden seçildi: sayı korunur, yalnız avatar güncellenir
  if v_old.named and regexp_replace(v_old.name, '_[0-9]{{4}}$', '') = v_words[p_word + 1] then
    update profiles set avatar = p_avatar where id = v_uid;
    return jsonb_build_object('name', v_old.name, 'avatar', p_avatar);
  end if;

  if v_old.named and v_old.name_changed_at is not null and v_old.name_changed_at > now() - interval '7 days' then
    raise exception 'ad_sik_degisti';
  end if;

  -- sayıyı sunucu verir; çakışırsa yenisini dener
  for v_try in 1..30 loop
    v_name := v_words[p_word + 1] || '_' || ((1000 + floor(random() * 9000))::int)::text;
    begin
      update profiles set name = v_name, avatar = p_avatar, named = true, name_changed_at = now() where id = v_uid;
      return jsonb_build_object('name', v_name, 'avatar', p_avatar);
    exception when unique_violation then
      null; -- başkası aldı, tekrar dene
    end;
  end loop;
  raise exception 'ad_alinmis';
end $$;

revoke all on function public.set_profile(int, int) from public, anon;
grant execute on function public.set_profile(int, int) to authenticated;

-- Eski serbest yazılmış adlar (küfür/hakaret olabilir) SİLİNİR: herkes bir sonraki girişte listeden yeni isim seçer.
-- Oyun henüz yayında değilse güvenle çalıştır; yayındaysa oyuncular adlarını yeniden seçer (hesap/bilet/puan etkilenmez).
update public.profiles set named = false, name = 'Oyuncu', name_changed_at = null where named;
"""
open('okey101-server/supabase/migration-011.sql','w',encoding='utf-8').write(sql)
print(len(out),'kelime')
