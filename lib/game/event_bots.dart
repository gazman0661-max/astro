import 'dart:math' as math;

/// ORTAK BOT MOTORU (Worlds Merge'ten uyarlandi).
/// Her iki etkinlik de (Kuyruklu Yildiz Yarisi, Puan Toplama Yarisi) bunu kullanir.
/// Botlar SAKLANMAZ, bir tohumdan (seed) uretilir: ayni etkinlik = ayni botlar,
/// ama her yeni etkinlikte (yeni seed ile) farkli isim/seviye/hiz cikar.

/// Botun gorunen kimligi.
class BotProfile {
  final String name;
  final int avatarColor; // ARGB
  final String avatarIcon;
  final int level;
  final double awakeAdj; // kisilik: -0.15..+0.15, uyanik olma olasiligina eklenir
  const BotProfile({
    required this.name,
    required this.avatarColor,
    required this.avatarIcon,
    required this.level,
    required this.awakeAdj,
  });
}

class BotIdentity {
  BotIdentity._();

  // ---- v32: DESTEKLENEN 6 DILIN (tr, en, ru, es, pt-BR, ja) KARISIK ISIMLERI ----
  // Latin yazili diller duz liste; ru/ja icin 'Yerel|Latin' ciftleri (Latin hali
  // "emre34" tarzi takma adlarda kullanilir).
  static const List<String> trNames = [
    'Elif', 'Mert', 'Zeynep', 'Burak', 'Selin', 'Can', 'Deniz', 'Aylin', 'Emre', 'Ece',
    'Kaan', 'Defne', 'Arda', 'Yaren', 'Onur', 'Ada', 'Cem', 'Ayşe', 'Fatma', 'Ahmet',
    'Mehmet', 'Gizem', 'Hakan', 'Merve', 'Berk', 'Esra', 'Tuna', 'Buse', 'Eren', 'İrem',
    'Oğuz', 'Sinem', 'Yiğit', 'Pınar', 'Barış', 'Damla', 'Umut', 'Nehir', 'Tolga', 'Duygu',
    'Kerem', 'Melis', 'Ozan', 'Seda', 'Furkan', 'Beyza', 'Efe', 'Ceren', 'Mina', 'Doruk',
  ];
  static const List<String> enNames = [
    'Alex', 'Mia', 'Liam', 'Sofia', 'Noah', 'Emma', 'Lucas', 'Anna', 'Leo', 'Nina',
    'Max', 'Julia', 'Oliver', 'Chloe', 'Jack', 'Lily', 'Ethan', 'Grace', 'Ryan', 'Zoe',
    'Daniel', 'Ella', 'Jake', 'Ruby', 'Tom', 'Hannah', 'Sam', 'Amy', 'Ben', 'Kate',
  ];
  static const List<String> esNames = [
    'Mateo', 'Valentina', 'Santiago', 'Camila', 'Diego', 'Lucía', 'Sebastián', 'Martina',
    'Javier', 'Carmen', 'Álvaro', 'Paula', 'Hugo', 'Sara', 'Pablo', 'Elena', 'Andrés',
    'Daniela', 'Carlos', 'Isabella', 'Adrián', 'Marta', 'Iván', 'Noelia', 'Rubén', 'Inés',
    'Joaquín', 'Alba', 'Nicolás', 'Rocío',
  ];
  static const List<String> ptNames = [
    'Gabriel', 'Beatriz', 'Rafael', 'Larissa', 'Thiago', 'Julia', 'Matheus', 'Fernanda',
    'Lucas', 'Mariana', 'Bruno', 'Camila', 'Gustavo', 'Letícia', 'Felipe', 'Amanda',
    'João', 'Isabela', 'Vinícius', 'Bianca', 'Caio', 'Renata', 'Leonardo', 'Tatiane',
    'Rodrigo', 'Aline', 'Henrique', 'Luana', 'Murilo', 'Cláudia',
  ];
  static const List<String> ruNames = [
    'Александр|Aleksandr', 'Анастасия|Anastasia', 'Дмитрий|Dmitry', 'Мария|Maria',
    'Иван|Ivan', 'Екатерина|Katya', 'Михаил|Mikhail', 'Ольга|Olga', 'Никита|Nikita',
    'Полина|Polina', 'Артём|Artem', 'Дарья|Darya', 'Сергей|Sergey', 'Алиса|Alisa',
    'Кирилл|Kirill', 'Виктория|Viktoria', 'Максим|Maxim', 'Ксения|Ksenia', 'Егор|Egor',
    'Татьяна|Tanya', 'Андрей|Andrey', 'Юлия|Yulia', 'Роман|Roman', 'Анна|Anna',
    'Денис|Denis', 'Василиса|Vasilisa', 'Тимур|Timur', 'Елена|Elena', 'Глеб|Gleb', 'Вера|Vera',
  ];
  static const List<String> jaNames = [
    'さくら|Sakura', 'はると|Haruto', 'ゆうき|Yuki', 'あおい|Aoi', 'れん|Ren', 'ひなた|Hinata',
    'そうた|Sota', 'みお|Mio', 'たくみ|Takumi', 'ゆい|Yui', 'けんた|Kenta', 'りな|Rina',
    'だいき|Daiki', 'ななみ|Nanami', 'しょう|Sho', 'あやか|Ayaka', 'りく|Riku', 'めい|Mei',
    '大翔|Hiroto', '美咲|Misaki', '蓮|Ren', '陽菜|Hina', '悠斗|Yuto', '結衣|Yui',
    '健太|Kenta', '愛|Ai', '翔|Sho', '花|Hana', '拓海|Takumi', '優|Yu',
  ];

