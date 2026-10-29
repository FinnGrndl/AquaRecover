import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../models/export_options.dart';

/// How [BeforeAfterCompositor] places the two photos.
enum BeforeAfterArrangement {
  /// Original on the left, restored on the right.
  sideBySide,

  /// Original on top, restored below.
  stacked,

  /// One frame: original left of the centre line, restored right of it.
  split,
}

/// Builds one comparison image from an original ("before") and a restored
/// ("after") photo for sharing.
///
/// Both photos must already carry the same crop and rotation; only the
/// colour differs. The result is a new image, so it has no EXIF of its own.
/// It is pure `package:image` code and runs in background isolates.
class BeforeAfterCompositor {
  const BeforeAfterCompositor({this.maxDimension = defaultMaxDimension});

  /// Long edge of the comparison image. Feeds show far less than this, and
  /// it bounds memory for two full-resolution panes.
  static const defaultMaxDimension = 4096;

  static const beforeLabel = 'Before';
  static const afterLabel = 'After';

  final int maxDimension;

  /// The arrangement [layout] resolves to for a [width]×[height] photo.
  ///
  /// Two panes double one side, so landscape photos are stacked and portrait
  /// or square photos sit next to each other: the result stays close to
  /// square instead of becoming a thin strip.
  static BeforeAfterArrangement arrangementFor(
    BeforeAfterLayout layout, {
    required int width,
    required int height,
  }) {
    if (layout == BeforeAfterLayout.split) return BeforeAfterArrangement.split;
    return width > height
        ? BeforeAfterArrangement.stacked
        : BeforeAfterArrangement.sideBySide;
  }

  /// The comparison of [before] and [after]. [before] is resized to the
  /// restored pane when the two renderers rounded its size differently.
  img.Image compose({
    required img.Image before,
    required img.Image after,
    BeforeAfterLayout layout = BeforeAfterLayout.sideBySide,
    bool labels = true,
  }) {
    final arrangement = arrangementFor(
      layout,
      width: after.width,
      height: after.height,
    );
    final columns = arrangement == BeforeAfterArrangement.sideBySide ? 2 : 1;
    final rows = arrangement == BeforeAfterArrangement.stacked ? 2 : 1;
    final scale = math.min(
      1.0,
      maxDimension / math.max(after.width * columns, after.height * rows),
    );
    final paneWidth = math.max(1, (after.width * scale).round());
    final paneHeight = math.max(1, (after.height * scale).round());
    final afterPane = _fit(after, paneWidth, paneHeight);
    final beforePane = _fit(before, paneWidth, paneHeight);
    final unit = math.min(paneWidth, paneHeight);

    if (arrangement == BeforeAfterArrangement.split) {
      final canvas = img.Image.from(afterPane);
      final half = paneWidth ~/ 2;
      if (half > 0) {
        img.compositeImage(
          canvas,
          beforePane,
          srcW: half,
          srcH: paneHeight,
          dstW: half,
          dstH: paneHeight,
          blend: img.BlendMode.direct,
        );
      }
      final line = math.max(2, (unit * .004).round());
      img.fillRect(
        canvas,
        x1: half - line ~/ 2,
        y1: 0,
        x2: half - line ~/ 2 + line - 1,
        y2: paneHeight - 1,
        color: _divider,
      );
      if (labels) {
        final label = _LabelMetrics(unit);
        _drawLabel(
          canvas,
          beforeLabel,
          left: label.margin,
          bottom: paneHeight - label.margin,
          metrics: label,
        );
        _drawLabel(
          canvas,
          afterLabel,
          right: paneWidth - label.margin,
          bottom: paneHeight - label.margin,
          metrics: label,
        );
      }
      return canvas;
    }

    final gap = math.max(2, (unit * .008).round());
    final stacked = arrangement == BeforeAfterArrangement.stacked;
    final width = stacked ? paneWidth : paneWidth * 2 + gap;
    final height = stacked ? paneHeight * 2 + gap : paneHeight;
    final canvas = img.Image(
      width: width,
      height: height,
      numChannels: afterPane.numChannels,
    );
    img.fill(canvas, color: _divider);
    final afterX = stacked ? 0 : paneWidth + gap;
    final afterY = stacked ? paneHeight + gap : 0;
    for (final (pane, x, y) in [
      (beforePane, 0, 0),
      (afterPane, afterX, afterY),
    ]) {
      img.compositeImage(
        canvas,
        pane,
        dstX: x,
        dstY: y,
        dstW: paneWidth,
        dstH: paneHeight,
        blend: img.BlendMode.direct,
      );
    }
    if (labels) {
      final label = _LabelMetrics(unit);
      _drawLabel(
        canvas,
        beforeLabel,
        left: label.margin,
        bottom: paneHeight - label.margin,
        metrics: label,
      );
      _drawLabel(
        canvas,
        afterLabel,
        left: afterX + label.margin,
        bottom: afterY + paneHeight - label.margin,
        metrics: label,
      );
    }
    return canvas;
  }

