import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'image_downscale.dart';

/// A picked supplier bill, checked and ready to upload for AI reading.
class InvoiceUpload {
  const InvoiceUpload(this.bytes, this.name);

  final Uint8List bytes;

  /// Keeps the extension the server checks.
  final String name;

  // The server's limits; checked here too so a big file fails fast.
  static const int maxImageBytes = 7 * 1024 * 1024;
  static const int maxPdfBytes = 10 * 1024 * 1024;

  /// The AI's own image limit (long edge): sharp enough for small print,
  /// quick to upload.
  static const int maxImageSide = 2576;

  static const Set<String> extensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'webp',
    'pdf',
  };

  // For the file picker: PDFs on phones (photos come from the camera or
  // gallery there), photos or PDFs on the desktop.
  static const XTypeGroup pdfFiles = XTypeGroup(
    label: 'PDF',
    extensions: <String>['pdf'],
    mimeTypes: <String>['application/pdf'],
    uniformTypeIdentifiers: <String>['com.adobe.pdf'],
  );
  static const XTypeGroup invoiceFiles = XTypeGroup(
    label: 'Invoice photo or PDF',
    extensions: <String>['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    mimeTypes: <String>[
      'image/jpeg',
      'image/png',
      'image/webp',
      'application/pdf',
    ],
    uniformTypeIdentifiers: <String>[
      'public.jpeg',
      'public.png',
      'org.webmproject.webp',
      'com.adobe.pdf',
    ],
  );

  /// Checks [file]'s type and size; a photo [fromFiles] (the desktop's file
  /// picker gives the camera original, often several MB) is shrunk like the
  /// phone picker does. A name without an extension is taken as a PDF when
  /// [fromFiles], else a JPEG. Returns the upload, or the reason it can't be.
  static Future<(InvoiceUpload?, String?)> prepare(
    XFile file, {
    required bool fromFiles,
  }) async {
    String name = file.name.trim();
    if (!name.contains('.')) {
      name = '${name.isEmpty ? 'invoice' : name}.${fromFiles ? 'pdf' : 'jpg'}';
    }
    final String ext = name.split('.').last.toLowerCase();
    if (!extensions.contains(ext)) {
      return (null, 'Choose a JPG, PNG or WebP photo, or a PDF.');
    }
    final bool pdf = ext == 'pdf';
    Uint8List bytes = await file.readAsBytes();
    if (!pdf && fromFiles) {
      final Uint8List? small = await downscaleToJpeg(
        bytes,
        maxSide: maxImageSide,
        quality: 90,
      );
      if (small == null) {
        return (
          null,
          'Could not open this photo. Choose a JPG, PNG or WebP photo, or a PDF.',
        );
      }
      bytes = small;
      name = '${name.substring(0, name.lastIndexOf('.'))}.jpg';
    }
    if (bytes.length > (pdf ? maxPdfBytes : maxImageBytes)) {
      return (
        null,
        pdf
            ? 'This PDF is too large (10 MB at most).'
            : 'This photo is too large (7 MB at most).',
      );
    }
    return (InvoiceUpload(bytes, name), null);
  }
}
