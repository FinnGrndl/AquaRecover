import 'dart:io';
import 'dart:typed_data';

import 'package:aqua_recover/core/media/capture_metadata.dart';
import 'package:aqua_recover/core/models/export_options.dart';
import 'package:aqua_recover/core/models/media_kind.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/photo/photo_library_service.dart';
import 'package:aqua_recover/core/processing/export_metadata.dart';
import 'package:aqua_recover/core/processing/image_restoration_service.dart';
import 'package:aqua_recover/core/processing/still_render_pipeline.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

const _keep = ExportOptions(stripMetadata: false);

/// A 6×4 JPEG stored sideways (orientation 6), so it decodes upright as 4×6.
Uint8List _diveJpeg() {
  final image = img.Image(width: 6, height: 4);
  img.fill(image, color: img.ColorRgb8(20, 90, 120));
  final exif = image.exif;
  exif.imageIfd
    ..orientation = 6
    ..make = 'OM Digital Solutions'
    ..model = 'TG-7';
  exif.imageIfd[0x0100] = img.IfdValueLong(6); // ImageWidth
  exif.exifIfd
    ..[0x9003] =
        img.IfdValueAscii('2026:03:14 10:15:30') // DateTimeOriginal
    ..[0x9011] =
        img.IfdValueAscii('+07:00') // OffsetTimeOriginal
    ..[0x829A] =
        img.IfdValueRational(1, 125) // ExposureTime
    ..[0x8827] =
        img.IfdValueShort(400) // ISO
    ..[0xA434] =
        img.IfdValueAscii('4.5-18mm') // LensModel
    ..[0xA002] = img.IfdValueLong(6)
    ..[0xA003] = img.IfdValueLong(4)
    ..[0x927C] = img.IfdValueUndefined.list(Uint8List(16)); // MakerNote
  exif.gpsIfd
    ..[0x0001] = img.IfdValueAscii('S')
    ..[0x0002] = _rationals([8, 20, 0])
    ..[0x0003] = img.IfdValueAscii('E')
    ..[0x0004] = _rationals([115, 30, 0]);
  exif.thumbnailIfd[0x0103] = img.IfdValueShort(6);
  exif.thumbnailData = Uint8List.fromList(
    img.encodeJpg(img.Image(width: 2, height: 2)),
  );
  return Uint8List.fromList(img.encodeJpg(image));
}

img.IfdValue _rationals(List<int> values) => img.IfdValueRational.list([
  for (final value in values) img.IfdValueRational(value, 1).toRational(),
]);

