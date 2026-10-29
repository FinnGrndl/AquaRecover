import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Prepares source EXIF for a restored export and writes it into JPEG or PNG
/// bytes.
///
/// Rendering bakes the source orientation into the pixels and may crop or
/// resize them, so only descriptive metadata is carried over: capture date,
/// camera and lens, exposure, GPS and copyright. Orientation is reset to 1,
/// the pixel size is rewritten, and thumbnails, maker notes and TIFF layout
/// tags that describe the original pixels are dropped.
class ExportMetadata {
  const ExportMetadata._();

  /// IFD0 tags that describe the photo rather than its pixel layout.
  static const keptImageTags = <int>{
    0x010E, // ImageDescription
    0x010F, // Make
    0x0110, // Model
    0x011A, // XResolution
    0x011B, // YResolution
    0x0128, // ResolutionUnit
    0x0131, // Software
    0x0132, // DateTime
    0x013B, // Artist
    0x8298, // Copyright
  };

  /// EXIF sub-IFD tags that would be wrong or dangling after rendering.
  static const droppedExifTags = <int>{
    0x927C, // MakerNote: vendor offsets point into the source file.
    0xA005, // Interoperability IFD pointer
    0xA002, // PixelXDimension (rewritten)
    0xA003, // PixelYDimension (rewritten)
    0x9214, // SubjectArea: coordinates in the source pixel grid.
    0xA214, // SubjectLocation
  };

  /// IFD0 tags kept by a comparison export: only when it was taken.
  static const captureDateImageTags = <int>{
    0x0132, // DateTime
  };

  /// EXIF sub-IFD tags kept by a comparison export.
  static const captureDateExifTags = <int>{
    0x9003, // DateTimeOriginal
    0x9004, // DateTimeDigitized
    0x9010, // OffsetTime
    0x9011, // OffsetTimeOriginal
    0x9012, // OffsetTimeDigitized
    0x9290, // SubSecTime
    0x9291, // SubSecTimeOriginal
    0x9292, // SubSecTimeDigitized
  };

  /// A sanitized copy of [source] for an upright export of [width]×[height].
  /// Returns `null` when [source] carries nothing worth keeping.
  ///
  /// [captureDateOnly] keeps nothing but the capture date and time. A
  /// before/after comparison is a new image, so camera, exposure and GPS
  /// tags no longer describe it, but it should still sort by the dive.
  static img.ExifData? forExport(
    img.ExifData? source, {
    required int width,
    required int height,
    bool captureDateOnly = false,
  }) {
    if (source == null || source.isEmpty) return null;
    final result = img.ExifData();
    final sourceImage = source.directories['ifd0'];
    final image = result.imageIfd;
    if (sourceImage != null && captureDateOnly) {
      for (final tag in captureDateImageTags) {
        final value = sourceImage.data[tag];
        if (value != null) image.data[tag] = value.clone();
      }
      final exif = sourceImage.sub.directories['exif'];
      if (exif != null) {
        for (final tag in captureDateExifTags) {
          final value = exif.data[tag];
          if (value != null) result.exifIfd.data[tag] = value.clone();
        }
      }
    } else if (sourceImage != null) {
      for (final tag in keptImageTags) {
        final value = sourceImage.data[tag];
        if (value != null) image.data[tag] = value.clone();
      }
      final exif = sourceImage.sub.directories['exif'];
      if (exif != null) {
        for (final entry in exif.data.entries) {
          if (droppedExifTags.contains(entry.key)) continue;
          result.exifIfd.data[entry.key] = entry.value.clone();
        }
      }
      final gps = sourceImage.sub.directories['gps'];
      if (gps != null && !gps.isEmpty) {
        for (final entry in gps.data.entries) {
          result.gpsIfd.data[entry.key] = entry.value.clone();
        }
      }
    }
    if (image.isEmpty && result.exifIfd.isEmpty) return null;
    // Pixels are already upright; a carried-over rotation would turn them
    // a second time.
    image.orientation = 1;
    result.exifIfd.data[0xA002] = img.IfdValueLong(width);
    result.exifIfd.data[0xA003] = img.IfdValueLong(height);
    return result;
  }

  /// Writes [exif] into [encoded] JPEG or PNG bytes, replacing any EXIF the
  /// encoder wrote. Unknown formats are returned unchanged.
  static Uint8List embed(Uint8List encoded, img.ExifData exif) {
    if (encoded.length > 2 && encoded[0] == 0xFF && encoded[1] == 0xD8) {
      return img.injectJpgExif(encoded, exif) ?? encoded;
    }
    if (encoded.length > 8 && encoded[0] == 0x89 && encoded[1] == 0x50) {
      return _embedPng(encoded, exif);
    }
    return encoded;
  }

  /// Inserts an `eXIf` chunk after `IHDR` and drops existing ones.
  static Uint8List _embedPng(Uint8List png, img.ExifData exif) {
    final payload = img.OutputBuffer(bigEndian: true);
    exif.write(payload);
    final exifBytes = payload.getBytes();
    final data = ByteData.sublistView(png);
    final out = BytesBuilder(copy: false)
      ..add(Uint8List.sublistView(png, 0, 8));
    var offset = 8;
    var inserted = false;
    while (offset + 12 <= png.length) {
      final length = data.getUint32(offset);
      final end = offset + 12 + length;
      if (end > png.length) return png;
      final type = String.fromCharCodes(png, offset + 4, offset + 8);
      if (type != 'eXIf') out.add(Uint8List.sublistView(png, offset, end));
      if (type == 'IHDR' && !inserted) {
        out.add(_pngChunk('eXIf', exifBytes));
        inserted = true;
      }
      offset = end;
    }
    return inserted ? out.takeBytes() : png;
  }

  static Uint8List _pngChunk(String type, Uint8List payload) {
    final typeBytes = Uint8List.fromList(type.codeUnits);
    final chunk = Uint8List(12 + payload.length);
    final data = ByteData.sublistView(chunk)..setUint32(0, payload.length);
    chunk
      ..setRange(4, 8, typeBytes)
      ..setRange(8, 8 + payload.length, payload);
    data.setUint32(8 + payload.length, _crc32(chunk, 4, 8 + payload.length));
    return chunk;
  }

  static final List<int> _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int _crc32(Uint8List bytes, int start, int end) {
    var crc = 0xFFFFFFFF;
    for (var i = start; i < end; i++) {
      crc = _crcTable[(crc ^ bytes[i]) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }
}
