enum ImageOutputFormat { jpeg, png }

extension ImageOutputFormatX on ImageOutputFormat {
  String get label => this == ImageOutputFormat.jpeg ? 'JPEG' : 'PNG';
  String get extension => this == ImageOutputFormat.jpeg ? 'jpg' : 'png';
}

enum VideoOutputFormat { mp4, mov }

extension VideoOutputFormatX on VideoOutputFormat {
  String get label => switch (this) {
    VideoOutputFormat.mp4 => 'MP4',
    VideoOutputFormat.mov => 'MOV',
  };

  String get extension => name;
}

/// How a before/after comparison export arranges the original and the
/// restored photo.
enum BeforeAfterLayout {
  /// Two full panes. Landscape photos are stacked and portrait photos sit
  /// next to each other, so the result stays close to square for feeds.
  sideBySide,

  /// One frame: the original on the left half, the restored photo on the
  /// right, divided at 50 %.
  split,
}

extension BeforeAfterLayoutX on BeforeAfterLayout {
  String get label => switch (this) {
    BeforeAfterLayout.sideBySide => 'Side by side',
    BeforeAfterLayout.split => 'Split',
  };
}

enum ExportPreset { social, archive, proEdit }

extension ExportPresetX on ExportPreset {
  String get label => switch (this) {
    ExportPreset.social => 'Social',
    ExportPreset.archive => 'Archive',
    ExportPreset.proEdit => 'Pro edit',
  };

  int get jpegQuality => switch (this) {
    ExportPreset.social => 88,
    ExportPreset.archive => 96,
    ExportPreset.proEdit => 100,
  };

  ImageOutputFormat get imageFormat => switch (this) {
    ExportPreset.social => ImageOutputFormat.jpeg,
    ExportPreset.archive => ImageOutputFormat.jpeg,
    ExportPreset.proEdit => ImageOutputFormat.png,
  };

  VideoOutputFormat get videoFormat => switch (this) {
    ExportPreset.social => VideoOutputFormat.mp4,
    ExportPreset.archive => VideoOutputFormat.mp4,
    ExportPreset.proEdit => VideoOutputFormat.mov,
  };

  ExportOptions get options => ExportOptions(
    imageFormat: imageFormat,
    videoFormat: videoFormat,
    stripMetadata: this != ExportPreset.archive,
    keepLocalCopy: true,
    saveToPhotoLibrary: false,
    saveToFiles: false,
    keepAudio: true,
  );
}

class ExportOptions {
  const ExportOptions({
    this.imageFormat = ImageOutputFormat.jpeg,
    this.videoFormat = VideoOutputFormat.mp4,
    this.stripMetadata = true,
    this.keepLocalCopy = true,
    this.saveToPhotoLibrary = false,
    this.saveToFiles = false,
    this.keepAudio = true,
    this.beforeAfter = false,
    this.beforeAfterLayout = BeforeAfterLayout.sideBySide,
    this.beforeAfterLabels = true,
  });

  final ImageOutputFormat imageFormat;
  final VideoOutputFormat videoFormat;
  final bool stripMetadata;
  final bool keepLocalCopy;
  final bool saveToPhotoLibrary;
  final bool saveToFiles;
  final bool keepAudio;

  /// Photo exports become one comparison image of the original and the
  /// restored photo. Videos ignore it.
  final bool beforeAfter;
  final BeforeAfterLayout beforeAfterLayout;

  /// Draws small "Before" and "After" labels on the comparison image.
  final bool beforeAfterLabels;

  bool get outputPng => imageFormat == ImageOutputFormat.png;

  ExportOptions copyWith({
    ImageOutputFormat? imageFormat,
    VideoOutputFormat? videoFormat,
    bool? stripMetadata,
    bool? keepLocalCopy,
    bool? saveToPhotoLibrary,
    bool? saveToFiles,
    bool? keepAudio,
    bool? beforeAfter,
    BeforeAfterLayout? beforeAfterLayout,
    bool? beforeAfterLabels,
  }) {
    return ExportOptions(
      imageFormat: imageFormat ?? this.imageFormat,
      videoFormat: videoFormat ?? this.videoFormat,
      stripMetadata: stripMetadata ?? this.stripMetadata,
      keepLocalCopy: keepLocalCopy ?? this.keepLocalCopy,
      saveToPhotoLibrary: saveToPhotoLibrary ?? this.saveToPhotoLibrary,
      saveToFiles: saveToFiles ?? this.saveToFiles,
      keepAudio: keepAudio ?? this.keepAudio,
      beforeAfter: beforeAfter ?? this.beforeAfter,
      beforeAfterLayout: beforeAfterLayout ?? this.beforeAfterLayout,
      beforeAfterLabels: beforeAfterLabels ?? this.beforeAfterLabels,
    );
  }

  ExportOptions withKeepLocalCopy(bool value) => copyWith(
    keepLocalCopy: value,
    saveToPhotoLibrary: value || saveToPhotoLibrary || saveToFiles
        ? saveToPhotoLibrary
        : true,
  );

  ExportOptions withPhotoLibrary(bool value) => copyWith(
    saveToPhotoLibrary: value,
    keepLocalCopy: value || keepLocalCopy || saveToFiles ? keepLocalCopy : true,
  );

  ExportOptions withFiles(bool value) => copyWith(
    saveToFiles: value,
    keepLocalCopy: value || keepLocalCopy || saveToPhotoLibrary
        ? keepLocalCopy
        : true,
  );

  factory ExportOptions.fromJson(Map<String, Object?> map) {
    const defaults = ExportOptions();
    bool flag(String key, bool fallback) => map[key] as bool? ?? fallback;
    return ExportOptions(
      imageFormat: ImageOutputFormat.values.firstWhere(
        (value) => value.name == map['imageFormat'],
        orElse: () => defaults.imageFormat,
      ),
      videoFormat: VideoOutputFormat.values.firstWhere(
        (value) => value.name == map['videoFormat'],
        orElse: () => defaults.videoFormat,
      ),
      stripMetadata: flag('stripMetadata', defaults.stripMetadata),
      keepLocalCopy: flag('keepLocalCopy', defaults.keepLocalCopy),
      saveToPhotoLibrary: flag(
        'saveToPhotoLibrary',
        defaults.saveToPhotoLibrary,
      ),
      saveToFiles: flag('saveToFiles', defaults.saveToFiles),
      keepAudio: flag('keepAudio', defaults.keepAudio),
      beforeAfter: flag('beforeAfter', defaults.beforeAfter),
      beforeAfterLayout: BeforeAfterLayout.values.firstWhere(
        (value) => value.name == map['beforeAfterLayout'],
        orElse: () => defaults.beforeAfterLayout,
      ),
      beforeAfterLabels: flag('beforeAfterLabels', defaults.beforeAfterLabels),
    );
  }

  Map<String, Object> toJson() => {
    'imageFormat': imageFormat.name,
    'videoFormat': videoFormat.name,
    'stripMetadata': stripMetadata,
    'keepLocalCopy': keepLocalCopy,
    'saveToPhotoLibrary': saveToPhotoLibrary,
    'saveToFiles': saveToFiles,
    'keepAudio': keepAudio,
    'beforeAfter': beforeAfter,
    'beforeAfterLayout': beforeAfterLayout.name,
    'beforeAfterLabels': beforeAfterLabels,
  };
}
