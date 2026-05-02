# Changelog

## [3.0.0] - 2026-05-02

### Added
- **Cloudflare Tunnel integration** for external access without port forwarding
  - Quick tunnel mode (no account needed, instant temporary URL)
  - Named tunnel mode (persistent custom domain with Cloudflare account)
- **Window-specific capture** on both X11 and Wayland
  - X11: click-to-select or match by window title via xdotool
  - Wayland: interactive window picker via wf-recorder, region select via slurp
- **Region capture** — stream only a portion of the screen
- **Built-in web player** at `/player` with hls.js, auto-reconnect, and fullscreen
- **Adaptive multi-bitrate streaming** (ABR) — 480p/720p/1080p master playlist
- **RTMP restreaming** — push to Twitch, YouTube Live, or custom RTMP endpoints
- **Quality presets** (Low/Medium/High/Ultra/Custom) with appropriate encoder settings
- **Basic auth protection** — optional password on the HLS endpoint
- **System resource check** before streaming (RAM/CPU warnings)
- **Management utility** (`vm2tv-ctl.sh`) with start/stop/status/restart/logs/url commands
- **Health endpoint** at `/health` for monitoring
- **Log files** stored in `/var/log/vm2tv/` for debugging
- **maxrate/bufsize** buffer control for consistent bitrate delivery
- CORS headers (Allow-Methods, Allow-Headers) for broader player compatibility

### Fixed
- nginx config appended outside server block causing nginx to fail on restart
- `root` directive mismatch — nginx looked for files at wrong path; replaced with `alias`
- Background process exit code check (`$?` after `&`) always returned 0, never catching failures
- Command injection vulnerability via unvalidated user input passed to `sudo bash -c`
- Conflicting FFmpeg rate control (`-crf` and `-b:v` set simultaneously; CRF silently won)
- wf-recorder `-g` flag passed resolution instead of required `x,y WxH` geometry format
- Wayland path had no audio capture — stream was silent
- RTSP pipeline sent raw RTP via `udpsink` to localhost — not a real RTSP server
- Beta Wayland script used `ximagesrc` for RTSP which only works on X11
- Deprecated FFmpeg `-s` flag replaced with `-video_size`

### Changed
- Dedicated nginx site config (`vm2tv-hls`) instead of modifying the default site
- `nginx -t` validates config before applying
- Scripts use `set -euo pipefail` for immediate failure on errors
- PID tracking with signal traps for clean shutdown
- RTSP fallback binds to `0.0.0.0` for network access
- Encoder preset changed to `veryfast` default for lower CPU usage
- HLS segment list reduced from 10 to 5 for faster channel switching
- Keyframe interval tied to framerate for proper segment alignment

## [2.0.0] - 2026-05-02

### Fixed
- All bugs from v1.0.0 (see v3.0.0 fixed section for full list)

### Added
- Input validation for resolution, port numbers, and paths
- Automatic Wayland/X11 detection
- Basic PID file tracking
- Signal traps for cleanup

## [1.0.0] - Initial Release

### Features
- HLS streaming via FFmpeg and nginx
- RTSP streaming via GStreamer (optional)
- Avahi service discovery for network devices
- Beta Wayland support via wf-recorder
