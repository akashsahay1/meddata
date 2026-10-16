import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:medikabiz/services/image_downscale.dart';

void main() {
  Future<img.Image> shrink(Uint8List bytes, int maxSide) async {
    final Uint8List? out =
        await downscaleToJpeg(bytes, maxSide: maxSide, quality: 85);
    expect(out, isNotNull);
    expect(out!.sublist(0, 3), <int>[0xFF, 0xD8, 0xFF]); // JPEG
    return img.decodeJpg(out)!;
  }

  test('a big photo is shrunk to the bound, keeping its shape', () async {
    final img.Image wide = await shrink(
        img.encodePng(img.Image(width: 4000, height: 3000)), 2576);
    expect(<int>[wide.width, wide.height], <int>[2576, 1932]);

    final img.Image tall =
        await shrink(img.encodeJpg(img.Image(width: 600, height: 1200)), 512);
    expect(<int>[tall.width, tall.height], <int>[256, 512]);
  });

  test('a small picture keeps its size', () async {
    final img.Image small =
        await shrink(img.encodePng(img.Image(width: 300, height: 200)), 512);
    expect(<int>[small.width, small.height], <int>[300, 200]);
  });

  test('BMP and GIF pictures come out as JPEG', () async {
    final img.Image bmp =
        await shrink(img.encodeBmp(img.Image(width: 1024, height: 1024)), 512);
    expect(bmp.width, 512);
    final img.Image gif =
        await shrink(img.encodeGif(img.Image(width: 800, height: 400)), 512);
    expect(<int>[gif.width, gif.height], <int>[512, 256]);
  });

  test('a file that is not a picture gives null', () async {
    expect(
      await downscaleToJpeg(Uint8List.fromList(<int>[1, 2, 3, 4]),
          maxSide: 512, quality: 85),
      isNull,
    );
  });
}
