import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as p;

import '../../../core/models/media_job.dart';
import '../../../core/models/media_kind.dart';
import '../../../core/models/lut_profile.dart';
import '../../../core/models/restoration_settings.dart';
import '../editor_tools.dart';
import 'restored_image_preview.dart';
import 'video_frame_preview_tile.dart';

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
  });

  final MediaJob job;
  final RestorationSettings settings;
  final EditorCompareMode compareMode;
  final LutProfile lutProfile;
  final bool immersive;
  final bool showHeader;
  final double borderRadius;

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
    final original = _photoFitPreview(
      background: Image.file(
        File(job.inputPath),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(context, job.kind),
      ),
      foreground: Image.file(
        File(job.inputPath),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _placeholder(context, job.kind),
      ),
    );
    final edited = _photoFitPreview(
      background: Image.file(
        File(job.inputPath),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(context, job.kind),
      ),
      foreground: RestoredImagePreview(
        path: job.inputPath,
        settings: settings,
        lutProfile: lutProfile,
      ),
    );
    return switch (compareMode) {
      EditorCompareMode.original => original,
      EditorCompareMode.edited => edited,
      EditorCompareMode.split => _splitPreview(
        context,
        original: _fitPreview(
          Image.file(
            File(job.inputPath),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _placeholder(context, job.kind),
          ),
        ),
        edited: _fitPreview(
          RestoredImagePreview(
            path: job.inputPath,
            settings: settings,
            lutProfile: lutProfile,
          ),
        ),
      ),
    };
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
    return Row(
      children: [
        Expanded(child: _labeledHalf(context, 'Original', original)),
        Container(width: 1, color: CupertinoColors.white.withValues(alpha: .5)),
        Expanded(child: _labeledHalf(context, 'Edited', edited)),
      ],
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
          padding: const EdgeInsets.fromLTRB(10, 54, 10, 154),
          child: Center(child: foreground),
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
