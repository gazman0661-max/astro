import 'package:flutter_test/flutter_test.dart';
import 'package:okey101/services/game_socket.dart';

void main() {
  group('validateOps (sunucuya gitmeden hamle kontrolü)', () {
    test('take + openSeries + lay + discard geçerli', () {
      final ops = TurnBatch()
          .take()
          .openSeries([
            [1, 2, 3]
          ])
          .lay(7, meld: 0)
          .discard(9)
          .build();
      expect(ops.length, 4);
      expect(validateOps(ops), isNull);
    });

    test('take + discard tek başına geçersiz', () {
      expect(() => TurnBatch().take().discard(5).build(),
          throwsA(isA<BatchException>()));
    });

    test('draw ayrı mesaj olmalı', () {
      expect(validateOps([
        {'t': 'draw'},
        {'t': 'discard', 'id': 1}
      ]), isNotNull);
      expect(validateOps([
        {'t': 'draw'}
      ]), isNull);
    });

    test('discard son hamle olmalı', () {
      expect(validateOps([
        {'t': 'discard', 'id': 1},
        {'t': 'lay', 'id': 2}
      ]), isNotNull);
    });

    test('en fazla 8 hamle, boş liste ve bilinmeyen hamle reddedilir', () {
      final nine = List<Map<String, dynamic>>.generate(9, (_) => {'t': 'autolay'});
      expect(validateOps(nine), isNotNull);
      expect(validateOps(const []), isNotNull);
      expect(validateOps([
        {'t': 'hile'}
      ]), isNotNull);
      expect(validateOps(List<Map<String, dynamic>>.generate(8, (_) => {'t': 'autolay'})), isNull);
    });
  });
}
