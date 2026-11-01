import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okey101/models/quick_chat.dart';
import 'package:okey101/services/mock_game_service.dart';
import 'package:okey101/widgets/chat_widgets.dart';

void main() {
  test('numaralar benzersiz ve sunucu sınırı (0..31) içinde', () {
    final all = [...kQuickPhrases, ...kQuickEmojis];
    final ids = all.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids.every((i) => i >= 0 && i < 32), isTrue);
  });

  test('istenen cümleler ve emojiler var, numaradan bulunur', () {
    final labels = kQuickPhrases.map((c) => c.label).toList();
    for (final t in ['Seriii', 'Okey attın!', 'Bu el benim', 'Elin nasıl?', 'Bitiyim mi?', 'Evet', 'Hayır', 'Tebrikler', 'Teşekkürler']) {
      expect(labels, contains(t));
    }
    expect(kQuickEmojis, isNotEmpty);
    expect(kQuickEmojis.every((c) => c.isEmoji), isTrue);
    expect(quickChatById(0)!.label, 'Seriii');
    expect(quickChatById(31), isNull); // bilinmeyen numara yok sayılır
  });

  test('hız sınırı: 3 sn bekleme + dakikada 8 mesaj', () {
    final l = ChatLimiter();
    var t = DateTime(2026, 10, 26, 12);
    expect(l.canSend(t), isTrue);
    l.record(t);
    expect(l.canSend(t.add(const Duration(milliseconds: 2900))), isFalse);
    expect(l.wait(t.add(const Duration(seconds: 1))), const Duration(seconds: 2));
    // 8 mesaj, aralarında 3,1 sn: hepsi geçer; 9. dakikalık sınıra takılır
    for (var i = 1; i < 8; i++) {
      t = t.add(const Duration(milliseconds: 3100));
      expect(l.canSend(t), isTrue, reason: 'mesaj ${i + 1}');
      l.record(t);
    }
    t = t.add(const Duration(milliseconds: 3100));
    expect(l.canSend(t), isFalse, reason: '9. mesaj dakikalık sınırda');
    expect(l.wait(t) > Duration.zero, isTrue);
    // ilk mesajdan 60 sn sonra yeniden açılır
    expect(l.canSend(DateTime(2026, 10, 26, 12, 1, 1)), isTrue);
  });

  test('sahte servis: bekleme süresi içindeki ikinci mesaj yok sayılır', () async {
    final s = MockGameService();
    final got = <ChatEvent>[];
    s.chatEvents.listen(got.add);
    for (var i = 0; i < 20; i++) {
      s.sendChat(0); // ilki bekleme başlatır, kalanlar atılır
    }
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(got.length <= 1, isTrue); // en çok 1 bilgisayar cevabı
    if (got.isNotEmpty) {
      expect(got.first.seat >= 1 && got.first.seat <= 3, isTrue);
      expect(quickChatById(got.first.id), isNotNull);
    }
  });

  testWidgets('panel: cümleye dokununca onPick çağrılır; bekleme sürerken çağrılmaz', (tester) async {
    QuickChat? picked;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(child: ChatPanel(ready: true, onPick: (c) => picked = c, onClose: () {})))));
    await tester.tap(find.text('Seriii'));
    expect(picked?.id, 0);
    picked = null;
    await tester.tap(find.text('😂'));
    expect(picked?.id, 8);

    picked = null;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: ChatPanel(ready: false, onPick: (c) => picked = c, onClose: () {})))));
    await tester.tap(find.text('Evet'));
    expect(picked, isNull);
  });

  testWidgets('balon: mesaj görünür, chat null olunca kaybolur', (tester) async {
    Widget app(QuickChat? c, int gen) => MaterialApp(
        home: Scaffold(body: Center(child: ChatBubbleSlot(chat: c, gen: gen))));
    await tester.pumpWidget(app(quickChatById(1), 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Okey attın!'), findsOneWidget);
    await tester.pumpWidget(app(null, 1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Okey attın!'), findsNothing);
  });
}
