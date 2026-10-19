import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../../core/media/engine_image_decoder.dart';
import '../../../core/models/lut_profile.dart';
import '../../../core/models/restoration_settings.dart';
import '../../../core/processing/underwater_processor.dart';
import 'editor_glass_surface.dart';
import 'glass_navigation_bar.dart';
import 'restored_image_preview.dart';

typedef RgbaDecoder =
    Future<RgbaThumbnail?> Function(String path, int maxDimension);

/// Full-screen "tap something that should be white" picker. Each tap sets
/// [RestorationSettings.temperature] and [RestorationSettings.tint] so the
/// tapped area comes out neutral, and the edited preview updates under the
/// finger. Returns the new settings, or null when cancelled.
class NeutralPointPicker extends StatefulWidget {
  const NeutralPointPicker({
    super.key,
    required this.path,
    required this.settings,
    this.lutProfile = LutProfile.none,
    this.decoder = decodeRgbaThumbnail,
    this.previewBuilder,
  });

  final String path;
  final RestorationSettings settings;
  final LutProfile lutProfile;
  final RgbaDecoder decoder;

  /// Replaces the rendered preview, for tests.
  final Widget Function(RestorationSettings settings)? previewBuilder;

  /// Long side of the analysed thumbnail.
  static const sampleDimension = 1024;

  static Future<RestorationSettings?> show(
    BuildContext context, {
    required String path,
    required RestorationSettings settings,
    LutProfile lutProfile = LutProfile.none,
  }) {
    return Navigator.of(context).push<RestorationSettings>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => NeutralPointPicker(
          path: path,
          settings: settings,
          lutProfile: lutProfile,
        ),
      ),
    );
  }

  @override
  State<NeutralPointPicker> createState() => _NeutralPointPickerState();
}

