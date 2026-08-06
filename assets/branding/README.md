# Branding assets

`aquarecover_app_icon.png` is the canonical 1024 x 1024 app icon. It has no
alpha channel and is the only image that should be edited when the launcher icon
changes.

Generate the Android, iOS, macOS, and Windows icon sets with:

```bash
dart run flutter_launcher_icons -f flutter_launcher_icons.yaml
```

The generated files under the platform runners are committed so builds do not
depend on running the generator. Do not edit those derived PNG files by hand.
The canonical icon and its generated variants are distributed under the root
MIT License.