  /// Ortak (dile bagli olmayan) takma ad kelimeleri + her dilden birkac kelime.
  static const List<String> nickWords = [
    'Pixel', 'Nova', 'Maple', 'Turbo', 'Blaze', 'Lucky', 'Cosmo', 'Panda', 'Ninja', 'Rocket',
    'Comet', 'Orbit', 'Frost', 'Bolt', 'Gizmo', 'Galaxy', 'Star', 'Moon', 'Cyber', 'Alpha',
    'Yildiz', 'Bulut', 'Kurt', 'Aslan', // tr
    'Estrella', 'Luna', 'Fuego', 'Lobo', // es
    'Estrela', 'Sol', 'Raio', 'Onca', // pt
    'Zvezda', 'Volk', 'Medved', 'Luch', // ru
    'Sakura', 'Hoshi', 'Kitsune', 'Tora', // ja
  ];
  static const List<String> surnames = [
    'Yılmaz', 'Kaya', 'Demir', 'Çelik', 'Şahin', 'Yıldız', 'Öztürk', 'Aydın', 'Arslan', 'Doğan', // tr
    'Smith', 'Brown', 'Miller', 'Wilson', 'Taylor', // en
    'García', 'Martínez', 'López', 'Hernández', 'Sánchez', // es
    'Silva', 'Santos', 'Oliveira', 'Souza', 'Costa', // pt
    'Иванов', 'Петров', 'Смирнов', 'Кузнецов', 'Попов', // ru
  ];
  /// "oyuncu12345" tarzi varsayilan kullanici adi on ekleri (dillere gore).
  static const List<String> playerWords = [
    'oyuncu', 'player', 'jugador', 'jogador', 'igrok', 'purei',
  ];

  static const List<String> icons = ['🐱', '🐶', '🦊', '🐼', '🐸', '🦁', '🐯', '🐵', '🐧', '🦄', '🌟', '🔥', '🍀', '🎮', '🚀', '🌈'];
  static const List<int> colors = [
    0xFF5C6BC0, 0xFF26A69A, 0xFFEF5350, 0xFFFFA726, 0xFF8D6E63,
    0xFFAB47BC, 0xFF42A5F5, 0xFF66BB6A, 0xFFEC407A, 0xFF78909C,
  ];

