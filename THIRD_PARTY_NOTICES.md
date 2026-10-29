# Third-party notices

AquaRecover uses Flutter and packages distributed through pub.dev. Their
license texts are registered by Flutter and can be opened from **About >
Licenses** inside the app. The resolved versions in `pubspec.lock` are the
authoritative dependency list for a build.

Direct dependencies in version 1.6.0:

| Component | Resolved version | License |
| --- | ---: | --- |
| Flutter SDK | 3.44.1 | BSD-3-Clause; the engine's third-party components are in the same in-app list |
| cupertino_icons | 1.0.9 | MIT |
| file_picker | 13.1.0 | MIT |
| flutter_map | 8.3.2 | BSD-3-Clause |
| image | 4.9.2 | MIT; derived codecs include Apache-2.0 and BSD-3-Clause material |
| image_picker | 1.2.3 | BSD-3-Clause; bundled Android code also includes Apache-2.0 material |
| image_picker_android | 0.8.13+19 | BSD-3-Clause; includes Apache-2.0 material |
| image_picker_platform_interface | 2.11.1 | BSD-3-Clause |
| latlong2 | 0.10.1 | Apache-2.0 |
| path | 1.9.1 | BSD-3-Clause |
| path_provider | 2.1.6 | BSD-3-Clause |
| photo_manager | 3.12.0 | Apache-2.0 |
| video_player | 2.14.0 | BSD-3-Clause |
| xml | 7.0.1 | MIT |

Transitive pub packages are licensed under MIT, BSD-3-Clause, or Apache-2.0,
with one exception: `dbus` (MPL-2.0) is used only by `file_picker_linux`, and
AquaRecover does not ship a Linux build. No dependency is licensed under the
GPL, LGPL, or AGPL.

Source distributions retain the full package notices in each dependency. Binary
distributions must keep the in-app license registry available.

## Components outside pub.dev

| Component | Where | License | Notes |
| --- | --- | --- | --- |
| AndroidX Media3 1.8.0 (`media3-transformer`, `media3-effect`, `media3-common`) | Android app | Apache-2.0 | Linked by the native video export. Listed in the in-app licenses on Android, with the text from `assets/licenses/APACHE-2.0.txt`. |
| OpenStreetMap map data and tiles | Dive logbook map | ODbL 1.0 | Loaded at run time from `tile.openstreetmap.org`, not bundled. The map shows "© OpenStreetMap contributors"; tapping it opens the license notice, which is also in the in-app licenses. |
| FFmpeg | Windows video export | LGPL or GPL, depending on the user's build | Not bundled. The Windows app runs an `ffmpeg` executable the user installed. Other platforms do not use FFmpeg. |
| LibRaw | `native/libraw_bridge` | LGPL-2.1 or CDDL-1.0 | Optional bridge that no release build compiles or ships. Shipping it requires adding its notice and meeting the LGPL relinking terms, or choosing CDDL. |

The app icon and its generated platform sizes are original AquaRecover artwork
under the root MIT License (see `assets/branding/README.md`). Apart from the
Cupertino icon font from `cupertino_icons`, the app bundles no third-party
fonts, images, LUTs, shaders, or sample media.

Build tooling includes `flutter_launcher_icons` 0.14.4 under the MIT License.
It generates platform icon sizes and is not linked into the application binary.