final _diveMoment = DateTime.utc(2026, 3, 14, 3, 15, 30);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the source JPEG fixture carries the metadata under test', () {
    final exif = img.decodeJpgExif(_diveJpeg())!;
    expect(exif.imageIfd.orientation, 6);
    expect(exif.thumbnailData, isNotNull);
    expect(exif.exifIfd.containsKey(0x927C), isTrue);
    expect(exif.gpsIfd.containsKey(0x0002), isTrue);
  });

  group('still export metadata', () {
    test(
      'JPEG export keeps date, camera, exposure and GPS but not rotation',
      () async {
        final output = await const StillRenderPipeline().renderEncoded(
          _diveJpeg(),
          settings: const RestorationSettings(),
          exportOptions: _keep,
        );

        final decoded = img.decodeJpg(output)!;
        expect((decoded.width, decoded.height), (4, 6));

        final exif = img.decodeJpgExif(output)!;
        expect(exif.imageIfd.orientation, 1);
        expect(exif.imageIfd.make, 'OM Digital Solutions');
        expect(exif.imageIfd.model, 'TG-7');
        expect(exif.exifIfd[0x9003].toString(), '2026:03:14 10:15:30');
        expect(exif.exifIfd[0x829A]!.toRational().denominator, 125);
        expect(exif.exifIfd[0x8827]!.toInt(), 400);
        expect(exif.exifIfd[0xA434].toString(), '4.5-18mm');
        expect(exif.exifIfd[0xA002]!.toInt(), 4);
        expect(exif.exifIfd[0xA003]!.toInt(), 6);
        expect(exif.gpsIfd[0x0001].toString(), 'S');
        expect(exif.gpsIfd[0x0002]!.toRational(1).toInt(), 20);
        expect(exif.gpsIfd[0x0004]!.toRational().toInt(), 115);
        expect(exif.exifIfd.containsKey(0x927C), isFalse);
        expect(exif.imageIfd.containsKey(0x0100), isFalse);
        expect(exif.thumbnailData, isNull);
        expect(exif.directories.containsKey('ifd1'), isFalse);
        expect(CaptureMetadata.captureDate(exif), _diveMoment);
      },
    );

    test('Strip metadata exports carry no EXIF', () async {
      final output = await const StillRenderPipeline().renderEncoded(
        _diveJpeg(),
        settings: const RestorationSettings(),
      );

      final exif = img.decodeJpgExif(output);
      expect(exif == null || exif.isEmpty, isTrue);
      final decoded = img.decodeJpg(output)!;
      expect((decoded.width, decoded.height), (4, 6));
    });

    test('PNG export keeps the metadata in an eXIf chunk', () async {
      final output = await const StillRenderPipeline().renderEncoded(
        _diveJpeg(),
        settings: const RestorationSettings(),
        exportOptions: _keep.copyWith(imageFormat: ImageOutputFormat.png),
      );

      final decoded = img.decodePng(output)!;
      expect((decoded.width, decoded.height), (4, 6));
      final exif = CaptureMetadata.exifFromBytes(output)!;
      expect(exif.imageIfd.orientation, 1);
      expect(exif.gpsIfd[0x0001].toString(), 'S');
      expect(CaptureMetadata.captureDate(exif), _diveMoment);
      // eXIf must precede the image data.
      final text = String.fromCharCodes(output);
      expect(text.indexOf('eXIf'), lessThan(text.indexOf('IDAT')));
      expect(text.indexOf('eXIf'), greaterThan(text.indexOf('IHDR')));
    });

    test('an intermediate decode takes the original file metadata', () async {
      final source = img.decodeJpg(_diveJpeg())!;
      final intermediate = img.encodePng(img.Image.from(source)..exif.clear());

      final output = await const StillRenderPipeline().renderEncoded(
        intermediate,
        settings: const RestorationSettings(),
        exportOptions: _keep,
        sourceExif: img.decodeJpgExif(_diveJpeg()),
      );

      final exif = img.decodeJpgExif(output)!;
      expect(exif.imageIfd.orientation, 1);
      expect(exif.imageIfd.model, 'TG-7');
      expect(CaptureMetadata.captureDate(exif), _diveMoment);
    });

    test('a file export with a metadata source keeps its EXIF', () async {
      final dir = await Directory.systemTemp.createTemp('aqua_meta_');
      addTearDown(() => dir.delete(recursive: true));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(
        pathProvider,
        (call) async => dir.path,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(pathProvider, null));

      final original = File(p.join(dir.path, 'dive.jpg'))
        ..writeAsBytesSync(_diveJpeg());
      final intermediate = File(p.join(dir.path, 'dive.decoded.png'))
        ..writeAsBytesSync(
          img.encodePng(img.decodeJpg(_diveJpeg())!..exif.clear()),
        );

      final output = await const ImageRestorationService().restoreFile(
        intermediate.path,
        const RestorationSettings(),
        exportOptions: _keep,
        metadataSourcePath: original.path,
      );

      final exif = img.decodeJpgExif(File(output).readAsBytesSync())!;
      expect(exif.imageIfd.orientation, 1);
      expect(CaptureMetadata.captureDate(exif), _diveMoment);
    });

    test('forExport returns null without source metadata', () {
      expect(ExportMetadata.forExport(null, width: 1, height: 1), isNull);
      expect(
        ExportMetadata.forExport(img.ExifData(), width: 1, height: 1),
        isNull,
      );
    });
  });

  group('capture dates', () {
    test('EXIF dates honor the recorded UTC offset', () {
      expect(
        CaptureMetadata.parseExifDate('2026:03:14 10:15:30', offset: '+07:00'),
        _diveMoment,
      );
      expect(
        CaptureMetadata.parseExifDate('2026:03:14 10:15:30', offset: '-03:30'),
        DateTime.utc(2026, 3, 14, 13, 45, 30),
      );
      expect(
        CaptureMetadata.parseExifDate('2026:03:14 10:15:30'),
        DateTime(2026, 3, 14, 10, 15, 30),
      );
      expect(CaptureMetadata.parseExifDate('0000:00:00 00:00:00'), isNull);
      expect(CaptureMetadata.parseExifDate(null), isNull);
    });

    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('aqua_capture_');
    });
    tearDown(() => dir.delete(recursive: true));

    test('reads the date of a JPEG file', () async {
      final file = File(p.join(dir.path, 'reef.JPG'))
        ..writeAsBytesSync(_diveJpeg());
      expect(await CaptureMetadata.captureDateForFile(file.path), _diveMoment);
    });

    test('reads the Exif item of a HEIC file', () async {
      final tiff = img.OutputBuffer(bigEndian: true);
      img.decodeJpgExif(_diveJpeg())!.write(tiff);
      final file = File(p.join(dir.path, 'reef.heic'))
        ..writeAsBytesSync(_heif(tiff.getBytes()));

      final exif = await CaptureMetadata.exifFromFile(file.path);
      expect(exif?.imageIfd.model, 'TG-7');
      expect(await CaptureMetadata.captureDateForFile(file.path), _diveMoment);
    });

    test('reads the mvhd creation time of a video', () async {
      final file = File(p.join(dir.path, 'dive.mov'))
        ..writeAsBytesSync(_movie(_diveMoment));
      expect(await CaptureMetadata.captureDateForFile(file.path), _diveMoment);

      final unset = File(p.join(dir.path, 'unset.mp4'))
        ..writeAsBytesSync(_movie(null));
      expect(await CaptureMetadata.videoCreationDate(unset.path), isNull);
    });

    test('unknown or damaged files have no capture date', () async {
      final garbage = File(p.join(dir.path, 'broken.jpg'))
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE1, 0, 2, 1]);
      final text = File(p.join(dir.path, 'notes.txt'))..writeAsStringSync('x');
      expect(await CaptureMetadata.captureDateForFile(garbage.path), isNull);
      expect(await CaptureMetadata.captureDateForFile(text.path), isNull);
      expect(
        await CaptureMetadata.captureDateForFile(p.join(dir.path, 'gone.mp4')),
        isNull,
      );
    });
  });

  test('saving to the library passes the capture date', () async {
    final dir = await Directory.systemTemp.createTemp('aqua_save_');
    addTearDown(() => dir.delete(recursive: true));
    final photo = File(p.join(dir.path, 'reef_aqua.jpg'))
      ..writeAsBytesSync(_diveJpeg());
    final video = File(p.join(dir.path, 'reef_aqua.mp4'))
      ..writeAsBytesSync(_movie(_diveMoment));
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('com.fluttercandies/photo_manager');
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'requestPermissionExtend') return 3; // authorized
      return <String, Object?>{'id': '1', 'type': 1, 'width': 4, 'height': 6};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    const service = PhotoLibraryService();
    await service.saveExport(
      photo.path,
      MediaKind.photo,
      creationDate: _diveMoment,
    );
    await service.saveExport(
      video.path,
      MediaKind.video,
      creationDate: _diveMoment,
    );

    final saves = calls.where((call) => call.method.startsWith('save'));
    expect(saves.map((call) => call.method), [
      'saveImageWithPath',
      'saveVideo',
    ]);
    for (final call in saves) {
      final args = call.arguments as Map;
      expect(args['creationDate'], _diveMoment.millisecondsSinceEpoch);
      expect(args['latitude'], isNull);
    }
  });
}

