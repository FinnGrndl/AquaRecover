class RawVideoDescriptor {
  const RawVideoDescriptor({
    required this.width,
    required this.height,
    required this.frameRate,
    required this.pixelFormat,
  });

  final int width;
  final int height;
  final double frameRate;
  final String pixelFormat;

  static const minDimension = 16;
  static const maxDimension = 16384;
  static const maxPixels = 100000000;
  static const minFrameRate = 1.0;
  static const maxFrameRate = 240.0;

  static const commonPixelFormats = <String>[
    'yuv420p',
    'yuv422p',
    'yuv444p',
    'nv12',
    'rgb24',
    'rgba',
    'gray16le',
  ];

  static const default4k = RawVideoDescriptor(
    width: 3840,
    height: 2160,
    frameRate: 30,
    pixelFormat: 'yuv420p',
  );

  RawVideoDescriptor copyWith({
    int? width,
    int? height,
    double? frameRate,
    String? pixelFormat,
  }) {
    return RawVideoDescriptor(
      width: width ?? this.width,
      height: height ?? this.height,
      frameRate: frameRate ?? this.frameRate,
      pixelFormat: pixelFormat ?? this.pixelFormat,
    );
  }

  void validateForProcessing() {
    if (!commonPixelFormats.contains(pixelFormat)) {
      throw FormatException('Unsupported raw pixel format: $pixelFormat');
    }
    if (width < minDimension || height < minDimension) {
      throw const FormatException('RAW video dimensions are too small.');
    }
    if (width > maxDimension || height > maxDimension) {
      throw FormatException(
        'RAW video dimensions must be at most ${maxDimension}x$maxDimension.',
      );
    }
    if (width * height > maxPixels) {
      throw FormatException(
        'RAW video frames are too large. Maximum is $maxPixels pixels per frame.',
      );
    }
    if (!frameRate.isFinite ||
        frameRate < minFrameRate ||
        frameRate > maxFrameRate) {
      throw FormatException(
        'Frame rate must be between $minFrameRate and $maxFrameRate fps.',
      );
    }
  }

  List<String> toFfmpegInputArgs() {
    validateForProcessing();
    return [
      '-f',
      'rawvideo',
      '-pixel_format',
      pixelFormat,
      '-video_size',
      '${width}x$height',
      '-framerate',
      frameRate.toString(),
    ];
  }

  Map<String, Object> toJson() => {
    'width': width,
    'height': height,
    'frameRate': frameRate,
    'pixelFormat': pixelFormat,
  };
}
