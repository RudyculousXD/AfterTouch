# LyricGlass

LyricGlass is an independent macOS music companion for the MacBook notch and Lock Screen. It brings playback controls, album artwork, and timed lyrics into a compact native interface.

## Features

- Notch player with current artwork, track details, playback controls, and animated audio bars.
- Lock Screen card with album art, a softly blurred artwork background, and timed lyrics. The active lyric line fills progressively while nearby lines remain visible.
- Spotify and Apple Music playback support through separate media providers.
- Optional lyrics lookup through LRCLIB. Lookup sends the current track title, artist, album, and duration; lyric availability depends on the track. The active-line fill estimates timing between synced lines and does not represent word-level timestamps.
- File tray in the expanded player for up to 12 files or folders, with open, drag-out, share, and remove actions.
- Settings for Lock Screen placement, artwork treatment, lyrics, and player surface appearance.

LyricGlass displays the macOS account name using `NSFullUserName()`. Native authentication controls remain owned by macOS; the Lock Screen panel cannot become key or main and does not accept password input.

## Requirements

- macOS 14 or later
- Xcode
- A MacBook with a camera notch for the notch player
- Spotify and/or Apple Music for media controls

## Build

Open `LyricGlass.xcodeproj` in Xcode and build the `Nocta` scheme. The app's displayed name is LyricGlass. The project is also configured with XcodeGen in `project.yml`.

## Project and third-party code

LyricGlass is an independent project built from the Nocta codebase. It is **not built from the Boring Notch application base**. One source file, `Sources/System/BoringVolumeManager.swift`, adapts Boring Notch's Core Audio system-volume management code. Its upstream UI coordinator was removed. The required attribution and license details are in `NOTICE`; the project is distributed under GPL-3.0-or-later.

## License

GPL-3.0-or-later. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE) for license and third-party attribution details.
