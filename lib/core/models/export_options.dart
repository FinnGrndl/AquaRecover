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
  });

  final ImageOutputFormat imageFormat;
  final VideoOutputFormat videoFormat;
  final bool stripMetadata;
  final bool keepLocalCopy;
  final bool saveToPhotoLibrary;
  final bool saveToFiles;
  final bool keepAudio;

  bool get outputPng => imageFormat == ImageOutputFormat.png;

  ExportOptions copyWith({
    ImageOutputFormat? imageFormat,
    VideoOutputFormat? videoFormat,
    bool? stripMetadata,
    bool? keepLocalCopy,
    bool? saveToPhotoLibrary,
    bool? saveToFiles,
    bool? keepAudio,
  }) {
    return ExportOptions(
      imageFormat: imageFormat ?? this.imageFormat,
      videoFormat: videoFormat ?? this.videoFormat,
      stripMetadata: stripMetadata ?? this.stripMetadata,
      keepLocalCopy: keepLocalCopy ?? this.keepLocalCopy,
      saveToPhotoLibrary: saveToPhotoLibrary ?? this.saveToPhotoLibrary,
      saveToFiles: saveToFiles ?? this.saveToFiles,
      keepAudio: keepAudio ?? this.keepAudio,
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

  Map<String, Object> toJson() => {
    'imageFormat': imageFormat.name,
    'videoFormat': videoFormat.name,
    'stripMetadata': stripMetadata,
    'keepLocalCopy': keepLocalCopy,
    'saveToPhotoLibrary': saveToPhotoLibrary,
    'saveToFiles': saveToFiles,
    'keepAudio': keepAudio,
  };
}
