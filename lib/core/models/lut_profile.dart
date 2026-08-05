enum LutKind { none, coralWarm, blueWater, greenWater, customCube }

class LutProfile {
  const LutProfile({
    required this.kind,
    required this.name,
    this.path,
    this.intensity = 1.0,
  });

  final LutKind kind;
  final String name;
  final String? path;
  final double intensity;

  static const none = LutProfile(
    kind: LutKind.none,
    name: 'None',
    intensity: 0,
  );
  static const coralWarm = LutProfile(
    kind: LutKind.coralWarm,
    name: 'Coral Warm',
  );
  static const blueWater = LutProfile(
    kind: LutKind.blueWater,
    name: 'Blue Water',
  );
  static const greenWater = LutProfile(
    kind: LutKind.greenWater,
    name: 'Green Water',
  );
  static const builtIns = <LutProfile>[none, coralWarm, blueWater, greenWater];

  bool get isEnabled => kind != LutKind.none && intensity > 0.001;
  bool get isCustomCube => kind == LutKind.customCube && path != null;

  LutProfile copyWith({
    LutKind? kind,
    String? name,
    String? path,
    double? intensity,
  }) {
    return LutProfile(
      kind: kind ?? this.kind,
      name: name ?? this.name,
      path: path ?? this.path,
      intensity: intensity ?? this.intensity,
    );
  }

  static LutProfile customCube(
    String path, {
    String name = 'Custom .cube',
    double intensity = 1.0,
  }) {
    return LutProfile(
      kind: LutKind.customCube,
      name: name,
      path: path,
      intensity: intensity,
    );
  }

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'name': name,
    'path': path,
    'intensity': intensity,
  };
}
