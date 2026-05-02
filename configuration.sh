#!/bin/bash
set -euo pipefail

PIDFILE="/tmp/vm2tv-stream.pid"
CONFIG_DIR="$HOME/.config/vm2tv"
LOG_DIR="/var/log/vm2tv"

validate_resolution() {
    if ! [[ "$1" =~ ^[0-9]+x[0-9]+$ ]]; then
        echo "Error: Invalid resolution format. Use WIDTHxHEIGHT (e.g., 1920x1080)."
        exit 1
    fi
}

validate_port() {
    if ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 1 ] || [ "$1" -gt 65535 ]; then
        echo "Error: Invalid port number. Must be between 1 and 65535."
        exit 1
    fi
}

validate_path() {
    if [[ "$1" =~ [[:space:]] ]] || [[ "$1" == *".."* ]] || [[ "$1" != /* ]]; then
        echo "Error: Invalid path. Must be an absolute path without spaces or '..'."
        exit 1
    fi
}

cleanup() {
    echo ""
    echo "Stopping streaming processes..."
    if [ -f "$PIDFILE" ]; then
        while IFS= read -r pid; do
            kill "$pid" 2>/dev/null || true
        done < "$PIDFILE"
        rm -f "$PIDFILE"
    fi
    if pgrep -f "cloudflared tunnel" > /dev/null 2>&1; then
        pkill -f "cloudflared tunnel" 2>/dev/null || true
    fi
    echo "Cleanup complete."
}

trap cleanup EXIT INT TERM

check_system_resources() {
    echo "Checking system resources..."
    local cpu_cores
    cpu_cores=$(nproc)
    local mem_mb
    mem_mb=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)

    if [ "$mem_mb" -lt 512 ]; then
        echo "Warning: Less than 512MB RAM available. Streaming may be unstable."
    fi
    if [ "$cpu_cores" -lt 2 ]; then
        echo "Warning: Only $cpu_cores CPU core(s). Consider using 'ultrafast' preset."
    fi
    echo "Resources: ${cpu_cores} CPU cores, ${mem_mb}MB available RAM"
}

install_packages() {
    echo "Updating package lists and installing required packages..."
    sudo apt-get update
    sudo apt-get install -y ffmpeg avahi-daemon nginx pulseaudio-utils curl xdotool

    mkdir -p "$CONFIG_DIR"
    sudo mkdir -p "$LOG_DIR"
    echo "Installation complete."
}

install_cloudflared() {
    if command -v cloudflared &>/dev/null; then
        echo "cloudflared already installed."
        return
    fi

    echo "Installing cloudflared..."
    local arch
    arch=$(dpkg --print-architecture)
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}.deb" -o /tmp/cloudflared.deb
    sudo dpkg -i /tmp/cloudflared.deb
    rm -f /tmp/cloudflared.deb
    echo "cloudflared installed."
}

configure_nginx() {
    echo "Configuring nginx for HLS streaming..."

    read -rp "Enter the directory for HLS stream files (e.g., /var/www/html/hls): " webserver_dir
    validate_path "$webserver_dir"
    sudo mkdir -p "$webserver_dir"
    sudo chown www-data:www-data "$webserver_dir"

    read -rp "Enable basic auth password protection? (y/n): " enable_auth
    local auth_block=""
    if [[ "$enable_auth" == "y" ]]; then
        sudo apt-get install -y apache2-utils
        read -rp "Enter username: " auth_user
        read -rsp "Enter password: " auth_pass
        echo ""
        sudo htpasswd -cb /etc/nginx/.htpasswd "$auth_user" "$auth_pass"
        auth_block="        auth_basic \"VM Stream\";\n        auth_basic_user_file /etc/nginx/.htpasswd;"
    fi

    local nginx_conf="/etc/nginx/sites-available/vm2tv-hls"

    sudo tee "$nginx_conf" > /dev/null <<EOF
server {
    listen 80;
    server_name _;

    location /hls {
        alias ${webserver_dir};
        types {
            application/vnd.apple.mpegurl m3u8;
            video/mp2t ts;
        }
        add_header Cache-Control no-cache;
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, OPTIONS";
        add_header Access-Control-Allow-Headers "Range";
$(if [ -n "$auth_block" ]; then echo -e "$auth_block"; fi)
    }

    location /player {
        alias /var/www/html/vm2tv-player;
        index index.html;
    }

    location /health {
        return 200 'ok';
        add_header Content-Type text/plain;
    }
}
EOF

    sudo ln -sf "$nginx_conf" /etc/nginx/sites-enabled/vm2tv-hls
    sudo rm -f /etc/nginx/sites-enabled/default

    if sudo nginx -t 2>&1; then
        sudo systemctl restart nginx
        echo "nginx configuration complete."
    else
        echo "nginx configuration test failed."
        exit 1
    fi
}

create_web_player() {
    echo "Creating web player..."
    local player_dir="/var/www/html/vm2tv-player"
    sudo mkdir -p "$player_dir"

    sudo tee "$player_dir/index.html" > /dev/null <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VM2TV Stream</title>
    <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { background: #0a0a0a; color: #fff; font-family: system-ui, sans-serif; min-height: 100vh; display: flex; flex-direction: column; align-items: center; justify-content: center; }
        .container { width: 100%; max-width: 1280px; padding: 1rem; }
        h1 { text-align: center; margin-bottom: 1rem; font-size: 1.5rem; opacity: 0.9; }
        video { width: 100%; background: #000; border-radius: 8px; }
        .status { text-align: center; margin-top: 0.5rem; font-size: 0.85rem; opacity: 0.6; }
        .controls { display: flex; gap: 0.5rem; margin-top: 0.5rem; justify-content: center; }
        button { background: #222; border: 1px solid #444; color: #fff; padding: 0.4rem 1rem; border-radius: 4px; cursor: pointer; font-size: 0.85rem; }
        button:hover { background: #333; }
    </style>
</head>
<body>
    <div class="container">
        <h1>VM2TV Stream</h1>
        <video id="video" controls autoplay muted></video>
        <div class="status" id="status">Connecting...</div>
        <div class="controls">
            <button onclick="toggleMute()">Unmute</button>
            <button onclick="toggleFullscreen()">Fullscreen</button>
            <button onclick="reconnect()">Reconnect</button>
        </div>
    </div>
    <script>
        const video = document.getElementById('video');
        const status = document.getElementById('status');
        const streamUrl = '/hls/stream.m3u8';
        let hls;

        function startStream() {
            if (Hls.isSupported()) {
                hls = new Hls({ liveSyncDurationCount: 3, liveMaxLatencyDurationCount: 6 });
                hls.loadSource(streamUrl);
                hls.attachMedia(video);
                hls.on(Hls.Events.MANIFEST_PARSED, () => { video.play(); status.textContent = 'Live'; });
                hls.on(Hls.Events.ERROR, (e, data) => {
                    if (data.fatal) { status.textContent = 'Stream error - retrying...'; setTimeout(reconnect, 3000); }
                });
            } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
                video.src = streamUrl;
                video.addEventListener('loadedmetadata', () => { video.play(); status.textContent = 'Live'; });
            } else {
                status.textContent = 'HLS not supported in this browser';
            }
        }

        function toggleMute() { video.muted = !video.muted; event.target.textContent = video.muted ? 'Unmute' : 'Mute'; }
        function toggleFullscreen() { video.requestFullscreen ? video.requestFullscreen() : video.webkitRequestFullscreen(); }
        function reconnect() { if (hls) hls.destroy(); startStream(); }

        startStream();
    </script>
</body>
</html>
EOF
    echo "Web player created at /player"
}

select_capture_source() {
    echo ""
    echo "Select capture source:"
    echo "  1) Full screen"
    echo "  2) Specific window"
    echo "  3) Region of screen"
    read -rp "Choice [1-3]: " capture_choice

    CAPTURE_MODE="fullscreen"
    CAPTURE_TARGET=""

    case "$capture_choice" in
        2)
            CAPTURE_MODE="window"
            echo "Available windows:"
            wmctrl -l 2>/dev/null || xdotool search --name "" getwindowname 2>/dev/null | head -20
            echo ""
            echo "Options:"
            echo "  a) Click to select window"
            echo "  b) Enter window title to match"
            read -rp "Choice [a/b]: " win_method
            case "$win_method" in
                a)
                    echo "Click on the window you want to capture..."
                    CAPTURE_TARGET=$(xdotool selectwindow 2>/dev/null)
                    if [ -n "$CAPTURE_TARGET" ]; then
                        local win_name
                        win_name=$(xdotool getwindowname "$CAPTURE_TARGET" 2>/dev/null || echo "unknown")
                        echo "Selected: $win_name (ID: $CAPTURE_TARGET)"
                    fi
                    ;;
                b)
                    read -rp "Enter window title (partial match): " win_title
                    CAPTURE_TARGET=$(xdotool search --name "$win_title" | head -1)
                    if [ -z "$CAPTURE_TARGET" ]; then
                        echo "Window not found. Falling back to full screen."
                        CAPTURE_MODE="fullscreen"
                    else
                        echo "Found window ID: $CAPTURE_TARGET"
                    fi
                    ;;
            esac
            ;;
        3)
            CAPTURE_MODE="region"
            echo "Click and drag to select the capture region..."
            read -rp "Enter region as WxH+X+Y (e.g., 1280x720+100+50): " CAPTURE_TARGET
            if ! [[ "$CAPTURE_TARGET" =~ ^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$ ]]; then
                echo "Invalid format. Falling back to full screen."
                CAPTURE_MODE="fullscreen"
            fi
            ;;
    esac
}

build_ffmpeg_input() {
    local display_number="$1"
    local input_args=""

    case "$CAPTURE_MODE" in
        fullscreen)
            input_args="-f x11grab -video_size $STREAM_RES -framerate $STREAM_FPS -i ${display_number}"
            ;;
        window)
            if [ -n "$CAPTURE_TARGET" ]; then
                local win_geo
                win_geo=$(xdotool getwindowgeometry --shell "$CAPTURE_TARGET" 2>/dev/null)
                local win_x win_y win_w win_h
                win_x=$(echo "$win_geo" | grep "^X=" | cut -d= -f2)
                win_y=$(echo "$win_geo" | grep "^Y=" | cut -d= -f2)
                win_w=$(echo "$win_geo" | grep "^WIDTH=" | cut -d= -f2)
                win_h=$(echo "$win_geo" | grep "^HEIGHT=" | cut -d= -f2)
                input_args="-f x11grab -video_size ${win_w}x${win_h} -framerate $STREAM_FPS -i ${display_number}+${win_x},${win_y}"
            else
                input_args="-f x11grab -video_size $STREAM_RES -framerate $STREAM_FPS -i ${display_number}"
            fi
            ;;
        region)
            local region_size region_offset
            region_size=$(echo "$CAPTURE_TARGET" | grep -oP '^\d+x\d+')
            region_offset=$(echo "$CAPTURE_TARGET" | grep -oP '\+\d+\+\d+' | tr '+' ',')
            region_offset="${region_offset#,}"
            input_args="-f x11grab -video_size $region_size -framerate $STREAM_FPS -i ${display_number}+${region_offset}"
            ;;
    esac
    echo "$input_args"
}

select_quality_preset() {
    echo ""
    echo "Select streaming quality:"
    echo "  1) Low     (720p, 1000 kbps) - Low bandwidth"
    echo "  2) Medium  (1080p, 2500 kbps) - Balanced"
    echo "  3) High    (1080p, 5000 kbps) - High quality"
    echo "  4) Ultra   (1080p, 8000 kbps) - Maximum quality"
    echo "  5) Custom"
    read -rp "Choice [1-5]: " quality_choice

    case "$quality_choice" in
        1) STREAM_RES="1280x720"; STREAM_BITRATE="1000"; STREAM_PRESET="veryfast"; STREAM_FPS="24" ;;
        2) STREAM_RES="1920x1080"; STREAM_BITRATE="2500"; STREAM_PRESET="veryfast"; STREAM_FPS="30" ;;
        3) STREAM_RES="1920x1080"; STREAM_BITRATE="5000"; STREAM_PRESET="fast"; STREAM_FPS="30" ;;
        4) STREAM_RES="1920x1080"; STREAM_BITRATE="8000"; STREAM_PRESET="medium"; STREAM_FPS="60" ;;
        5)
            read -rp "Resolution (e.g., 1920x1080): " STREAM_RES
            validate_resolution "$STREAM_RES"
            read -rp "Bitrate in kbps: " STREAM_BITRATE
            read -rp "FPS (e.g., 30): " STREAM_FPS
            STREAM_PRESET="veryfast"
            ;;
        *) STREAM_RES="1920x1080"; STREAM_BITRATE="2500"; STREAM_PRESET="veryfast"; STREAM_FPS="30" ;;
    esac
}

configure_ffmpeg_hls() {
    echo "Configuring FFmpeg for HLS streaming..."

    read -rp "Enter the X11 display (default: :0.0): " display_number
    display_number="${display_number:-:0.0}"

    local hls_output="${webserver_dir}/stream.m3u8"
    local ffmpeg_input
    ffmpeg_input=$(build_ffmpeg_input "$display_number")

    echo "Starting FFmpeg stream (capture: $CAPTURE_MODE)..."
    eval ffmpeg $ffmpeg_input \
        -f pulse -ac 2 -i default \
        -c:v libx264 -b:v "${STREAM_BITRATE}k" -maxrate "$((STREAM_BITRATE * 12 / 10))k" \
        -bufsize "$((STREAM_BITRATE * 2))k" \
        -pix_fmt yuv420p -preset "$STREAM_PRESET" \
        -g "$((STREAM_FPS * 2))" -keyint_min "$((STREAM_FPS * 2))" \
        -c:a aac -b:a 128k \
        -f hls -hls_time 2 -hls_list_size 5 -hls_flags delete_segments+append_list \
        "$hls_output" > "$LOG_DIR/ffmpeg.log" 2>&1 &

    local ffmpeg_pid=$!
    echo "$ffmpeg_pid" >> "$PIDFILE"

    sleep 2
    if kill -0 "$ffmpeg_pid" 2>/dev/null; then
        echo "FFmpeg running (PID: $ffmpeg_pid), streaming to $hls_output"
    else
        echo "FFmpeg failed. Check $LOG_DIR/ffmpeg.log"
        tail -5 "$LOG_DIR/ffmpeg.log" 2>/dev/null
        exit 1
    fi
}

configure_multi_bitrate() {
    read -rp "Enable adaptive multi-bitrate streaming? (y/n): " enable_abr
    if [[ "$enable_abr" != "y" ]]; then
        return
    fi

    echo "Setting up adaptive bitrate variants..."
    local hls_dir="$webserver_dir"
    local display_number="${display_number:-:0.0}"

    sudo mkdir -p "$hls_dir/low" "$hls_dir/mid" "$hls_dir/high"
    sudo chown -R www-data:www-data "$hls_dir"

    ffmpeg -f x11grab -video_size "$STREAM_RES" -framerate "$STREAM_FPS" -i "$display_number" \
        -f pulse -ac 2 -i default \
        -filter_complex "[0:v]split=3[v1][v2][v3]; \
            [v1]scale=1920:1080[high]; \
            [v2]scale=1280:720[mid]; \
            [v3]scale=854:480[low]" \
        -map "[high]" -map 0:a -c:v libx264 -b:v 5000k -preset veryfast -c:a aac -b:a 128k \
            -f hls -hls_time 2 -hls_list_size 5 -hls_flags delete_segments "$hls_dir/high/stream.m3u8" \
        -map "[mid]" -map 0:a -c:v libx264 -b:v 2500k -preset veryfast -c:a aac -b:a 96k \
            -f hls -hls_time 2 -hls_list_size 5 -hls_flags delete_segments "$hls_dir/mid/stream.m3u8" \
        -map "[low]" -map 0:a -c:v libx264 -b:v 800k -preset veryfast -c:a aac -b:a 64k \
            -f hls -hls_time 2 -hls_list_size 5 -hls_flags delete_segments "$hls_dir/low/stream.m3u8" \
        > "$LOG_DIR/ffmpeg-abr.log" 2>&1 &

    echo "$!" >> "$PIDFILE"

    sudo tee "$hls_dir/master.m3u8" > /dev/null <<'EOF'
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=5200000,RESOLUTION=1920x1080
high/stream.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2600000,RESOLUTION=1280x720
mid/stream.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=864000,RESOLUTION=854x480
low/stream.m3u8
EOF

    echo "Adaptive bitrate streaming enabled. Master playlist: /hls/master.m3u8"
}

configure_avahi() {
    echo "Configuring Avahi for service discovery..."

    local avahi_service="/etc/avahi/services/vm2tv-hls.service"
    sudo tee "$avahi_service" > /dev/null <<'EOF'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">VM Stream on %h</name>
  <service>
    <type>_http._tcp</type>
    <port>80</port>
    <txt-record>path=/hls/stream.m3u8</txt-record>
  </service>
</service-group>
EOF

    sudo systemctl restart avahi-daemon
    echo "Avahi configuration complete."
}

configure_cloudflare_tunnel() {
    read -rp "Enable Cloudflare Tunnel for external access? (y/n): " enable_cf
    if [[ "$enable_cf" != "y" ]]; then
        echo "Skipping Cloudflare Tunnel. Stream is local-only."
        return
    fi

    install_cloudflared

    echo ""
    echo "Cloudflare Tunnel Setup Options:"
    echo "  1) Quick tunnel (no account needed, temporary URL)"
    echo "  2) Named tunnel (requires Cloudflare account, persistent URL)"
    read -rp "Choice [1-2]: " tunnel_choice

    case "$tunnel_choice" in
        1)
            echo "Starting quick tunnel..."
            cloudflared tunnel --url http://localhost:80 > "$LOG_DIR/cloudflared.log" 2>&1 &
            echo "$!" >> "$PIDFILE"

            sleep 5
            local tunnel_url
            tunnel_url=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG_DIR/cloudflared.log" | head -1)
            if [ -n "$tunnel_url" ]; then
                echo ""
                echo "============================================"
                echo "  EXTERNAL URL: $tunnel_url/hls/stream.m3u8"
                echo "  WEB PLAYER:   $tunnel_url/player"
                echo "============================================"
                echo "$tunnel_url" > "$CONFIG_DIR/tunnel-url.txt"
            else
                echo "Tunnel starting... check $LOG_DIR/cloudflared.log for URL"
            fi
            ;;
        2)
            if [ ! -f "$HOME/.cloudflared/cert.pem" ]; then
                echo "You need to authenticate with Cloudflare first."
                echo "Run: cloudflared tunnel login"
                echo "Then re-run this script."
                exit 1
            fi

            read -rp "Enter tunnel name (e.g., vm2tv): " tunnel_name
            read -rp "Enter your domain (e.g., stream.yourdomain.com): " tunnel_domain

            if ! cloudflared tunnel list | grep -q "$tunnel_name"; then
                cloudflared tunnel create "$tunnel_name"
            fi

            local tunnel_id
            tunnel_id=$(cloudflared tunnel list | grep "$tunnel_name" | awk '{print $1}')

            mkdir -p "$HOME/.cloudflared"
            cat > "$HOME/.cloudflared/config.yml" <<EOF
tunnel: ${tunnel_id}
credentials-file: $HOME/.cloudflared/${tunnel_id}.json

ingress:
  - hostname: ${tunnel_domain}
    service: http://localhost:80
  - service: http_status:404
EOF

            cloudflared tunnel route dns "$tunnel_name" "$tunnel_domain" 2>/dev/null || true

            cloudflared tunnel run "$tunnel_name" > "$LOG_DIR/cloudflared.log" 2>&1 &
            echo "$!" >> "$PIDFILE"

            echo ""
            echo "============================================"
            echo "  EXTERNAL URL: https://${tunnel_domain}/hls/stream.m3u8"
            echo "  WEB PLAYER:   https://${tunnel_domain}/player"
            echo "============================================"
            echo "https://${tunnel_domain}" > "$CONFIG_DIR/tunnel-url.txt"
            ;;
    esac
}

configure_rtsp() {
    read -rp "Set up RTSP streaming for low-latency? (y/n): " enable_rtsp
    if [[ "$enable_rtsp" != "y" ]]; then
        return
    fi

    sudo apt-get install -y gstreamer1.0-tools gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly

    read -rp "Enter the RTSP port (default: 8554): " rtsp_port
    rtsp_port="${rtsp_port:-8554}"
    validate_port "$rtsp_port"

    if command -v mediamtx &>/dev/null; then
        echo "Starting mediamtx RTSP server on port $rtsp_port..."
        mediamtx &
        echo "$!" >> "$PIDFILE"
    else
        echo "Note: Install mediamtx for full RTSP support."
        echo "Falling back to GStreamer RTP on port $rtsp_port..."
        gst-launch-1.0 -v ximagesrc use-damage=0 \
            ! videoconvert \
            ! x264enc tune=zerolatency bitrate=2000 speed-preset=superfast \
            ! rtph264pay config-interval=1 pt=96 \
            ! udpsink host=0.0.0.0 port="$rtsp_port" &
        echo "$!" >> "$PIDFILE"
    fi

    local rtsp_avahi="/etc/avahi/services/vm2tv-rtsp.service"
    sudo tee "$rtsp_avahi" > /dev/null <<EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">RTSP Stream on %h</name>
  <service>
    <type>_rtsp._tcp</type>
    <port>${rtsp_port}</port>
    <txt-record>path=/live</txt-record>
  </service>
</service-group>
EOF

    sudo systemctl restart avahi-daemon
    echo "RTSP configured on port $rtsp_port."
}

configure_restream() {
    read -rp "Push stream to external platform (Twitch/YouTube/Custom RTMP)? (y/n): " enable_restream
    if [[ "$enable_restream" != "y" ]]; then
        return
    fi

    echo "Select platform:"
    echo "  1) Twitch"
    echo "  2) YouTube Live"
    echo "  3) Custom RTMP URL"
    read -rp "Choice [1-3]: " platform_choice

    local rtmp_url
    case "$platform_choice" in
        1)
            read -rp "Enter Twitch stream key: " stream_key
            rtmp_url="rtmp://live.twitch.tv/app/${stream_key}"
            ;;
        2)
            read -rp "Enter YouTube stream key: " stream_key
            rtmp_url="rtmp://a.rtmp.youtube.com/live2/${stream_key}"
            ;;
        3)
            read -rp "Enter full RTMP URL (including stream key): " rtmp_url
            ;;
        *)
            echo "Invalid choice. Skipping."
            return
            ;;
    esac

    echo "Starting restream to platform..."
    ffmpeg -re -i "${webserver_dir}/stream.m3u8" \
        -c:v libx264 -preset veryfast -b:v "${STREAM_BITRATE}k" \
        -c:a aac -b:a 128k \
        -f flv "$rtmp_url" > "$LOG_DIR/restream.log" 2>&1 &

    echo "$!" >> "$PIDFILE"
    echo "Restreaming active. Check $LOG_DIR/restream.log for status."
}

show_status() {
    local ip
    ip=$(hostname -I | awk '{print $1}')
    echo ""
    echo "============================================"
    echo "  VM2TV Streaming Active"
    echo "============================================"
    echo "  Local:"
    echo "    HLS Stream:  http://${ip}/hls/stream.m3u8"
    echo "    Web Player:  http://${ip}/player"
    echo "    Health:      http://${ip}/health"
    if [ -f "$CONFIG_DIR/tunnel-url.txt" ]; then
        local tunnel_url
        tunnel_url=$(cat "$CONFIG_DIR/tunnel-url.txt")
        echo ""
        echo "  External (Cloudflare):"
        echo "    HLS Stream:  ${tunnel_url}/hls/stream.m3u8"
        echo "    Web Player:  ${tunnel_url}/player"
    fi
    echo "============================================"
    echo ""
    echo "  Logs: $LOG_DIR/"
    echo "  Press Ctrl+C to stop all streams."
    echo ""
}

# --- Main ---
echo "=== VM2TV - Linux VM Streaming Setup (X11) ==="
echo ""

check_system_resources
install_packages
configure_nginx
create_web_player
select_quality_preset
select_capture_source
configure_ffmpeg_hls
configure_multi_bitrate
configure_avahi
configure_rtsp
configure_cloudflare_tunnel
configure_restream
show_status

wait
