# SmartCapture

![Platform](https://img.shields.io/badge/platform-macOS%2012%2B-lightgrey)
![License](https://img.shields.io/badge/license-MIT-blue)

Languages: [한국어](README.md) · English

A menu bar screenshot utility for macOS. Capture the screen with a hotkey, and each capture is
indexed on-device with text recognition (OCR) so you can find it later by its content.

It aims to replace the built-in screenshot tool while solving a common problem: the more screenshots
you take, the harder they are to find. Capture, text recognition, and search all run on-device, and
nothing is sent to external servers.

## Features

- Lives in the menu bar with no Dock icon
- Global hotkeys for full screen, region, and window capture
- Copies to the clipboard and shows a bottom-right thumbnail preview on capture
- Search by in-image text (OCR) and classification tags
- Moves captures older than a retention period to the Trash automatically
- Optional image context captions via a local LLM

## Requirements

- macOS 12 or later (Apple Silicon recommended)
- Screen Recording permission

## Installation

Build from source.

```bash
git clone https://github.com/sudo-Terry/SmartCapture.git
cd SmartCapture
./build_app.sh
open SmartCapture.app
```

The first capture attempt requests Screen Recording permission. Allow SmartCapture under
`System Settings > Privacy & Security > Screen Recording`, then relaunch the app.

> Run the built `.app`. A binary launched with `swift run` will not get the permission attached
> correctly.

## Usage

| Shortcut | Action |
| --- | --- |
| `⌃⌥⌘3` | Capture full screen |
| `⌃⌥⌘4` | Capture a selected region |
| `⌃⌥⌘5` | Capture a window |
| `⌃⌥⌘F` | Open search |

Captures are saved to `~/Pictures/ScreenShots` by default and copied to the clipboard.

### Search

Open search with `⌃⌥⌘F` and find captures by their in-image text or tags. Double-click a result for
a Quick Look preview, or right-click to reveal it in Finder or copy its path. The index is built in
the background right after each capture, so it never blocks capturing.

## Image context (optional)

OCR only reads text on screen. To also search low-text screens by meaning, you can use a local
vision-language model (VLM). This requires [Ollama](https://ollama.com) and a vision model.

```bash
./setup_vlm.sh            # pull the model and enable it (default: llava:7b)
./setup_vlm.sh moondream  # a lighter model
```

Toggle it from the **Image context** item in the menu bar. When disabled (the default), search uses
OCR alone. Captions are used for search only and never move or delete capture files.

## Configuration

The config file lives at `~/Library/Application Support/SmartCapture/config.json` and is reachable
from **Open config file** in the menu bar. You can change the save folder, retention period, VLM
model, and more.

## How it works

- Capturing uses macOS `screencapture`.
- Text recognition, classification, and feature extraction use the Apple Vision framework.
- The index is stored in SQLite.
- Extracted information is also written to each file's extended attributes (xattr) so it travels with
  the file.

## Troubleshooting

<details>
<summary>The hotkey fires but nothing is saved</summary>

This is a Screen Recording permission issue, not a hotkey conflict (the app uses `⌃⌥⌘`, while the
built-in screenshot uses `⌘⇧`). Grant permission and relaunch. Because of ad-hoc signing, rebuilding
the app can reset the permission; signing with a self-signed certificate keeps it
(`SIGN_IDENTITY="Name" ./build_app.sh`).
</details>

<details>
<summary>The permission warning looks alarming</summary>

It is the standard macOS warning shown to every app that captures the screen. SmartCapture only takes
still images and does no audio or continuous recording.
</details>

<details>
<summary>Search returns nothing</summary>

The index may be empty. Grant permission, take a capture, and search again.
</details>

## License

MIT License. See [LICENSE](LICENSE).
