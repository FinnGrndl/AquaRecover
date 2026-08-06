import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as p;

import '../../../core/models/media_job.dart';
import '../../../core/models/media_kind.dart';
import '../../../core/models/image_transform_settings.dart';
import '../../../core/models/lut_profile.dart';
import '../../../core/models/restoration_settings.dart';
import '../editor_tools.dart';
import 'restored_image_preview.dart';
import 'image_transform_preview.dart';
import 'video_frame_preview_tile.dart';

class EditorHoldPreview extends StatefulWidget {
  const EditorHoldPreview({
    super.key,
    required this.compareMode,
    required this.previewBuilder,
    this.heldIndicator,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
  });

  final EditorCompareMode compareMode;
  final Widget Function(EditorCompareMode mode) previewBuilder;
  final Widget? heldIndicator;
  final GestureScaleStartCallback? onScaleStart;
  final GestureScaleUpdateCallback? onScaleUpdate;
  final GestureScaleEndCallback? onScaleEnd;

  @override
  State<EditorHoldPreview> createState() => _EditorHoldPreviewState();
}

class _EditorHoldPreviewState extends State<EditorHoldPreview> {
  bool _holdingOriginal = false;

  @override
  void didUpdateWidget(EditorHoldPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.compareMode != EditorCompareMode.edited) {
      _holdingOriginal = false;
    }
  }

  void _setHoldingOriginal(bool value) {
    if (_holdingOriginal == value) return;
    setState(() => _holdingOriginal = value);
  }

  @override
  Widget build(BuildContext context) {
    final canHold = widget.compareMode == EditorCompareMode.edited;
    final effectiveMode = _holdingOriginal
        ? EditorCompareMode.original
        : widget.compareMode;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: canHold ? (_) => _setHoldingOriginal(true) : null,
      onLongPressEnd: canHold ? (_) => _setHoldingOriginal(false) : null,
      onLongPressCancel: canHold ? () => _setHoldingOriginal(false) : null,
      onScaleStart: widget.onScaleStart,
      onScaleUpdate: widget.onScaleUpdate,
      onScaleEnd: widget.onScaleEnd,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.previewBuilder(effectiveMode),
          if (_holdingOriginal && widget.heldIndicator != null)
            widget.heldIndicator!,
        ],
      ),
    );
  }
}

class EditorPreviewStage extends StatelessWidget {
  const EditorPreviewStage({
    super.key,
    required this.job,
    required this.settings,
    required this.compareMode,
    this.lutProfile = LutProfile.none,
    this.immersive = false,
    this.showHeader = true,
    this.borderRadius = 18,
    this.immersiveBottomInset = 154,
    this.immersiveTopInset = 54,
    this.transform = const ImageTransformSettings(),
    this.showCropGrid = false,
    this.previewFit = EditorPreviewFit.fit,
  });

  final MediaJob job;
  final RestorationSettings settings;
  final EditorCompareMode compareMode;
  final LutProfile lutProfile;
  final bool immersive;
  final bool showHeader;
  final double borderRadius;
  final double immersiveBottomInset;
  final double immersiveTopInset;
  final ImageTransformSettings transform;
  final bool showCropGrid;
  final EditorPreviewFit previewFit;