class _NeutralPointPickerState extends State<NeutralPointPicker> {
  late RestorationSettings _settings = widget.settings;
  RgbaThumbnail? _thumbnail;
  img.Image? _sceneSample;
  Offset? _point;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final thumbnail = await widget.decoder(
        widget.path,
        NeutralPointPicker.sampleDimension,
      );
      if (!mounted) return;
      if (thumbnail == null) {
        setState(() => _error = 'This photo could not be read.');
        return;
      }
      setState(() {
        _thumbnail = thumbnail;
        _sceneSample = img.Image.fromBytes(
          width: thumbnail.width,
          height: thumbnail.height,
          bytes: Uint8List.fromList(thumbnail.rgba).buffer,
          numChannels: 4,
        );
      });
    } on Object {
      if (mounted) setState(() => _error = 'This photo could not be read.');
    }
  }

  /// Picks the neutral point at [point], in 0–1 image coordinates.
  void _pick(Offset point) {
    final thumbnail = _thumbnail;
    final sample = _sceneSample;
    if (thumbnail == null || sample == null) return;
    final u = point.dx.clamp(0.0, 1.0);
    final v = point.dy.clamp(0.0, 1.0);
    final (r, g, b) = averageAround(
      thumbnail,
      (u * (thumbnail.width - 1)).round(),
      (v * (thumbnail.height - 1)).round(),
    );
    final balance = const UnderwaterProcessor().neutralBalance(
      sample,
      _settings,
      r,
      g,
      b,
    );
    setState(() {
      _point = Offset(u, v);
      _settings = _settings.copyWith(
        temperature: balance.temperature,
        tint: balance.tint,
      );
    });
  }

  /// Mean colour of a small square around (x, y), so one noisy pixel does
  /// not decide the balance.
  static (int, int, int) averageAround(RgbaThumbnail thumbnail, int x, int y) {
    final radius = math.max(
      1,
      (math.max(thumbnail.width, thumbnail.height) * .012).round(),
    );
    var r = 0, g = 0, b = 0, n = 0;
    for (var yy = y - radius; yy <= y + radius; yy++) {
      if (yy < 0 || yy >= thumbnail.height) continue;
      for (var xx = x - radius; xx <= x + radius; xx++) {
        if (xx < 0 || xx >= thumbnail.width) continue;
        final i = (yy * thumbnail.width + xx) * 4;
        r += thumbnail.rgba[i];
        g += thumbnail.rgba[i + 1];
        b += thumbnail.rgba[i + 2];
        n++;
      }
    }
    if (n == 0) return (0, 0, 0);
    return ((r / n).round(), (g / n).round(), (b / n).round());
  }

  void _reset() => setState(() {
    _point = null;
    _settings = _settings.copyWith(temperature: 0, tint: 0);
  });

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    return CupertinoTheme(
      data: CupertinoTheme.of(context).copyWith(
        brightness: Brightness.dark,
        primaryColor: CupertinoColors.activeBlue,
      ),
      child: CupertinoPageScaffold(
        backgroundColor: CupertinoColors.black,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  0,
                  insets.top + 68,
                  0,
                  insets.bottom + 124,
                ),
                child: _imageArea(context),
              ),
              Positioned(
                top: insets.top + 8,
                left: 12,
                right: 12,
                child: GlassNavigationBar(
                  leadingKey: const Key('neutral_picker_cancel'),
                  leadingLabel: 'Cancel',
                  showBackChevron: false,
                  leadingWidth: 92,
                  onLeadingPressed: () => Navigator.of(context).pop(),
                  title: 'White balance',
                  subtitle: 'Tap something white or grey',
                  trailingWidth: 76,
                  trailing: CupertinoButton(
                    key: const Key('neutral_picker_done'),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(44, 44),
                    borderRadius: BorderRadius.circular(99),
                    color: CupertinoColors.activeBlue,
                    onPressed: () => Navigator.of(context).pop(_settings),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        color: CupertinoColors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: insets.bottom + 12,
                child: EditorGlassSurface(
                  borderRadius: 24,
                  padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Temperature ${_signed(_settings.temperature)}  ·  '
                              'Tint ${_signed(_settings.tint)}',
                              key: const Key('neutral_picker_values'),
                              style: const TextStyle(
                                color: CupertinoColors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _error ??
                                  'Sand, a slate, or a tank work well. '
                                      'Drag to compare spots.',
                              style: TextStyle(
                                color: CupertinoColors.white.withValues(
                                  alpha: .72,
                                ),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      CupertinoButton(
                        key: const Key('neutral_picker_reset'),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        onPressed: _settings.hasWhiteBalance ? _reset : null,
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageArea(BuildContext context) {
    final thumbnail = _thumbnail;
    if (thumbnail == null) {
      return Center(
        child: _error == null
            ? const CupertinoActivityIndicator(color: CupertinoColors.white)
            : const Icon(
                CupertinoIcons.exclamationmark_triangle,
                color: CupertinoColors.white,
              ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        final fitted = applyBoxFit(
          BoxFit.contain,
          Size(thumbnail.width.toDouble(), thumbnail.height.toDouble()),
          box,
        ).destination;
        final rect = Alignment.center.inscribe(fitted, Offset.zero & box);
        Offset normalised(Offset local) => Offset(
          (local.dx - rect.left) / rect.width,
          (local.dy - rect.top) / rect.height,
        );
        final point = _point;
        return GestureDetector(
          key: const Key('neutral_picker_canvas'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _pick(normalised(details.localPosition)),
          onPanUpdate: (details) => _pick(normalised(details.localPosition)),
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child:
                    widget.previewBuilder?.call(_settings) ??
                    RestoredImagePreview(
                      path: widget.path,
                      settings: _settings,
                      lutProfile: widget.lutProfile,
                    ),
              ),
              if (point != null)
                Positioned(
                  left: rect.left + point.dx * rect.width - 18,
                  top: rect.top + point.dy * rect.height - 18,
                  width: 36,
                  height: 36,
                  child: const IgnorePointer(child: _Reticle()),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _signed(double value) {
    final text = (value * 100).round();
    // A real minus sign lines up with the plus in tabular figures.
    return text > 0 ? '+$text' : (text < 0 ? '\u2212${-text}' : '0');
  }
}

class _Reticle extends StatelessWidget {
  const _Reticle();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _ReticlePainter());
  }
}

/// A white ring and centre dot, each over a slightly wider dark stroke, like
/// the crop overlay's lines. The crisp outline keeps the marker visible on
/// any colour without a blurred shadow darkening the patch being judged.
class _ReticlePainter extends CustomPainter {
  const _ReticlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2;
    final outline = Paint()
      ..color = CupertinoColors.black.withValues(alpha: .5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final ring = Paint()
      ..color = CupertinoColors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, outline);
    canvas.drawCircle(center, radius, ring);
    canvas.drawCircle(
      center,
      3,
      Paint()..color = CupertinoColors.black.withValues(alpha: .5),
    );
    canvas.drawCircle(center, 2, Paint()..color = CupertinoColors.white);
  }

  @override
  bool shouldRepaint(_ReticlePainter oldDelegate) => false;
}
