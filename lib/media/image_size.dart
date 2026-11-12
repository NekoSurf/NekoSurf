import 'dart:io';
import 'dart:typed_data';

/// The width and height of the image in [file], read from the start of it
/// without decoding it, so that a grid can be laid out before its pictures
/// load. Knows JPEG, PNG, GIF and WebP; null for anything else, or a file
/// that isn't there.
Future<(int, int)?> imageSize(File file) async {
  RandomAccessFile? raf;
  try {
    raf = await file.open();
    // A JPEG's size can come after its metadata, which can be long.
    for (final int length in const [4096, 65536, 1 << 20]) {
      await raf.setPosition(0);
      final Uint8List head = await raf.read(length);
      final (int, int)? size = imageSizeOf(head);
      if (size != null) {
        return size;
      }
      if (head.length < length) {
        return null;
      }
    }
    return null;
  } on FileSystemException {
    return null;
  } finally {
    await raf?.close();
  }
}

/// The width and height an image's first bytes give, if they do.
(int, int)? imageSizeOf(Uint8List b) {
  int u16be(int i) => b[i] << 8 | b[i + 1];
  int u16le(int i) => b[i] | b[i + 1] << 8;
  int u24le(int i) => b[i] | b[i + 1] << 8 | b[i + 2] << 16;
  int u32be(int i) => u16be(i) << 16 | u16be(i + 2);
  (int, int)? sized(int w, int h) => w > 0 && h > 0 ? (w, h) : null;

  // PNG: the IHDR chunk comes first.
  if (b.length >= 24 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E) {
    return sized(u32be(16), u32be(20));
  }
  // GIF: the logical screen.
  if (b.length >= 10 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
    return sized(u16le(6), u16le(8));
  }
  // WebP, in a RIFF.
  if (b.length >= 30 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[8] == 0x57 &&
      b[9] == 0x45) {
    final String chunk = String.fromCharCodes(b.sublist(12, 16));
    switch (chunk) {
      case 'VP8 ':
        return sized(u16le(26) & 0x3FFF, u16le(28) & 0x3FFF);
      case 'VP8L':
        final int bits = b[21] | b[22] << 8 | b[23] << 16 | b[24] << 24;
        return sized((bits & 0x3FFF) + 1, (bits >> 14 & 0x3FFF) + 1);
      case 'VP8X':
        return sized(u24le(24) + 1, u24le(27) + 1);
    }
    return null;
  }
  // JPEG: the first start-of-frame marker.
  if (b.length >= 4 && b[0] == 0xFF && b[1] == 0xD8) {
    int i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        return null;
      }
      final int marker = b[i + 1];
      if (marker == 0xFF) {
        i++;
        continue;
      }
      final bool isFrame =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isFrame) {
        return sized(u16be(i + 7), u16be(i + 5));
      }
      i += 2 + u16be(i + 2);
    }
  }
  return null;
}
