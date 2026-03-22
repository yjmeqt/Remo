# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Web dashboard** (`remo dashboard`): Browser-based UI with multi-device discovery, device selector, video streaming, screenshot capture, capabilities panel, and interactive terminal
- **Video streaming**: H.264 screen capture via RPScreenRecorder + VideoToolbox encoder on iOS, fMP4 muxer + MSE playback on desktop
- **StreamFrame wire protocol**: Type 0x02 binary frame for real-time video/audio data with flags and timestamps
- **Multi-device support in dashboard**: Auto-discovery via USB (usbmuxd) and Bonjour (mDNS), connect/disconnect via REST API
- **`remo mirror` CLI command**: Live screen mirror with `--web` option for browser playback and `--save` for MP4 recording
- **Bonjour multi-address fallback**: Tries all resolved addresses for reliable simulator connections
- **`remo-objc` screen capture**: `RPScreenRecorder` integration for capturing `CMSampleBuffer` frames
- **`remo-objc` video encoder**: VideoToolbox H.264 hardware encoder with AVCC-to-Annex-B NAL conversion
- **`remo-desktop` fMP4 muxer**: Generates ISO BMFF init segments and moof/mdat fragments for MSE playback
- **`remo-desktop` stream receiver**: Ordered frame collection from broadcast channel
- **`remo-desktop` web player**: Standalone MSE-based video player page

### Changed

- `remo dashboard` no longer requires `--addr`; discovers devices automatically
- `remo-protocol` max frame size increased from 16 MiB to 64 MiB for video frames
- `remo-protocol` codec handles JSON (0x00), Binary (0x01), and Stream (0x02) frame types
- `remo-desktop` device manager Bonjour connection tries all resolved addresses instead of only the first

## [0.2.0] - 2026-03-21

### Added

- Bonjour/mDNS auto-discovery for simulators and Wi-Fi devices
- Multi-simulator support with auto-assigned ports
- Built-in introspection: view tree, screenshot, device info, app info
- Binary frame protocol (Type 0x01) for efficient screenshot transfer
- Debug-only SDK (`#if DEBUG` — compiles to no-ops in Release builds)
- GCD main-thread dispatch for safe UIKit access from Rust
- CI/CD pipeline (check, fmt, clippy, test, iOS build, Swift integration)
- Automated release pipeline (XCFramework → GitHub Release → SPM distribution)
- CLI commands: `tree`, `screenshot`, `info`

## [0.1.0] - 2026-03-20

### Added

- Full RPC round-trip: CLI → TCP → iOS SDK → capability handler → response
- `remo-protocol`: Message types + length-prefixed JSON framing codec
- `remo-transport`: Bidirectional TCP connection + async listener
- `remo-usbmuxd`: macOS usbmuxd client for USB device discovery + tunneling
- `remo-sdk`: iOS embedded TCP server + capability registry + C FFI
- `remo-objc`: ObjC runtime bridge via `objc2`
- `remo-desktop`: Device manager + RPC client
- `remo-cli`: `devices`, `call`, `list`, `watch` commands
- `RemoSwift`: Swift wrapper with zero-config auto-start
- `RemoExample`: Demo app with counter, items, activity log, settings
