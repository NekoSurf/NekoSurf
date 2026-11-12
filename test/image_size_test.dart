import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_chan/media/image_size.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(List<int> b) =>
    Uint8List.fromList([...b, ...List.filled(64, 0)]);

void main() {
  test('reads the size of a PNG', () {
    final List<int> png = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, //
      0, 0, 0x02, 0x80, 0, 0, 0x01, 0xE0, // 640 × 480
    ];
    expect(imageSizeOf(bytes(png)), (640, 480));
  });

  test('reads the size of a GIF', () {
    final List<int> gif = [...'GIF89a'.codeUnits, 0x2C, 0x01, 0x90, 0x01];
    expect(imageSizeOf(bytes(gif)), (300, 400));
  });

  test('reads the size of a JPEG past its metadata', () {
    final List<int> jpeg = [
      0xFF, 0xD8, //
      0xFF, 0xE1, 0x00, 0x06, 1, 2, 3, 4, // a short APP1
      0xFF, 0xC2, 0x00, 0x11, 0x08, 0x03, 0x20, 0x04, 0xB0, // 1200 × 800
    ];
    expect(imageSizeOf(bytes(jpeg)), (1200, 800));
  });

  test('reads the size of an extended WebP', () {
    final List<int> webp = [
      ...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits, //
      ...'VP8X'.codeUnits, 10, 0, 0, 0, 0, 0, 0, 0, //
      0x1F, 0x03, 0x00, 0xDF, 0x01, 0x00, // 800 × 480, each less one
    ];
    expect(imageSizeOf(bytes(webp)), (800, 480));
  });

  test('knows nothing of what is not an image', () async {
    expect(imageSizeOf(bytes('hello'.codeUnits)), isNull);
    expect(await imageSize(File('/no/such/file.jpg')), isNull);
  });
}
