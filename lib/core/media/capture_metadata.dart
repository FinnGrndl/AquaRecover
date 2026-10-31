import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/media_kind.dart';
import 'media_classifier.dart';

/// Reads the capture metadata of a source photo or video on the device.
///
/// Stills: EXIF from JPEG, TIFF-based RAW/TIFF, PNG `eXIf` and HEIC/HEIF
/// (the ISO base media `Exif` item). Videos: the QuickTime/MP4 `mvhd`
/// creation time. Every reader is best effort and returns `null` for
/// unsupported or damaged files instead of throwing.
class CaptureMetadata {
  const CaptureMetadata._();

  /// How much of a still is read to find its metadata. EXIF lives at the
  /// start of JPEG, TIFF and PNG files; HEIF items outside this window are
  /// read separately.
  static const headBytes = 4 * 1024 * 1024;

  /// Upper bound for a HEIF `Exif` item, which is far smaller in practice.
  static const maxExifItemBytes = 1024 * 1024;

  /// Returns the EXIF of an encoded still held in memory.
  static img.ExifData? exifFromBytes(Uint8List bytes) {
    try {
      if (_isJpeg(bytes)) return _nonEmpty(img.decodeJpgExif(bytes));
      if (_isTiff(bytes, 0)) return _exifAt(bytes, 0);
      if (_isPng(bytes)) return _pngExif(bytes);
      if (_isIsoMedia(bytes)) {
        final location = _heifExifLocation(bytes);
        if (location == null || location.end > bytes.length) return null;
        return _heifExifPayload(
          Uint8List.sublistView(bytes, location.offset, location.end),
        );
      }
    } on Object {
      // Damaged metadata must never fail an export.
    }
    return null;
  }

  /// Returns the EXIF of the still at [path] without reading the whole file.
  static Future<img.ExifData?> exifFromFile(String path) async {
    RandomAccessFile? file;
    try {
      file = await File(path).open();
      final length = await file.length();
      final head = await file.read(math.min(length, headBytes));
      final location = _isIsoMedia(head) ? _heifExifLocation(head) : null;
      if (location == null) return exifFromBytes(head);
      if (location.end > length ||
          location.end - location.offset > maxExifItemBytes) {
        return null;
      }
      await file.setPosition(location.offset);
      return _heifExifPayload(await file.read(location.end - location.offset));
    } on Object {
      return null;
    } finally {
      await file?.close();
    }
  }

