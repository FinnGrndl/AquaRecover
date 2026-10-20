# Changelog

Changes are generated from Conventional Commit messages. AquaRecover follows
semantic versioning; the number after `+` is the platform build number.

## 1.5.0 - 2026-10-20

### Added

- Local dive logbook with map, UDDF import and export

### Fixed

- Full-size Photos picker and always-visible extra tracks
- Audit fixes for small, large-text, landscape and desktop layouts
## 1.4.0 - 2026-10-19

### Added

- Export video natively with a shared AVFoundation pipeline
- Export video on Android and Windows with a baked 3D LUT
- Add a timeline engine that renders photos and clips into one movie
- Add a Resolve-style mobile movie editor
- Match the movie editor to the app's design
- Tap-to-set white balance with temperature and tint
- Give the white balance picker the editor's glass chrome
- Render plan v2 with effects, overlays, titles and audio tracks
- Add an MCP server so Claude can restore dive media
- Live preview of the layered movie
- Render the v2 movie plan with Media3
- Render the v2 movie plan with ffmpeg on Windows and Linux
- Suggest a preset for each photo
- CapCut-style movie editor with lanes, toolbar and inspector

### Fixed

- Follow Apple's HIG across the editor, library and movies
- Import through permission-free system pickers
- Read .cube samples red-fastest and apply LUTs on packed buffers
- Pick movie media with the file_picker 13 API
- Give the preset suggestion room and a clear applied state
- Follow Apple's HIG for the preset suggestion and glass chrome
- Enable Export from the renderer's own backend

### Performance

- Render stills on packed buffers and parallel bands
## 1.3.2 - 2026-09-16

### Documentation

- Rebuild project and development guides
- Explain regional restoration weights
- Merge pull request #26 from FinnGrndl/feat/processing-docs
## 1.3.1 - 2026-09-16

### Fixed

- Align interactive preview and exported frame
- Improve motion and selection accessibility
- Recover Photos library permission access
- Validate unchanged release versions
## 1.3.0 - 2026-09-06

### Added

- Adopt Apple-style toolbars and stabilize export (#19)
- Edit crop and export page (#21)

### Fixed

- Open photo imports in editor (#20)
## 1.2.0 - 2026-08-10

### Added

- Add freeform ratios and straightening
- Add selectable preview frames and playback
- Continue long exports on iOS 26
- Replace sliders with haptic precision wheel

### Changed

- Unify floating glass control surfaces
- Compact crop and adjustment controls

### Documentation

- Update media editing and export behavior

### Fixed

- Make iPad Photos selection resilient
- Show media-specific format controls
- Keep iOS exports active during app switches
- Honor photo orientation in crop previews
- Build Apple checks with Xcode 26

### Performance

- Resolve Photos assets concurrently
## 1.1.2 - 2026-08-07

### Documentation

- Correct release line initialization (#12)

### Fixed

- Declare export compliance exemption (#13)
## 1.1.1 - 2026-08-07

### Fixed

- Declare required privacy purposes
- Use persistent major release lines
## 1.1.0 - 2026-08-07

### Added

- Add gitignore, readme
- Add app v0.1.0
- Design changes, refactoring
- Delete cocoapods
- Auto adjustments and test images
- New colors
- Update processing
- Archtiectural overview
- Add crop browser and image transformation features
- Add export library functionality and UI components
- Enhance editor tools and preview functionality
- Code release version 1.0.0 with major updates and enhancements
- Streamline multi-platform publication

### Fixed

- Restore file picker build compatibility
- Authenticate private validation fetch
- Correct mobile signing configuration
- Let archive select signing identity
- Scope distribution settings to Runner
- Require current App Store SDK

