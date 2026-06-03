# Optional LibRaw bridge

The Flutter app already includes native RAW still decoding through Apple Core Image on iOS/macOS and Android ImageDecoder on Android 9+. Use this optional C ABI when you need broader DSLR/mirrorless RAW support such as CR2, CR3, NEF, ARW, RAF, and RW2 across all platforms.

Build requirements:

- LibRaw development headers and library.
- A platform-specific build system that bundles the resulting shared library for Android, iOS, or macOS.
- Dart FFI bindings that call `aqua_decode_raw_to_rgba8` and then pass the RGBA buffer through `UnderwaterProcessor.restoreImage`.

This is intentionally isolated because LibRaw distribution, camera profile support, and app-store binary packaging differ by platform.
