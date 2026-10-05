import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/inr.dart';
import '../data/models/bill.dart';
import 'invoice_pdf.dart';

/// Print an invoice, share its PDF (WhatsApp, email, ...), or open a
/// WhatsApp chat with the customer with a text summary of the bill.
class InvoiceShare {
  InvoiceShare._();

  /// The system print dialog (any printer, incl. 80 mm thermal ones, or
  /// "save as PDF").
  static Future<void> printPdf(Bill bill, InvoiceLayout layout) async {
    final InvoiceFonts fonts = await InvoiceFonts.load();
    final (Uint8List pdf, PdfPageFormat format) =
        await InvoicePdf.buildForPrint(bill, layout: layout, fonts: fonts);
    await Printing.layoutPdf(
      name: InvoicePdf.fileName(bill, layout),
      format: format,
      onLayout: (_) async => pdf,
    );
  }

  /// The share sheet with the invoice PDF attached.
  static Future<void> sharePdf(Bill bill, InvoiceLayout layout) async {
    final InvoiceFonts fonts = await InvoiceFonts.load();
    final Directory dir = await getTemporaryDirectory();
    final File file = File(p.join(dir.path, InvoicePdf.fileName(bill, layout)));
    await file.writeAsBytes(await InvoicePdf.build(bill, layout: layout, fonts: fonts));
    await SharePlus.instance.share(ShareParams(
      files: <XFile>[XFile(file.path, mimeType: 'application/pdf')],
      text: summary(bill),
      subject: 'Invoice ${bill.invoiceNo}',
    ));
  }

  /// Opens WhatsApp on the customer's number with [summary]; false when the
  /// bill has no usable phone number or WhatsApp can't be opened.
  static Future<bool> openWhatsApp(Bill bill) async {
    final Uri? uri = whatsAppUri(bill);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static Uri? whatsAppUri(Bill bill) {
    final String? number = whatsAppNumber(bill.customerPhone);
    if (number == null) return null;
    return Uri.https('wa.me', '/$number', <String, String>{'text': summary(bill)});
  }

  /// Digits with country code for wa.me; a 10-digit number is Indian (+91).
  static String? whatsAppNumber(String? phone) {
    if (phone == null) return null;
    final String raw = phone.trim();
    String d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (raw.startsWith('+')) {
      // Already international.
    } else if (d.startsWith('00')) {
      d = d.substring(2);
    } else if (d.length == 11 && d.startsWith('0')) {
      d = '91${d.substring(1)}';
    } else if (d.length == 10) {
      d = '91$d';
    }
    return d.length >= 11 && d.length <= 15 ? d : null;
  }

  /// Short text version of the bill for WhatsApp / the share sheet.
  static String summary(Bill bill) {
    final StringBuffer b = StringBuffer()
      ..writeln('*${bill.seller.displayName}*')
      ..writeln('Invoice ${bill.invoiceNo}')
      ..writeln(DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt ?? bill.billDate))
      ..writeln();
    const int shown = 15;
    for (final BillItem i in bill.items.take(shown)) {
      b.writeln('${i.name} x ${i.qty} = ${Inr.format(i.totalPaise)}');
    }
    if (bill.items.length > shown) b.writeln('+ ${bill.items.length - shown} more');
    b
      ..writeln()
      ..writeln('*Total: ${Inr.format(bill.totalPaise)}* (${bill.paymentMode.label})');
    if (bill.isCancelled) b.writeln('This bill was cancelled.');
    b.write('Thank you!');
    return b.toString();
  }
}