  @override
  Widget build(BuildContext context) {
    final title = job.displayName ?? p.basename(job.inputPath);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.black,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _preview(context),
            if (showHeader)
              Positioned(
                left: 12,
                top: 12,
                right: 12,
                child: _stageHeader(context, title),
              ),
          ],
        ),
      ),
    );
  }

  Widget _preview(BuildContext context) {
    if (job.kind == MediaKind.photo) {
      return _photoPreview(context);
    }
    if (job.kind == MediaKind.video) {
      return _videoPreview(context);
    }
    return _placeholder(context, job.kind);
  }

  Widget _photoPreview(BuildContext context) {
    final background = Image.file(
      File(job.inputPath),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _placeholder(context, job.kind),
    );
    final original = _transformedPhoto(
      builder: (fit, alignment) => Image.file(
        File(job.inputPath),
        fit: fit,
        alignment: alignment,
        errorBuilder: (_, _, _) => _placeholder(context, job.kind),
      ),
    );
    final edited = _transformedPhoto(
      builder: (fit, alignment) => RestoredImagePreview(
        path: job.inputPath,
        settings: settings,
        lutProfile: lutProfile,
        fit: fit,
        alignment: alignment,
      ),
    );
    return switch (compareMode) {
      EditorCompareMode.original => _photoFitPreview(
        background: background,
        foreground: original,
      ),
      EditorCompareMode.edited => _photoFitPreview(
        background: background,
        foreground: edited,
      ),
      EditorCompareMode.split => _photoSplitPreview(
        context,
        background: background,
        original: original,
        edited: edited,
      ),
    };
  }

  Widget _transformedPhoto({required TransformPreviewBuilder builder}) {
    final width = job.metadata?.width;
    final height = job.metadata?.height;
    final sourceAspect = width != null && height != null && height > 0
        ? width / height
        : 4 / 3;
    return ImageTransformPreview(
      settings: transform,
      sourceAspectRatio: sourceAspect,
      showGrid: showCropGrid && compareMode != EditorCompareMode.split,
      previewFit: previewFit,
      builder: builder,
    );
  }

  Widget _photoSplitPreview(
    BuildContext context, {
    required Widget background,
    required Widget original,
    required Widget edited,
  }) {
    final split = Row(
      children: [
        Expanded(child: _labeledHalf(context, 'Original', original)),
        Container(width: 1, color: CupertinoColors.white.withValues(alpha: .5)),
        Expanded(child: _labeledHalf(context, 'Edited', edited)),
      ],
    );
    if (!immersive) {
      return ColoredBox(color: CupertinoColors.black, child: split);
    }
    return _photoFitPreview(background: background, foreground: split);
  }

  Widget _videoPreview(BuildContext context) {
    final original = _fitPreview(
      VideoFramePreviewTile(path: job.inputPath, caption: 'Frame preview'),
    );
    final edited = _fitPreview(
      VideoFramePreviewTile(
        path: job.inputPath,
        settings: settings,
        caption: 'Frame preview',
      ),
    );
    return switch (compareMode) {
      EditorCompareMode.original => original,
      EditorCompareMode.edited => edited,
      EditorCompareMode.split => _splitPreview(
        context,
        original: original,
        edited: edited,
      ),
    };
  }

  Widget _splitPreview(
    BuildContext context, {
    required Widget original,
    required Widget edited,
  }) {
    final split = Row(
      children: [
        Expanded(child: _labeledHalf(context, 'Original', original)),
        Container(width: 1, color: CupertinoColors.white.withValues(alpha: .5)),
        Expanded(child: _labeledHalf(context, 'Edited', edited)),
      ],
    );
    if (!immersive) return split;
    return ColoredBox(
      color: CupertinoColors.black,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          10,
          immersiveTopInset,
          10,
          immersiveBottomInset,
        ),
        child: split,
      ),
    );
  }

  Widget _labeledHalf(BuildContext context, String label, Widget child) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(left: 10, bottom: 10, child: _chip(context, label)),
      ],
    );
  }

  Widget _fitPreview(Widget child) {
    return ColoredBox(
      color: CupertinoColors.black,
      child: Center(child: child),
    );
  }

  Widget _photoFitPreview({
    required Widget background,
    required Widget foreground,
  }) {
    if (!immersive) {
      return _fitPreview(foreground);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Transform.scale(scale: 1.08, child: background),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                CupertinoColors.black.withValues(alpha: .16),
                CupertinoColors.black.withValues(alpha: .05),
                CupertinoColors.black.withValues(alpha: .34),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            10,
            immersiveTopInset,
            10,
            immersiveBottomInset,
          ),
          child: foreground,
        ),
      ],
    );
  }

  Widget _placeholder(BuildContext context, MediaKind kind) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            kind.isVideo ? CupertinoIcons.film : CupertinoIcons.doc_richtext,
            color: CupertinoColors.white.withValues(alpha: .64),
            size: 52,
          ),
          const SizedBox(height: 8),
          Text(
            kind.isVideo
                ? 'Frame preview unavailable for this format'
                : 'Preview generated during export',
            textAlign: TextAlign.center,
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
              color: CupertinoColors.white.withValues(alpha: .72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stageHeader(BuildContext context, String title) {
    return Row(
      children: [
        Expanded(child: _scrimText(context, title, maxLines: 1)),
        const SizedBox(width: 8),
        _chip(
          context,
          job.kind == MediaKind.video
              ? '${compareMode.label} frame'
              : compareMode.label,
        ),
      ],
    );
  }

  Widget _scrimText(BuildContext context, String text, {int maxLines = 1}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.black.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
            color: CupertinoColors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String text) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.black.withValues(alpha: .54),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: CupertinoColors.white.withValues(alpha: .18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
            color: CupertinoColors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class EditorPreviewZoom extends StatefulWidget {
  const EditorPreviewZoom({
    super.key,
    required this.child,
    required this.resetKey,
    this.enabled = true,
  });

  final Widget child;
  final Object resetKey;
  final bool enabled;

  @override
  State<EditorPreviewZoom> createState() => _EditorPreviewZoomState();
}

class _EditorPreviewZoomState extends State<EditorPreviewZoom> {
  final TransformationController _controller = TransformationController();

  @override
  void didUpdateWidget(covariant EditorPreviewZoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey ||
        oldWidget.enabled != widget.enabled) {
      _reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reset() => _controller.value = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: _reset,
      child: InteractiveViewer(
        key: const Key('editor_preview_zoom'),
        transformationController: _controller,
        minScale: 1,
        maxScale: 5,
        panEnabled: true,
        scaleEnabled: true,
        clipBehavior: Clip.hardEdge,
        child: SizedBox.expand(child: widget.child),
      ),
    );
  }
}
