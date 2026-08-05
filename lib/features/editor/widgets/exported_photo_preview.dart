import 'dart:io';

import 'package:flutter/cupertino.dart';

class ExportedPhotoPreview extends StatelessWidget {
  const ExportedPhotoPreview({
    super.key,
    required this.path,
    required this.aspectRatio,
  });

  final String path;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      key: const Key('exported_photo_preview'),
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ColoredBox(
          color: CupertinoColors.black,
          child: Image.file(
            File(path),
            key: const Key('exported_photo_image'),
            fit: BoxFit.contain,
            cacheWidth: 1600,
            errorBuilder: (_, _, _) => const Center(
              child: Text(
                'Exported photo preview unavailable.',
                style: TextStyle(color: CupertinoColors.systemGrey),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
