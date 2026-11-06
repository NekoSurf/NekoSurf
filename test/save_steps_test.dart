import 'package:flutter_chan/saved/downloads.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('downloading fills the first half, converting the second', () {
    final List<double?> ring = <double?>[];
    final SaveSteps steps = SaveSteps(ring.add, converts: true);

    steps.download(0);
    steps.download(0.5);
    steps.download(1);
    steps.convert(0);
    steps.convert(0.5);
    steps.convert(1);

    expect(ring, [0, 0.25, 0.5, 0.5, 0.75, 1]);
  });

  test('with nothing to download, converting fills all of it', () {
    final List<double?> ring = <double?>[];
    final SaveSteps steps = SaveSteps(ring.add, converts: true);

    steps.convert(0);
    steps.convert(0.4);
    steps.convert(1);

    expect(ring, [0, 0.4, 1]);
  });

  test('with nothing to convert, downloading fills all of it', () {
    final List<double?> ring = <double?>[];
    final SaveSteps steps = SaveSteps(ring.add, converts: false);

    steps.download(0.3);
    steps.download(1);

    expect(ring, [0.3, 1]);
  });

  test('an unknown download size keeps the ring, an unknown length spins', () {
    final List<double?> ring = <double?>[];
    final SaveSteps steps = SaveSteps(ring.add, converts: true);

    steps.download(0.6);
    steps.download(null);
    steps.convert(null);

    expect(ring, [0.3, null]);
  });

  test('goes in whole percent', () {
    final List<double?> ring = <double?>[];
    final SaveSteps steps = SaveSteps(ring.add, converts: true);

    steps.download(0.333);
    steps.convert(0.333);

    expect(ring, [0.16, 0.66]);
  });

  test('a saved file takes the extension of what it holds', () {
    // Only iPhones convert webms; these tests don't run as one.
    expect(savedExtension('1700000000000.webm'), '.webm');
    expect(savedExtension('1700000000000.JPG'), '.jpg');
  });
}
