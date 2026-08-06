import 'image_transform_settings.dart';
import 'lut_profile.dart';
import 'restoration_settings.dart';

/// Nondestructive editing values that belong to one item in the media queue.
class MediaEditState {
  const MediaEditState({
    this.settings = const RestorationSettings(),
    this.transform = const ImageTransformSettings(),
    this.lutProfile = LutProfile.none,
  });

  final RestorationSettings settings;
  final ImageTransformSettings transform;
  final LutProfile lutProfile;

  MediaEditState copyWith({
    RestorationSettings? settings,
    ImageTransformSettings? transform,
    LutProfile? lutProfile,
  }) {
    return MediaEditState(
      settings: settings ?? this.settings,
      transform: transform ?? this.transform,
      lutProfile: lutProfile ?? this.lutProfile,
    );
  }
}
