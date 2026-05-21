# VM2TV

Stream your Linux VM screen and audio to your local network — or the entire internet via Cloudflare Tunnel.

![VM2TV](https://github.com/s-b-repo/vm2tv/blob/main/782c0e2e-a3de-4334-988f-b6c4597a1ff6.jpg)

## Features

- **HLS Streaming** — HTTP Live Streaming via FFmpeg + nginx
- **Cloudflare Tunnel** — expose your stream externally without port forwarding
- **Window & Region Capture** — stream full screen, a specific window, or a custom region
- **Wayland + X11** — auto-detects your display server
- **Adaptive Bitrate** — multi-quality HLS (480p/720p/1080p) with master playlist
- **Built-in Web Player** — HTML5 player with hls.js at `/player`
- **RTMP Restreaming** — push to Twitch, YouTube Live, or custom RTMP endpoints
- **RTSP (Low-Latency)** — optional GStreamer/mediamtx-based RTSP stream
- **Avahi Discovery** — devices on the network auto-discover the stream
- **Password Protection** — optional basic auth on HLS endpoint
- **Quality Presets** — Low/Medium/High/Ultra or custom bitrate/resolution/fps
- **Management Utility** — `vm2tv-ctl.sh` for start/stop/status/restart/logs

## Prerequisites

- Debian-based Linux (Ubuntu, Kali, etc.)
- Graphical desktop (X11 or Wayland)
- PulseAudio or PipeWire for audio capture
- `sudo` access for nginx/avahi configuration

## Installation

```bash
git clone https://github.com/s-b-repo/vm2tv.git
cd vm2tv
chmod +x configuration.sh beta-wayland/beta-vm.sh vm2tv-ctl.sh
```

## Usage

### Quick Start

```bash
# X11 systems
./configuration.sh

# Wayland systems (also supports X11 with auto-detection)
./beta-wayland/beta-vm.sh
```

The script will walk you through:
1. Installing required packages
2. Choosing a quality preset
3. Selecting capture source (full screen / window / region)
4. Optionally enabling Cloudflare Tunnel, RTSP, and RTMP restreaming

### Management

```bash
./vm2tv-ctl.sh start    # Auto-selects Wayland or X11 script
./vm2tv-ctl.sh stop     # Kill all streaming processes
./vm2tv-ctl.sh status   # Show running processes and URLs
./vm2tv-ctl.sh restart  # Stop and start fresh
./vm2tv-ctl.sh logs     # Tail live logs
./vm2tv-ctl.sh url      # Print current stream URLs
```

## Accessing the Stream

### Local Network

| Endpoint | URL |
|----------|-----|
| HLS Stream | `http://<your-vm-ip>/hls/stream.m3u8` |
| Web Player | `http://<your-vm-ip>/player` |
| Adaptive (ABR) | `http://<your-vm-ip>/hls/master.m3u8` |
| Health Check | `http://<your-vm-ip>/health` |

### External (Cloudflare Tunnel)

When enabled, you get a public URL like:
```
https://random-name.trycloudflare.com/hls/stream.m3u8
https://random-name.trycloudflare.com/player
```

Or with a named tunnel and custom domain:
```
https://stream.yourdomain.com/player
```

### RTSP

If enabled:
```
rtsp://<your-vm-ip>:8554/live
```

## Capture Modes

| Mode | X11 | Wayland |
|------|-----|---------|
| Full screen | FFmpeg x11grab | wf-recorder |
| Specific window | xdotool click-to-select or title match | wf-recorder interactive picker |
| Screen region | WxH+X+Y coordinates | slurp region selector |

## Quality Presets

| Preset | Resolution | Bitrate | FPS | Use Case |
|--------|-----------|---------|-----|----------|
| Low | 1280x720 | 1000 kbps | 24 | Low bandwidth / mobile |
| Medium | 1920x1080 | 2500 kbps | 30 | Balanced |
| High | 1920x1080 | 5000 kbps | 30 | High quality viewing |
| Ultra | 1920x1080 | 8000 kbps | 60 | Maximum quality |
| Custom | User-defined | User-defined | User-defined | Specific needs |

## File Structure

```
vm2tv/
├── configuration.sh          # X11 streaming setup
├── beta-wayland/
│   └── beta-vm.sh           # Wayland + X11 auto-detect setup
├── vm2tv-ctl.sh             # Management utility (start/stop/status)
├── CHANGELOG.md             # Version history
├── LICENSE
└── README.md
```

## Cloudflare Tunnel Setup

### Quick Tunnel (No Account Required)

Select option 1 when prompted. A temporary public URL is generated instantly. The URL changes each time you restart.

### Named Tunnel (Persistent Domain)

1. Install cloudflared and authenticate:
   ```bash
   cloudflared tunnel login
   ```
2. Run the script and select option 2
3. Provide your tunnel name and domain
4. The script creates the tunnel, configures DNS, and starts serving

## Troubleshooting

| Problem | Solution |
|---------|----------|
| nginx won't start | Check port 80: `sudo lsof -i :80` |
| No video | Verify display: `echo $DISPLAY` or `echo $WAYLAND_DISPLAY` |
| No audio | Check PulseAudio: `pactl list short sinks` |
| FFmpeg fails | Check logs: `cat /var/log/vm2tv/ffmpeg.log` |
| Cloudflare tunnel no URL | Check logs: `cat /var/log/vm2tv/cloudflared.log` |
| Window capture wrong area | Ensure window isn't minimized; re-run capture selection |
| wf-recorder fails | Test manually: `wf-recorder -f test.mp4` |
| RTSP not connecting | Install mediamtx for proper RTSP server support |

## Logs

All streaming logs are stored in `/var/log/vm2tv/`:
- `ffmpeg.log` — main stream encoder output
- `ffmpeg-abr.log` — adaptive bitrate encoder
- `cloudflared.log` — tunnel status and URL
- `restream.log` — RTMP push output

## License

See [LICENSE](LICENSE) for details.

---

<details>
<summary><sub>Support this project</sub></summary>
<p align="center"><br/>
If this tool saved you time, consider tossing $1 in Monero:<br/><br/>
<code>478Lb78LDscQ8ukEDTZqXgEtjoBX1jMuVGvgfy2RagxZZk89YuyVYsganfLUKnwggz8YiBxhG25yWWiHUppG9uarSiseseY</code><br/><br/>
<sub>XMR — private, untraceable, appreciated.</sub>
</p>
</details>