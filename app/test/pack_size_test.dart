import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/domain/pack_size.dart';

void main() {
  group('PackSize', () {
    test('applies to tablets, capsules and ml with a pack of more than one',
        () {
      expect(PackSize.applies('Tablets', 10), isTrue);
      expect(PackSize.applies('Capsules', 6), isTrue);
      expect(PackSize.applies('ML', 100), isTrue);
      expect(PackSize.applies('Tablets', 1), isFalse, reason: 'no pack');
      expect(PackSize.applies('Strips', 10), isFalse,
          reason: 'strips are already whole packs');
      expect(PackSize.applies('Bottles', 100), isFalse);
    });

    test('reads stock as packs + loose pieces', () {
      expect(PackSize.split(63, 10), (6, 3));
      expect(PackSize.split(7, 1), (0, 7));
      expect(PackSize.breakdown(23, 'Tablets', 10), '2 strips + 3 tablets');
      expect(PackSize.breakdown(20, 'Tablets', 10), '2 strips');
      expect(PackSize.breakdown(10, 'Tablets', 10), '1 strip');
      expect(PackSize.breakdown(3, 'Tablets', 10), '3 tablets');
      expect(PackSize.breakdown(1, 'Capsules', 6), '1 capsule');
      expect(PackSize.breakdown(250, 'ML', 100), '2 bottles + 50 ml');
      expect(PackSize.breakdown(0, 'Tablets', 10), '0 tablets');
      expect(PackSize.breakdown(23, 'Strips', 10), isEmpty,
          reason: 'a strip-counted medicine has nothing to break down');
      expect(PackSize.breakdown(23, 'Tablets', 1), isEmpty);
    });

    test('stock label adds the breakdown only when it applies', () {
      expect(PackSize.stock(23, 'Tablets', 10),
          '23 Tablets (2 strips + 3 tablets)');
      expect(PackSize.stock(23, 'Strips', 10), '23 Strips');
      expect(PackSize.stock(5, 'Tablets', 1), '5 Tablets');
    });

    test('labels', () {
      expect(PackSize.perPackLabel('Tablets'), 'Tablets per strip');
      expect(PackSize.perPackLabel('Capsules'), 'Capsules per strip');
      expect(PackSize.perPackLabel('ML'), 'ML per bottle');
      expect(PackSize.pieceNoun('Tablets'), 'tablet');
      expect(PackSize.packNoun('ML'), 'bottle');
    });

    test('parses the pieces per pack from a printed label', () {
      expect(PackSize.parse("15's"), 15);
      expect(PackSize.parse('10S'), 10);
      expect(PackSize.parse('1x10'), 10);
      expect(PackSize.parse('10 X 10'), 100);
      expect(PackSize.parse('100ML'), 100);
      expect(PackSize.parse('strip of 10 tablets'), 10);
      expect(PackSize.parse('strip of 6 capsules'), 6);
      expect(PackSize.parse('strip of 1 tablet'), 1);
      expect(PackSize.parse('bottle of 60 ml Syrup'), 60);
      expect(PackSize.parse('10'), 10);
      expect(PackSize.parse('6'), 6);
      expect(PackSize.parse(''), 1);
      expect(PackSize.parse('TAB'), 1);
      expect(PackSize.parse('500 mg'), 1, reason: 'a strength, not a count');
      expect(PackSize.parse('tube of 15 gm Gel'), 15);
      expect(PackSize.parse('0'), 1, reason: 'never below one');
      expect(PackSize.parse('99999 x 99999'), PackSize.max);
    });
  });
}