  /// Aksan/ozel harfleri Latin ASCII'ye indirger (takma ad uretimi icin).
  static String ascii(String s) {
    const from = 'çÇğĞıİöÖşŞüÜáàâãäÁÀÂÃÄéèêëÉÈÊËíìîïÍÌÎÏóòôõÓÒÔÕúùûÚÙÛñÑ';
    const to = 'cCgGiIoOsSuUaaaaaAAAAAeeeeEEEEiiiiIIIIooooOOOOuuuUUUnN';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  /// 'Yerel|Latin' ciftini ayirir; cift degilse ikisi de ayni metin.
  static (String native, String latin) _split(String e) {
    final i = e.indexOf('|');
    return i < 0 ? (e, ascii(e)) : (e.substring(0, i), e.substring(i + 1));
  }

  /// Karisik dil dagilimi: tr %32, en %16, ru %14, es %13, pt %13, ja %12.
  static (String native, String latin) _base(math.Random r) {
    final roll = r.nextDouble();
    final List<String> list;
    if (roll < 0.32) {
      list = trNames;
    } else if (roll < 0.48) {
      list = enNames;
    } else if (roll < 0.62) {
      list = ruNames;
    } else if (roll < 0.75) {
      list = esNames;
    } else if (roll < 0.88) {
      list = ptNames;
    } else {
      list = jaNames;
    }
    return _split(list[r.nextInt(list.length)]);
  }

  static String _name(math.Random r) {
    final roll = r.nextDouble();
    if (roll < 0.30) return _base(r).$1; // Elif / Мария / さくら
    if (roll < 0.45) return '${_base(r).$2.toLowerCase()}${1 + r.nextInt(99)}'; // emre34 / maria7
    if (roll < 0.60) return _base(r).$2.toLowerCase(); // berk / sakura
    if (roll < 0.75) {
      final a = nickWords[r.nextInt(nickWords.length)];
      return '$a${1 + r.nextInt(99)}'; // Nova99
    }
    if (roll < 0.88) {
      final b = _base(r).$1;
      final sur = surnames[r.nextInt(surnames.length)];
      return '$b ${sur[0]}.'; // Mert Y. / Ana S.
    }
    return '${playerWords[r.nextInt(playerWords.length)]}${1 + r.nextInt(99999)}';
  }

  /// Tek bot kimligi uretir. [used] ayni listede isim tekrarini onler.
  /// [fast01]: botun hiz sirasi 0 (en yavas) .. 1 (en hizli). Hiz yuksekse seviye de yuksek cikar.
  static BotProfile make(math.Random r, Set<String> used, {int minLevel = 5, double fast01 = -1}) {
    var name = _name(r);
    for (var i = 0; i < 20 && used.contains(name.toLowerCase()); i++) {
      name = _name(r);
    }
    while (used.contains(name.toLowerCase())) {
      name = '$name${r.nextInt(10)}';
    }
    used.add(name.toLowerCase());
    final color = colors[r.nextInt(colors.length)];
    final icon = r.nextDouble() < 0.55 ? icons[r.nextInt(icons.length)] : '';
    final lv = r.nextDouble();
    final x = fast01 < 0 ? lv : (0.7 * fast01.clamp(0.0, 1.0) + 0.3 * lv);
    final level = minLevel + (math.pow(x, 1.5) * 40).floor() as int;
    final adj = (r.nextDouble() - 0.5) * 0.30;
    return BotProfile(name: name, avatarColor: color, avatarIcon: icon, level: level, awakeAdj: adj);
  }
}

/// ---------------------------------------------------------------------------
/// BOT PUAN EGRISI (Worlds Merge motorundan uyarlandi, v23)
///
/// Botlar OYUNCUDAN TAMAMEN BAGIMSIZDIR: her botun etkinlik sonundaki puani
/// (finalScore) sabittir; bu dosya yalnizca o puana ZAMAN icinde NASIL
/// ulasildigini uretir. Egri tohumdan (seed) hesaplanir, saklanmaz:
/// ayni seed + bot + saat = ayni sonuc.
///  - Gun ritmi: gece az, aksam cok (yerel saat: [kBotBaseTzHours]).
///  - Saat dilimi kaymasi: cogu bot +-2 saat, kalani dunyanin her yerinde.
///  - Oturum kumeleri: 3 saatlik blok acik degilse o blokta oynamaz.
///  - Patlama (burst): ara sira bir saatte 2.5 kat puan.
///  - Saat ici kumelenme: puan dakika dakika duz akmaz, kumeler halinde artar.
/// ---------------------------------------------------------------------------

/// Botlarin "yerel saat" merkezi. v30: etkinlik oyuncunun YEREL saatiyle
/// baslar ve startHour zaten yerel saattir; bu yuzden ek kaydirma 0.
/// (Botlarin aksam yogunlugu oyuncunun kendi aksamina denk gelir.)
const int kBotBaseTzHours = 0;

const double _kAwakeChance = 0.65;
const double _kBurstChance = 0.10;
const double _kBurstMul = 2.5;

// Saat (0-23) basina uyanik olma carpani; ortalamasi 1.0'a normalize edilir.
const List<double> _diurnalRaw = [
  0.45, 0.30, 0.20, 0.18, 0.18, 0.28, 0.55, 0.85, 1.00, 1.05, 1.05, 1.10,
  1.10, 1.05, 1.00, 1.00, 1.05, 1.10, 1.20, 1.30, 1.35, 1.30, 1.15, 0.75,
];
final List<double> _diurnal = () {
  var sum = 0.0;
  for (final v in _diurnalRaw) {
    sum += v;
  }
  final mean = sum / _diurnalRaw.length;
  return [for (final v in _diurnalRaw) v / mean];
}();

int _mix(int a, int b, int c) =>
    ((a * 1000003) ^ (b * 7919) ^ (c * 104729) ^ 0x5bd1e995) & 0x7fffffff;

/// Botun saat dilimi kaymasi (saat). Saf fonksiyon.
int botTzShift(int seed, int bot) {
  final r = math.Random(_mix(seed ^ 0x7A11, bot, 5));
  return r.nextDouble() < 0.82 ? r.nextInt(5) - 2 : r.nextInt(24);
}

/// Botun bu saatteki GORECELI agirligi (0 = uyuyor). Hiz carpani yok: bot
/// puani finalScore'a normalize edildigi icin yalnizca ORAN onemlidir.
double _hourWeight(int seed, int bot, int hour, double awakeAdj, int startHour, int tz) {
  final hod = (hour + startHour + tz + kBotBaseTzHours) % 24;
  final p = ((_kAwakeChance + awakeAdj) * _diurnal[hod]).clamp(0.05, 1.0).toDouble();
  final pBlock = math.min(1.0, p * 1.4);
  final pHour = p / pBlock;
  final rb = math.Random(_mix(seed ^ 0x51ED27, bot, hour ~/ 3)).nextDouble();
  final r = math.Random(_mix(seed, bot, hour));
  final rh = r.nextDouble();
  final burst = r.nextDouble() < _kBurstChance ? _kBurstMul : 1.0;
  final tempo = 0.5 + r.nextDouble(); // 0.5 .. 1.5
  final awake = rb < pBlock && rh < pHour;
  return awake ? burst * tempo : 0.0;
}

/// Bir saatin [part] (0..1) kadarlik kismi icin birikmis oran 0..1.
double _withinHour(int seed, int bot, int hour, double part) {
  if (part >= 1.0) return 1.0;
  if (part <= 0.0) return 0.0;
  final r = math.Random(_mix(seed ^ 0x2545F4, bot, hour));
  final w = List<double>.generate(4, (_) => r.nextDouble() < 0.6 ? 0.4 + r.nextDouble() : 0.0);
  var sum = w[0] + w[1] + w[2] + w[3];
  if (sum <= 0.0) {
    w[r.nextInt(4)] = 1.0;
    sum = 1.0;
  }
  final x = part * 4.0;
  var acc = 0.0;
  for (var q = 0; q < 4; q++) {
    acc += w[q] * (x - q).clamp(0.0, 1.0).toDouble();
  }
  return acc / sum;
}

// (seed, bot, startHour, awakeAdj) -> 48 saatlik agirliklar. Ekran saniyede
// bir tazelendigi icin her seferinde yeniden uretmeyelim.
final Map<String, List<double>> _weightCache = {};

List<double> _weightsFor(int seed, int bot, double awakeAdj, int startHour, int hours) {
  final key = '$seed:$bot:$startHour:$hours:${awakeAdj.toStringAsFixed(4)}';
  final hit = _weightCache[key];
  if (hit != null) return hit;
  if (_weightCache.length > 4000) _weightCache.clear();
  final tz = botTzShift(seed, bot);
  final w = List<double>.generate(hours, (h) => _hourWeight(seed, bot, h, awakeAdj, startHour, tz));
  _weightCache[key] = w;
  return w;
}

/// Botun [elapsedHours] anindaki puani. Etkinlik sonunda tam [finalScore]'a
/// ulasir; arada gercek bir oyuncu gibi gece durur, aksam hizlanir.
/// [finalScore] SABITTIR (oyuncunun puanina bagli degildir).
double botScoreAtHour(int seed, int botIndex, double finalScore, double elapsedHours,
    {double awakeAdj = 0.0, int startHour = 0, int eventHours = 48}) {
  if (elapsedHours <= 0) return 0.0;
  final total = elapsedHours.clamp(0.0, eventHours.toDouble()).toDouble();
  final w = _weightsFor(seed, botIndex, awakeAdj, startHour, eventHours);
  var sum = 0.0;
  for (final v in w) {
    sum += v;
  }
  if (sum <= 0) return finalScore * (total / eventHours); // hic uyanmadi: dümdüz ilerlet
  final full = total.floor();
  final part = total - full;
  var acc = 0.0;
  for (var h = 0; h < full && h < eventHours; h++) {
    acc += w[h];
  }
  if (full < eventHours) acc += w[full] * _withinHour(seed, botIndex, full, part);
  return finalScore * (acc / sum);
}
