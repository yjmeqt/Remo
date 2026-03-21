# Security Policy

## Reporting a Vulnerability

Remo is currently a development tool and not intended for production deployment.
If you discover a security vulnerability, please report it by
[opening a GitHub issue](../../issues/new).

For issues that may be sensitive (e.g., involving credentials or private data
exposure), please note that in the issue title and avoid including exploit
details in the public description. A maintainer will follow up to coordinate
disclosure.

## Scope

This project communicates with local iOS devices over USB (usbmuxd) and local
network tunnels. Security considerations include:

- Proper handling of pairing records and device trust
- Safe parsing of untrusted plist/binary data from devices
- No exfiltration of device data beyond what the user explicitly requests

## Supported Versions

| Version       | Supported |
| ------------- | --------- |
| main (HEAD)   | Yes       |
| Older commits | No        |
