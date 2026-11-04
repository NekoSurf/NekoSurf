import 'package:flutter/material.dart';
import 'package:flutter_chan/pages/media/shared_media_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const Size screen = Size(400, 800);

  group('fittedImageSize', () {
    test('leaves an image that fits at its own size', () {
      expect(
        fittedImageSize(const Size(200, 100), screen),
        const Size(200, 100),
      );
    });

    test('shrinks a wide image to the width of the screen', () {
      expect(
        fittedImageSize(const Size(2000, 1000), screen),
        const Size(400, 200),
      );
    });

    test('shrinks a tall image to the height of the screen', () {
      expect(
        fittedImageSize(const Size(1000, 4000), screen),
        const Size(200, 800),
      );
    });
  });
}
