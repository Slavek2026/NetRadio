# NetRadio for macOS

NetRadio is a native internet radio player for macOS 13 and later.

**Version:** 1.0  
**Copyright:** © 2026 Brumbambule (X/Twitter: @Brumbambule)

## Download

[Download NetRadio for macOS 1.0](https://github.com/Slavek2026/NetRadio/raw/refs/heads/main/NetRadio-macOS-v1.0.zip) and move `NetRadio.app` from the ZIP to your Applications folder. Requires macOS 13 or later.

## Features

- Search radio stations by name through Radio Browser.
- Save up to 10 stations as presets, or add a direct HTTP/HTTPS stream URL.
- Play, pause, stop, and adjust volume.
- Show station and track metadata when the stream provides it.
- Compact player window, always-on-top mode, and a menu bar mini-player with playback controls and a restore action.
- Czech and English interface languages.
- Show country, codec, and bitrate when station data is available.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools or Xcode
- Internet connection for station search and playback

## Build and run

```sh
swift build -c release
swift run
```

Open the project directory in Xcode to build or run it there.

## Station search

Search uses public Radio Browser servers. Station availability and track metadata depend on the station's stream. You can also add a direct HTTP or HTTPS stream URL manually.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).

