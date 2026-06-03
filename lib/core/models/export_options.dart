enum ImageOutputFormat { jpeg, png }

extension ImageOutputFormatX on ImageOutputFormat {
  String get label => this == ImageOutputFormat.jpeg ? 'JPEG' : 'PNG';
  String get extension => this == ImageOutputFormat.jpeg ? 'jpg' : 'png';
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

  ExportOptions get options => ExportOptions(
        imageFormat: imageFormat,
        stripMetadata: this != ExportPreset.archive,
        saveToPhotoLibrary: false,
        keepAudio: true,
      );
}

class ExportOptions {
  const ExportOptions({
    this.imageFormat = ImageOutputFormat.jpeg,
    this.stripMetadata = true,
    this.saveToPhotoLibrary = false,
    this.keepAudio = true,
  });

  final ImageOutputFormat imageFormat;
  final bool stripMetadata;
  final bool saveToPhotoLibrary;
  final bool keepAudio;

  bool get outputPng => imageFormat == ImageOutputFormat.png;

  ExportOptions copyWith({ImageOutputFormat? imageFormat, bool? stripMetadata, bool? saveToPhotoLibrary, bool? keepAudio}) {
    return ExportOptions(
      imageFormat: imageFormat ?? this.imageFormat,
      stripMetadata: stripMetadata ?? this.stripMetadata,
      saveToPhotoLibrary: saveToPhotoLibrary ?? this.saveToPhotoLibrary,
      keepAudio: keepAudio ?? this.keepAudio,
    );
  }

  Map<String, Object> toJson() => {
        'imageFormat': imageFormat.name,
        'stripMetadata': stripMetadata,
        'saveToPhotoLibrary': saveToPhotoLibrary,
        'keepAudio': keepAudio,
      };
}
