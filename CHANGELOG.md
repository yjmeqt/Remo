# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial workspace structure with `remo-core`, `remo-sdk`, and `remo-cli` crates
- usbmuxd protocol implementation (TCP connection, device listing)
- DTX (DeviceLink) transport layer for communicating with iOS services
- Remote XPC (RemoteXPC) tunneling support
- iOS framework build script (`build-ios.sh`) with C header generation via cbindgen
- Swift package wrapper for iOS integration

### 0.1.0-alpha Milestone

- [ ] Stable device discovery and pairing
- [ ] Screen mirroring via CoreMediaIO relay
- [ ] CLI tool for device management
- [ ] Published Swift package
