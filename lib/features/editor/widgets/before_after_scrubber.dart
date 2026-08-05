import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as p;

import '../../../core/media/media_classifier.dart';
import '../../../core/models/image_transform_settings.dart';
import '../../../core/models/media_kind.dart';
import 'image_transform_preview.dart';

class BeforeAfterScrubber extends StatefulWidget {
  const BeforeAfterScrubber({
    super.key,
    required this.originalPath,
    required this.restoredPath,
    required this.kind,
    this.aspectRatio = 4 / 3,
    this.sourceAspectRatio = 4 / 3,
    this.transform = const ImageTransformSettings(),
  });
  final String originalPath;
  final String restoredPath;
  final MediaKind kind;
  final double aspectRatio;
  final double sourceAspectRatio;
  final ImageTransformSettings transform;
  @override
  State<BeforeAfterScrubber> createState() => _BeforeAfterScrubberState();
}

class _BeforeAfterScrubberState extends State<BeforeAfterScrubber> {
  double _split = 0.5;
  @override
  Widget build(BuildContext context) {
    if (!widget.kind.isImage || _isRaw(widget.originalPath)) {
      return _staticResult(context);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Before / after',
              style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
            ),
            const Spacer(),
            Text('${(_split * 100).round()}%'),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: widget.aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ColoredBox(
                  color: CupertinoColors.black,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(widget.restoredPath),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => _previewError(
                              context,
                              'Restored preview unavailable',
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: constraints.maxWidth * _split,
                            child: ClipRect(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: constraints.maxWidth,
                                  height: constraints.maxHeight,
                                  child: ImageTransformPreview(
                                    settings: widget.transform,
                                    sourceAspectRatio: widget.sourceAspectRatio,
                                    builder: (fit, alignment) => Image.file(
                                      File(widget.originalPath),
                                      fit: fit,
                                      alignment: alignment,
                                      errorBuilder: (_, _, _) => _previewError(
                                        context,
                                        'Original preview unavailable',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment((_split * 2) - 1, 0),
                            child: Container(
                              width: 2,
                              color: CupertinoColors.white.withValues(
                                alpha: 0.85,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            top: 10,
                            child: _pill(context, 'Original'),
                          ),
                          Positioned(
                            right: 10,
                            top: 10,
                            child: _pill(context, 'Restored'),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        CupertinoSlider(
          value: _split,
          min: 0,
          max: 1,
          onChanged: (v) => setState(() => _split = v),
        ),
      ],
    );
  }

  bool _isRaw(String path) => MediaClassifier.rawPhotoExtensions.contains(
    p.extension(path).replaceFirst('.', '').toLowerCase(),
  );

  Widget _staticResult(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: ColoredBox(
        color: CupertinoColors.black,
        child: Image.file(
          File(widget.restoredPath),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Center(
            child: Text(
              'Restored file saved to ${p.basename(widget.restoredPath)}',
            ),
          ),
        ),
      ),
    ),
  );

  Widget _previewError(BuildContext context, String label) => Center(
    child: Text(
      label,
      style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.secondaryLabel,
          context,
        ),
      ),
    ),
  );
  Widget _pill(BuildContext context, String label) => DecoratedBox(
    decoration: BoxDecoration(
      color: CupertinoColors.black.withValues(alpha: 0.48),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        label,
        style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
          color: CupertinoColors.white,
          fontSize: 12,
        ),
      ),
    ),
  );
}