  static final _divider = img.ColorRgba8(255, 255, 255, 255);

  /// The in-app compare chip: black at 54 % behind white text, no shadow.
  static final _pillFill = img.ColorRgba8(0, 0, 0, 138);

  static img.Image _fit(img.Image source, int width, int height) {
    final uint8 = source.format == img.Format.uint8
        ? source
        : source.convert(format: img.Format.uint8);
    if (uint8.width == width && uint8.height == height) return uint8;
    final shrinking = width < uint8.width && height < uint8.height;
    return img.copyResize(
      uint8,
      width: width,
      height: height,
      interpolation: shrinking
          ? img.Interpolation.average
          : img.Interpolation.linear,
    );
  }

  /// Draws a rounded pill holding [text]. Exactly one of [left] and [right]
  /// is given; [bottom] is the pill's bottom edge.
  static void _drawLabel(
    img.Image canvas,
    String text, {
    required int bottom,
    required _LabelMetrics metrics,
    int? left,
    int? right,
  }) {
    final glyphs = _textImage(text, metrics.textHeight);
    final pillHeight = metrics.pillHeight;
    final pillWidth = glyphs.width + metrics.padding * 2;
    final x = left ?? right! - pillWidth;
    final y = bottom - pillHeight;
    // A photo too small for its label stays unlabelled.
    if (x < 0 || y < 0 || x + pillWidth > canvas.width) return;
    img.fillRect(
      canvas,
      x1: x,
      y1: y,
      x2: x + pillWidth - 1,
      y2: y + pillHeight - 1,
      radius: pillHeight / 2,
      color: _pillFill,
    );
    img.compositeImage(
      canvas,
      glyphs,
      dstX: x + metrics.padding,
      dstY: y + (pillHeight - glyphs.height) ~/ 2,
      dstW: glyphs.width,
      dstH: glyphs.height,
    );
  }

  /// White [text] on transparency, cropped to its ink and scaled to
  /// [height] pixels. Uses the smallest bundled font at least that tall so
  /// the glyphs are shrunk rather than enlarged whenever possible.
  static img.Image _textImage(String text, int height) {
    final font = [img.arial14, img.arial24, img.arial48].firstWhere(
      (font) => _inkHeight(font, text) >= height,
      orElse: () => img.arial48,
    );
    var top = font.lineHeight;
    var bottom = 0;
    var width = 0;
    for (final code in text.codeUnits) {
      final glyph = font.characters[code];
      if (glyph == null) continue;
      width += glyph.xAdvance;
      top = math.min(top, glyph.yOffset);
      bottom = math.max(bottom, glyph.yOffset + glyph.height);
    }
    final ink = img.Image(width: math.max(1, width), height: font.lineHeight);
    img.drawString(
      ink,
      text,
      font: font,
      x: 0,
      y: 0,
      color: img.ColorRgb8(255, 255, 255),
    );
    final inkHeight = math.max(1, bottom - top);
    final cropped = img.copyCrop(
      ink,
      x: 0,
      y: top,
      width: ink.width,
      height: inkHeight,
    );
    final alpha = img.Image(
      width: cropped.width,
      height: cropped.height,
      numChannels: 4,
    );
    for (final pixel in cropped) {
      alpha.setPixelRgba(pixel.x, pixel.y, 255, 255, 255, pixel.r);
    }
    if (inkHeight == height) return alpha;
    return img.copyResize(
      alpha,
      width: math.max(1, (alpha.width * height / inkHeight).round()),
      height: height,
      interpolation: height < inkHeight
          ? img.Interpolation.average
          : img.Interpolation.linear,
    );
  }

  static int _inkHeight(img.BitmapFont font, String text) {
    var top = font.lineHeight;
    var bottom = 0;
    for (final code in text.codeUnits) {
      final glyph = font.characters[code];
      if (glyph == null) continue;
      top = math.min(top, glyph.yOffset);
      bottom = math.max(bottom, glyph.yOffset + glyph.height);
    }
    return bottom - top;
  }
}

/// Label sizes relative to the shorter side of one pane: small enough to
/// stay out of the way, large enough to read in a feed.
class _LabelMetrics {
  factory _LabelMetrics(int unit) {
    final pillHeight = math.max(14, (unit * .05).round());
    return _LabelMetrics._(
      pillHeight: pillHeight,
      margin: math.max(6, (unit * .03).round()),
      textHeight: math.max(7, (pillHeight * .5).round()),
      padding: math.max(5, (pillHeight * .45).round()),
    );
  }

  const _LabelMetrics._({
    required this.pillHeight,
    required this.margin,
    required this.textHeight,
    required this.padding,
  });

  final int pillHeight;
  final int margin;
  final int textHeight;
  final int padding;
}
