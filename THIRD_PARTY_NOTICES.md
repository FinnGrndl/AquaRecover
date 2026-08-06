# Third-party notices

AquaRecover uses Flutter and packages distributed through pub.dev. Their
license texts are registered by Flutter and can be opened from **About >
Licenses** inside the app. The resolved versions in `pubspec.lock` are the
authoritative dependency list for a build.

Direct dependencies in version 1.0.0:

| Component | Resolved version | License |
| --- | ---: | --- |
| Flutter SDK | 3.44.1 | BSD-3-Clause |
| cupertino_icons | 1.0.9 | MIT |
| file_picker | 11.0.3 | MIT |
| image_picker | 1.2.3 | BSD-3-Clause; bundled Android code also includes Apache-2.0 material |
| image | 4.9.1 | MIT; derived codecs include Apache-2.0 and BSD-3-Clause material |
| path | 1.9.1 | BSD-3-Clause |
| path_provider | 2.1.6 | BSD-3-Clause |
| photo_manager | 3.11.0 | Apache-2.0 |
| video_player | 2.13.0 | BSD-3-Clause |

Source distributions retain the full package notices in each dependency. Binary
distributions must keep the in-app license registry available.

Build tooling includes `flutter_launcher_icons` 0.14.4 under the MIT License.
It generates platform icon sizes and is not linked into the application binary.