Uint8List _box(String type, List<int> payload) {
  final out = BytesBuilder()
    ..add(_u32(payload.length + 8))
    ..add(type.codeUnits)
    ..add(payload);
  return out.toBytes();
}

List<int> _u32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _u16(int value) => [(value >> 8) & 0xFF, value & 0xFF];

/// A minimal HEIF container whose `Exif` item lives in `mdat`.
Uint8List _heif(Uint8List tiff) {
  final ftyp = _box('ftyp', [...'heic'.codeUnits, 0, 0, 0, 0]);
  final infe = _box('infe', [
    2,
    0,
    0,
    0,
    ..._u16(1),
    ..._u16(0),
    ...'Exif'.codeUnits,
    0,
  ]);
  final iinf = _box('iinf', [0, 0, 0, 0, ..._u16(1), ...infe]);
  final payload = [0, 0, 0, 6, ...'Exif'.codeUnits, 0, 0, ...tiff];
  Uint8List meta(int exifOffset) {
    final iloc = _box('iloc', [
      0, 0, 0, 0, // version 0
      0x44, 0x00, // offset_size 4, length_size 4, base_offset_size 0
      ..._u16(1), // item_count
      ..._u16(1), // item_ID
      ..._u16(0), // data_reference_index
      ..._u16(1), // extent_count
      ..._u32(exifOffset),
      ..._u32(payload.length),
    ]);
    final hdlr = _box('hdlr', [0, 0, 0, 0, 0, 0, 0, 0, ...'pict'.codeUnits]);
    return _box('meta', [0, 0, 0, 0, ...hdlr, ...iinf, ...iloc]);
  }

  final metaLength = meta(0).length;
  final exifOffset = ftyp.length + metaLength + 8;
  return Uint8List.fromList([
    ...ftyp,
    ...meta(exifOffset),
    ..._box('mdat', payload),
  ]);
}

/// A minimal QuickTime file with an `mvhd` creation time.
Uint8List _movie(DateTime? created) {
  final seconds = created == null
      ? 0
      : created.millisecondsSinceEpoch ~/ 1000 + 2082844800;
  final mvhd = _box('mvhd', [
    0, 0, 0, 0, // version 0
    ..._u32(seconds), // creation_time
    ..._u32(seconds), // modification_time
    ..._u32(600), // timescale
    ..._u32(600), // duration
    ...List<int>.filled(80, 0),
  ]);
  return Uint8List.fromList([
    ..._box('ftyp', [...'qt  '.codeUnits, 0, 0, 0, 0]),
    ..._box('mdat', List<int>.filled(32, 0)),
    ..._box('moov', mvhd),
  ]);
}
