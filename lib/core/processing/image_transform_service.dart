import 'package:image/image.dart' as img;

import '../models/image_transform_settings.dart';

class ImageTransformService {
  const ImageTransformService();

  img.Image apply(img.Image source, ImageTransformSettings settings) {
    if (settings.isIdentity) return source;
    final sourceAspectRatio = source.width / source.height;
    var output = img.Image.from(source);
    final turns = settings.normalizedQuarterTurns;
    if (turns != 0) {
      output = img.copyRotate(output, angle: turns * 90);
    }
    if (settings.flipHorizontal) {
      output = img.flipHorizontal(output);
    }
    if (settings.flipVertical) {
      output = img.flipVertical(output);
    }

    final rect = settings.normalizedCropRect(sourceAspectRatio);
    final x = (rect.left * output.width)
        .floor()
        .clamp(0, output.width - 1)
        .toInt();
    final y = (rect.top * output.height)
        .floor()
        .clamp(0, output.height - 1)
        .toInt();
    final width = (rect.width * output.width)
        .round()
        .clamp(1, output.width - x)
        .toInt();
    final height = (rect.height * output.height)
        .round()
        .clamp(1, output.height - y)
        .toInt();
    if (x == 0 && y == 0 && width == output.width && height == output.height) {
      return output;
    }
    return img.copyCrop(output, x: x, y: y, width: width, height: height);
  }
}
