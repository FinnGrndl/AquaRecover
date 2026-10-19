import 'dart:typed_data';

import 'package:aqua_recover/core/models/lut_profile.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/processing/lut_service.dart';
import 'package:aqua_recover/core/processing/underwater_processor.dart';
import 'package:aqua_recover/core/processing/video_lut_baker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _uniform(int r, int g, int b, {int size = 4}) {
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return image;
}

void main() {
  const processor = UnderwaterProcessor();
  final settings = const RestorationSettings().copyWith(
    sharpness: 0,
    clarity: 0,
    vignette: 0,
  );

  test('lattice nodes match the still renderer on flat regions', () {
    // Size 18 puts nodes on multiples of 15, so these colours are exact nodes
    // and no interpolation is involved.
    const size = 18;
    for (final colour in const [
      [30, 120, 165],
      [15, 90, 75],
      [210, 225, 240],
      [0, 0, 0],
    ]) {
      final image = _uniform(colour[0], colour[1], colour[2]);
      final expected = processor.restoreImage(image, settings).getPixel(1, 1);
      final lattice = processor.bakeColorLattice(image, settings, size: size);
      final r = colour[0] ~/ 15, g = colour[1] ~/ 15, b = colour[2] ~/ 15;
      final i = ((b * size + g) * size + r) * 3;
      expect(
        [lattice[i], lattice[i + 1], lattice[i + 2]],
        [expected.r, expected.g, expected.b],
        reason: 'colour $colour',
      );
    }
  });

  test('identity settings bake an identity cube', () {
    final lattice = processor.bakeColorLattice(
      _uniform(10, 80, 120),
      RestorationPreset.none.settings,
      size: 2,
    );
    expect(lattice, [
      0, 0, 0, 255, 0, 0, 0, 255, 0, 255, 255, 0, //
      0, 0, 255, 255, 0, 255, 0, 255, 255, 255, 255, 255,
    ]);
  });

  test('creative LUT is composed after the restoration', () async {
    final frame = _uniform(30, 120, 165);
    final plain = await const VideoLutBaker().bake([frame], settings, size: 5);
    final graded = await const VideoLutBaker().bake(
      [frame],
      settings,
      lutProfile: LutProfile.coralWarm,
      size: 5,
    );
    final expected = await const LutService().apply(
      img.Image.fromBytes(
        width: 5,
        height: 25,
        bytes: plain.rgb.buffer,
        numChannels: 3,
      ),
      LutProfile.coralWarm,
    );
    expect(graded.rgb, expected.toUint8List());
  });

  test('cube text and ARGB keep red-fastest order', () {
    final cube = ColorCube(
      2,
      Uint8List.fromList([
        255, 0, 0, 0, 255, 0, 0, 0, 255, 1, 2, 3, //
        4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
      ]),
    );
    final lines = cube.toCubeText().split('\n');
    expect(lines, contains('LUT_3D_SIZE 2'));
    final first = lines.indexOf('1.000000 0.000000 0.000000');
    expect(lines[first + 1], '0.000000 1.000000 0.000000');
    expect(cube.toArgb().first, 0xFFFF0000.toSigned(32));
    expect(cube.toArgb()[3], 0xFF010203.toSigned(32));
  });

  test('scene sample stacks frames at a common width', () {
    final sample = VideoLutBaker.sceneSample([
      img.Image(width: 800, height: 400),
      img.Image(width: 200, height: 100),
    ]);
    expect(sample.width, VideoLutBaker.sampleMaxDimension);
    expect(sample.height, 192 + 100);
  });
}