  /// The moment [exif] says the photo was taken.
  ///
  /// EXIF stores local wall-clock time. When the camera also recorded the UTC
  /// offset (`OffsetTimeOriginal`), the result is exact; otherwise the time is
  /// read in the device's time zone, as photo libraries do.
  static DateTime? captureDate(img.ExifData exif) {
    final exifIfd = exif.exifIfd;
    final candidates = [
      (exifIfd[0x9003], exifIfd[0x9011]), // DateTimeOriginal, OffsetTime…
      (exifIfd[0x9004], exifIfd[0x9012]), // DateTimeDigitized
      (exif.imageIfd[0x0132], exifIfd[0x9010]), // DateTime
    ];
    for (final (value, offset) in candidates) {
      final parsed = parseExifDate(
        value?.toString(),
        offset: offset?.toString(),
      );
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// Parses an EXIF `YYYY:MM:DD HH:MM:SS` value with an optional `±HH:MM`.
  static DateTime? parseExifDate(String? value, {String? offset}) {
    final match = RegExp(
      r'^\s*(\d{4})[:\-](\d{2})[:\-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(value ?? '');
    if (match == null) return null;
    final n = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
    if (n[0] < 1900 || n[1] < 1 || n[1] > 12 || n[2] < 1 || n[2] > 31) {
      return null;
    }
    final zone = RegExp(r'^\s*([+-])(\d{2}):(\d{2})').firstMatch(offset ?? '');
    if (zone != null) {
      final sign = zone.group(1) == '-' ? -1 : 1;
      final minutes =
          int.parse(zone.group(2)!) * 60 + int.parse(zone.group(3)!);
      return DateTime.utc(
        n[0],
        n[1],
        n[2],
        n[3],
        n[4],
        n[5],
      ).subtract(Duration(minutes: sign * minutes));
    }
    return DateTime(n[0], n[1], n[2], n[3], n[4], n[5]);
  }

  /// The capture date of the photo or video at [path], if it records one.
  static Future<DateTime?> captureDateForFile(String path) async {
    final MediaKind kind;
    try {
      kind = MediaClassifier.classify(path);
    } on UnsupportedError {
      return null;
    }
    if (kind.isVideo) return videoCreationDate(path);
    final exif = await exifFromFile(path);
    return exif == null ? null : captureDate(exif);
  }

  /// The `mvhd` creation time of a QuickTime/MP4 file, which is stored in
  /// UTC. Zero or pre-1971 values (unset clocks) are ignored.
  static Future<DateTime?> videoCreationDate(String path) async {
    RandomAccessFile? file;
    try {
      file = await File(path).open();
      final length = await file.length();
      final moov = await _findBox(file, 0, length, 'moov');
      if (moov == null) return null;
      final mvhd = await _findBox(file, moov.$1, moov.$2, 'mvhd');
      if (mvhd == null) return null;
      await file.setPosition(mvhd.$1);
      final header = await file.read(12);
      if (header.length < 8) return null;
      final data = ByteData.sublistView(header);
      final seconds = data.getUint8(0) == 1 && header.length >= 12
          ? data.getUint64(4)
          : data.getUint32(4);
      // Seconds between 1904-01-01 (the QuickTime epoch) and 1970-01-01.
      const quickTimeEpochOffset = 2082844800;
      final unix = seconds - quickTimeEpochOffset;
      if (unix < 365 * 24 * 3600) return null;
      return DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true);
    } on Object {
      return null;
    } finally {
      await file?.close();
    }
  }

  /// Finds the first box named [type] between [start] and [end] and returns
  /// its payload range.
  static Future<(int, int)?> _findBox(
    RandomAccessFile file,
    int start,
    int end,
    String type,
  ) async {
    var offset = start;
    while (offset + 8 <= end) {
      await file.setPosition(offset);
      final header = await file.read(16);
      if (header.length < 8) return null;
      final data = ByteData.sublistView(header);
      var size = data.getUint32(0);
      var headerSize = 8;
      if (size == 1) {
        if (header.length < 16) return null;
        size = data.getUint64(8);
        headerSize = 16;
      } else if (size == 0) {
        size = end - offset;
      }
      if (size < headerSize || offset + size > end) return null;
      if (String.fromCharCodes(header, 4, 8) == type) {
        return (offset + headerSize, offset + size);
      }
      offset += size;
    }
    return null;
  }

  static img.ExifData? _nonEmpty(img.ExifData? exif) =>
      exif == null || exif.isEmpty ? null : exif;

  static img.ExifData? _exifAt(Uint8List bytes, int offset) {
    if (!_isTiff(bytes, offset)) return null;
    return _nonEmpty(
      img.ExifData.fromInputBuffer(
        img.InputBuffer(bytes, bigEndian: true, offset: offset),
      ),
    );
  }

  static bool _isJpeg(Uint8List b) =>
      b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;

  static bool _isTiff(Uint8List b, int o) =>
      b.length >= o + 8 &&
      ((b[o] == 0x49 &&
              b[o + 1] == 0x49 &&
              b[o + 2] == 0x2A &&
              b[o + 3] == 0) ||
          (b[o] == 0x4D &&
              b[o + 1] == 0x4D &&
              b[o + 2] == 0 &&
              b[o + 3] == 0x2A));

  static bool _isPng(Uint8List b) =>
      b.length > 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47;

  static bool _isIsoMedia(Uint8List b) =>
      b.length >= 12 && String.fromCharCodes(b, 4, 8) == 'ftyp';

  static img.ExifData? _pngExif(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    var offset = 8;
    while (offset + 12 <= bytes.length) {
      final length = data.getUint32(offset);
      final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
      final payload = offset + 8;
      if (payload + length > bytes.length) return null;
      if (type == 'eXIf') return _exifAt(bytes, payload);
      if (type == 'IDAT' || type == 'IEND') return null;
      offset = payload + length + 4;
    }
    return null;
  }

  /// Parses the payload of a HEIF `Exif` item: a 4-byte offset to the TIFF
  /// header, followed by the EXIF data.
  static img.ExifData? _heifExifPayload(Uint8List payload) {
    if (payload.length < 12) return null;
    final declared = ByteData.sublistView(payload).getUint32(0) + 4;
    if (_isTiff(payload, declared)) return _exifAt(payload, declared);
    for (var offset = 4; offset < math.min(payload.length - 8, 32); offset++) {
      if (_isTiff(payload, offset)) return _exifAt(payload, offset);
    }
    return null;
  }

  /// Locates the `Exif` item of a HEIF file through `meta` → `iinf`/`iloc`.
  /// The returned range is absolute within the file.
  static ({int offset, int end})? _heifExifLocation(Uint8List bytes) {
    try {
      final data = ByteData.sublistView(bytes);
      final meta = _boxIn(bytes, 0, bytes.length, 'meta');
      if (meta == null) return null;
      // `meta` is a full box: skip version and flags.
      final children = meta.$1 + 4;
      final iinf = _boxIn(bytes, children, meta.$2, 'iinf');
      final iloc = _boxIn(bytes, children, meta.$2, 'iloc');
      if (iinf == null || iloc == null) return null;

      int? exifItem;
      final iinfVersion = bytes[iinf.$1];
      var entry = iinf.$1 + (iinfVersion == 0 ? 6 : 8);
      while (exifItem == null && entry + 8 <= iinf.$2) {
        final size = data.getUint32(entry);
        if (size < 8 || entry + size > iinf.$2) break;
        if (String.fromCharCodes(bytes, entry + 4, entry + 8) == 'infe') {
          final version = bytes[entry + 8];
          var cursor = entry + 12;
          if (version >= 2) {
            final id = version == 2
                ? data.getUint16(cursor)
                : data.getUint32(cursor);
            cursor += (version == 2 ? 2 : 4) + 2;
            if (String.fromCharCodes(bytes, cursor, cursor + 4) == 'Exif') {
              exifItem = id;
            }
          }
        }
        entry += size;
      }
      if (exifItem == null) return null;

      final version = bytes[iloc.$1];
      var cursor = iloc.$1 + 4;
      final offsetSize = bytes[cursor] >> 4;
      final lengthSize = bytes[cursor] & 0x0F;
      final baseOffsetSize = bytes[cursor + 1] >> 4;
      final indexSize = version == 1 || version == 2
          ? bytes[cursor + 1] & 0x0F
          : 0;
      cursor += 2;
      int read(int size) {
        var value = 0;
        for (var i = 0; i < size; i++) {
          value = (value << 8) | bytes[cursor + i];
        }
        cursor += size;
        return value;
      }

      final itemCount = read(version < 2 ? 2 : 4);
      for (var i = 0; i < itemCount && cursor < iloc.$2; i++) {
        final id = read(version < 2 ? 2 : 4);
        final method = version == 1 || version == 2 ? read(2) & 0x0F : 0;
        read(2); // data_reference_index
        final baseOffset = read(baseOffsetSize);
        final extentCount = read(2);
        int? firstOffset;
        var totalLength = 0;
        for (var e = 0; e < extentCount; e++) {
          read(indexSize);
          final extentOffset = read(offsetSize);
          final extentLength = read(lengthSize);
          firstOffset ??= extentOffset;
          totalLength += extentLength;
        }
        if (id != exifItem) continue;
        // Only single-extent items stored in the file or in `idat`.
        if (extentCount != 1 || firstOffset == null || method > 1) return null;
        var start = baseOffset + firstOffset;
        if (method == 1) {
          final idat = _boxIn(bytes, children, meta.$2, 'idat');
          if (idat == null) return null;
          start += idat.$1;
        }
        return (offset: start, end: start + totalLength);
      }
    } on Object {
      return null;
    }
    return null;
  }

  static (int, int)? _boxIn(Uint8List bytes, int start, int end, String type) {
    final data = ByteData.sublistView(bytes);
    var offset = start;
    while (offset + 8 <= end) {
      var size = data.getUint32(offset);
      var headerSize = 8;
      if (size == 1) {
        if (offset + 16 > end) return null;
        size = data.getUint64(offset + 8);
        headerSize = 16;
      } else if (size == 0) {
        size = end - offset;
      }
      if (size < headerSize) return null;
      if (String.fromCharCodes(bytes, offset + 4, offset + 8) == type) {
        return (offset + headerSize, math.min(offset + size, end));
      }
      offset += size;
    }
    return null;
  }
}
