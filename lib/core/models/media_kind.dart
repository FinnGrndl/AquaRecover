enum MediaKind { photo, rawPhoto, video, rawVideo }

extension MediaKindLabels on MediaKind {
  String get label {
    switch (this) {
      case MediaKind.photo:
        return 'Photo';
      case MediaKind.rawPhoto:
        return 'RAW photo';
      case MediaKind.video:
        return 'Video';
      case MediaKind.rawVideo:
        return 'RAW video';
    }
  }

  bool get isImage => this == MediaKind.photo || this == MediaKind.rawPhoto;
  bool get isVideo => this == MediaKind.video || this == MediaKind.rawVideo;
  bool get isRaw => this == MediaKind.rawPhoto || this == MediaKind.rawVideo;
}
