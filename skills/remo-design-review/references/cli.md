# Remo CLI Reference

This reference travels with the skill so the setup workflow does not depend on repository-only docs.

## Resolve the Binary

Use this order:

1. `.remo/bin/remo`
2. `remo`

Prefer the project-local binary for pinned installs.

## Global Options

```bash
remo --help
remo -v <command>
remo -vv <command>
remo -vvv <command>
```

## Command Summary

| Command | Purpose | Example |
|---------|---------|---------|
| `remo devices` | Discover simulators and devices | `remo devices` |
| `remo call` | Invoke a capability | `remo call -a $ADDR "__ping" '{}'` |
| `remo list` | List registered capabilities | `remo list -a $ADDR` |
| `remo watch` | Stream events | `remo watch -a $ADDR` |
| `remo tree` | Dump the view hierarchy | `remo tree -a $ADDR -m 4` |
| `remo screenshot` | Save a screenshot | `remo screenshot -a $ADDR -o shot.jpg` |
| `remo info` | Print device and app metadata | `remo info -a $ADDR` |
| `remo mirror` | Live mirror or MP4 save | `remo mirror -a $ADDR --web --save out.mp4` |
| `remo dashboard` | Launch the dashboard | `remo dashboard --port 8080` |
| `remo start` | Start the daemon | `remo start -d` |
| `remo stop` | Stop the daemon | `remo stop` |
| `remo status` | Check daemon health | `remo status` |

## Connection Model

Most device-targeted commands use one of these:

- `-a, --addr <host:port>` for direct TCP, common with simulators
- `-d, --device <usb-device-id>` for USB discovery, which overrides `--addr`

Simulator addresses can change on each launch. Re-run `remo devices` if a saved address stops working.

## Setup Verification Sequence

Use these commands in order:

```bash
remo devices
remo call -a <ADDRESS> "__ping" '{}'
remo screenshot -a <ADDRESS> -o /tmp/remo-verify.jpg
remo tree -a <ADDRESS>
```

## Command Notes

### `remo screenshot`

```bash
remo screenshot -a $ADDR -o shot.jpg
remo screenshot -a $ADDR -o shot.png --format png
remo screenshot -a $ADDR -o shot.jpg --format jpeg --quality 0.9
```

- screenshot output is written directly to the requested path
- the USB flag for this command is `-D, --device`, not lowercase `-d`

### `remo mirror`

```bash
remo mirror -a $ADDR --web
remo mirror -a $ADDR --save out.mp4
remo mirror -a $ADDR --web --save out.mp4
```

- at least one output mode is required
- `--web` opens the browser player
- `--save <path>` writes fragmented MP4 to disk
- the session runs until `Ctrl+C`

#### `mirror --save` lifecycle

1. the CLI sends `__start_mirror`
2. the output file is created immediately
3. frames are written incrementally
4. `Ctrl+C` triggers `__stop_mirror`
5. the writer finishes on end-of-stream
6. the CLI flushes and prints `Saved to ...`

Implications:

- choose the file path up front
- existing files are overwritten
- clean shutdown matters for finalizing the file

#### Timing caveat

Current MP4 output uses a fixed per-frame duration. Idle periods can be compressed, so saved videos may be shorter than wall-clock time.

Use `remo mirror --save` for debugging and quick animation review. Prefer `xcrun simctl io ... recordVideo` for timing-accurate simulator recordings.

## Built-ins

These built-in capabilities are always available:

- `__ping`
- `__list_capabilities`
- `__view_tree`
- `__screenshot`
- `__device_info`
- `__app_info`
- `__start_mirror`
- `__stop_mirror`

## Troubleshooting

| Symptom | What to do |
|---------|------------|
| `remo devices` shows nothing | Ensure the app is running and `Remo.start()` is on the debug path |
| Connection refused | Re-run `remo devices` and use the fresh address |
| Capability not found | Run `remo list -a $ADDR` |
| Screenshot is black | Bring the simulator to the foreground |
| Saved mirror video is too short | Use `simctl recordVideo` if timing accuracy matters |
