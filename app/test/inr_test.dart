import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/core/inr.dart';

void main() {
  test('Indian digit grouping', () {
    expect(Inr.format(0), '₹0.00');
    expect(Inr.format(5), '₹0.05');
    expect(Inr.format(36400), '₹364.00');
    expect(Inr.format(123456), '₹1,234.56');
    expect(Inr.format(12345678), '₹1,23,456.78');
    expect(Inr.format(123456789012), '₹1,23,45,67,890.12');
    expect(Inr.format(-49), '-₹0.49');
    expect(Inr.format(1234567, symbol: false), '12,345.67');
    expect(Inr.group(100000), '1,00,000');
  });

  test('amount in words, lakh and crore', () {
    expect(Inr.words(36400), 'Rupees Three Hundred Sixty Four Only');
    expect(Inr.words(0), 'Rupees Zero Only');
    expect(Inr.words(100), 'Rupees One Only');
    expect(Inr.words(1150), 'Rupees Eleven and Fifty Paise Only');
    expect(Inr.words(12345678),
        'Rupees One Lakh Twenty Three Thousand Four Hundred Fifty Six and Seventy Eight Paise Only');
    expect(Inr.words(1000000000), 'Rupees One Crore Only');
    expect(Inr.words(2500000000000), 'Rupees Two Thousand Five Hundred Crore Only');
    expect(Inr.words(9019900), 'Rupees Ninety Thousand One Hundred Ninety Nine Only');
  });

  test('percent from basis points', () {
    expect(Inr.percent(500), '5%');
    expect(Inr.percent(1250), '12.5%');
    expect(Inr.percent(1205), '12.05%');
    expect(Inr.percent(0), '0%');
    expect(Inr.parsePercent('12.5'), 1250);
    expect(Inr.parsePercent('10%'), 1000);
    expect(Inr.parsePercent(''), 0);
    expect(Inr.parsePercent('101'), isNull);
    expect(Inr.parsePercent('abc'), isNull);
  });
}
