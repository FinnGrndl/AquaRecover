# Using AquaRecover with Claude (MCP)

AquaRecover ships a [Model Context Protocol](https://modelcontextprotocol.io)
server. Claude Desktop, Claude Code, or any other MCP client can use it to
analyse, preview, and restore underwater photos and videos on your computer
through conversation, for example:

> "Look at the photos in ~/Dives/2026-10-Bonaire, fix the colours, keep it
> natural, and export them to ~/Dives/2026-10-Bonaire/edited."

The server runs the same restoration code as the app. Files are read and
written locally; nothing is uploaded by AquaRecover. Preview images that a tool
returns are sent to Claude by your MCP client as part of the conversation.

## Tools

| Tool | What it does |
| --- | --- |
| `analyze_media` | Measures red loss, water colour, brightness and clipping of a photo or video frame and suggests a preset with reasons |
| `describe_settings` | Lists presets, built-in LUTs and every adjustable parameter with its range |
| `preview_restoration` | Returns a downscaled preview image (`after`, `before`, or `side_by_side`) for a look, without writing files |
| `restore_image` | Writes a full-resolution JPEG or PNG and an `.aquarecover.json` sidecar |
| `batch_restore` | Restores a list of photos or a whole folder, optionally with a per-photo suggested preset |
| `restore_video` | Exports an H.264 MP4/MOV with ffmpeg, with optional trim and audio |
| `read_sidecar` | Reads the settings of an earlier export so the same look can be reapplied |

A look is a `preset` (`auto`, `natural`, `vivid`, `deep`, `macro`, `shallow`,
`greenWater`, `redFilter`, `artificialLight`, `none`), a `preset_strength`, and
optional absolute `adjustments` such as `{"exposure": 0.15, "redRecovery":
1.6}`. A built-in `lut` or a `cube_path` and a crop/rotation `transform` can be
added. Existing files are never overwritten unless `overwrite` is true.

Two prompts are included: `restore_dive_folder` and `match_look`.

## Formats

JPEG, PNG, WebP and TIFF work everywhere. HEIC/HEIF and camera RAW files are
converted with the built-in `sips` tool on macOS; on other systems convert
them first or use the app. Video tools need `ffmpeg` and `ffprobe` on `PATH`
(`brew install ffmpeg`, `winget install ffmpeg`, or your package manager).

## Install

The server is a Dart command-line program in this repository. With Flutter
installed:

```bash
git clone https://github.com/FinnGrndl/AquaRecover.git
cd AquaRecover
flutter pub get
dart build cli -t bin/aquarecover_mcp.dart -o build/mcp
```

The executable is `build/mcp/bundle/bin/aquarecover_mcp`
(`aquarecover_mcp.exe` on Windows). `dart run bin/aquarecover_mcp.dart` also
works but compiles on every start.

### Claude Code

```bash
claude mcp add aquarecover -- /absolute/path/to/build/mcp/bundle/bin/aquarecover_mcp --allow ~/Dives
```

### Claude Desktop

Add the server to `claude_desktop_config.json` (Settings → Developer → Edit
Config) and restart Claude Desktop:

```json
{
  "mcpServers": {
    "aquarecover": {
      "command": "/absolute/path/to/build/mcp/bundle/bin/aquarecover_mcp",
      "args": ["--allow", "/Users/you/Dives"]
    }
  }
}
```

## Limiting access

`--allow <folder>` (repeatable) restricts every read and write to those
folders, including symbolic-link targets. `AQUARECOVER_MCP_ALLOW` accepts the
same list separated by `:` (`;` on Windows). Without either, the server can
access any path your user account can, like other command-line tools you run.
Using `--allow` is recommended.

## Development

`lib/mcp/mcp_server.dart` implements the protocol (JSON-RPC over
newline-delimited stdio, protocol versions 2025-06-18, 2025-03-26 and
2024-11-05, tools, prompts, and progress notifications).
`lib/mcp/aquarecover_tools.dart` defines the tools on top of
`StillRenderPipeline` and `SceneAnalyzer`, which the app uses as well.
`test/mcp_server_test.dart` drives the server in-process.
