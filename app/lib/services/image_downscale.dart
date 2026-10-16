import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Re-encodes a photo (JPG, PNG, WebP, BMP, GIF, TIFF…) as a JPEG whose
/// longest side is at most [maxSide] px, turned upright from its EXIF
/// orientation. Null when [bytes] is not an image this can read.
///
/// The phone picker can shrink on its own, but the Windows one ignores
/// maxWidth/imageQuality and lets any picture through, so uploads go
/// through this. Decoding runs off the UI thread.
Future<Uint8List?> downscaleToJpeg(
  Uint8List bytes, {
  required int maxSide,
  required int quality,
}) => compute(_downscale, (bytes, maxSide, quality));

Uint8List? _downscale((Uint8List, int, int) args) {
  final (Uint8List bytes, int maxSide, int quality) = args;
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null; // some format probes throw on bytes that aren't theirs
  }
  if (decoded == null) return null;
  img.Image image = img.bakeOrientation(decoded);
  if (image.width > maxSide || image.height > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
  }
  return img.encodeJpg(image, quality: quality);
}
