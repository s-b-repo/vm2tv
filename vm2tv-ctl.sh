#!/bin/bash
set -euo pipefail

PIDFILE="/tmp/vm2tv-stream.pid"
CONFIG_DIR="$HOME/.config/vm2tv"
LOG_DIR="/var/log/vm2tv"

usage() {
    echo "Usage: $0 {start|stop|status|restart|logs|url}"
    echo ""
    echo "Commands:"
    echo "  start    - Run configuration.sh or beta-vm.sh"
    echo "  stop     - Kill all vm2tv streaming processes"
    echo "  status   - Show running processes and stream URLs"
    echo "  restart  - Stop then start"
    echo "  logs     - Tail streaming logs"
    echo "  url      - Show current stream URLs"
    exit 1
}

stop_streams() {
    echo "Stopping vm2tv streams..."
    if [ -f "$PIDFILE" ]; then
        while IFS= read -r pid; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid"
                echo "  Killed PID $pid"
            fi
        done < "$PIDFILE"
        rm -f "$PIDFILE"
    fi
    if pgrep -f "cloudflared tunnel" > /dev/null 2>&1; then
        pkill -f "cloudflared tunnel"
        echo "  Killed cloudflared tunnel"
    fi
    pkill -f "ffmpeg.*hls" 2>/dev/null && echo "  Killed ffmpeg HLS" || true
    pkill -f "wf-recorder" 2>/dev/null && echo "  Killed wf-recorder" || true
    pkill -f "gst-launch.*rtph264pay" 2>/dev/null && echo "  Killed GStreamer RTP" || true
    echo "All streams stopped."
}

show_status() {
    echo "=== VM2TV Status ==="
    echo ""

    if [ -f "$PIDFILE" ]; then
        echo "Tracked processes:"
        while IFS= read -r pid; do
            if kill -0 "$pid" 2>/dev/null; then
                local cmd
                cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
                echo "  PID $pid ($cmd) - running"
            else
                echo "  PID $pid - dead"
            fi
        done < "$PIDFILE"
    else
        echo "No PID file found."
    fi

    echo ""
    if pgrep -f "ffmpeg.*hls" > /dev/null 2>&1; then
        echo "FFmpeg HLS: RUNNING"
    else
        echo "FFmpeg HLS: STOPPED"
    fi

    if pgrep -f "cloudflared tunnel" > /dev/null 2>&1; then
        echo "Cloudflare Tunnel: RUNNING"
    else
        echo "Cloudflare Tunnel: STOPPED"
    fi

    if systemctl is-active --quiet nginx; then
        echo "nginx: RUNNING"
    else
        echo "nginx: STOPPED"
    fi

    show_urls
}

show_urls() {
    echo ""
    local ip
    ip=$(hostname -I | awk '{print $1}')
    echo "Local URLs:"
    echo "  HLS:    http://${ip}/hls/stream.m3u8"
    echo "  Player: http://${ip}/player"

    if [ -f "$CONFIG_DIR/tunnel-url.txt" ]; then
        local tunnel_url
        tunnel_url=$(cat "$CONFIG_DIR/tunnel-url.txt")
        echo ""
        echo "External URLs:"
        echo "  HLS:    ${tunnel_url}/hls/stream.m3u8"
        echo "  Player: ${tunnel_url}/player"
    fi
}

show_logs() {
    if [ -d "$LOG_DIR" ]; then
        echo "Tailing logs from $LOG_DIR..."
        tail -f "$LOG_DIR"/*.log
    else
        echo "No logs found at $LOG_DIR"
    fi
}

case "${1:-}" in
    start)
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -f "$SCRIPT_DIR/beta-wayland/beta-vm.sh" ]; then
            exec "$SCRIPT_DIR/beta-wayland/beta-vm.sh"
        else
            exec "$SCRIPT_DIR/configuration.sh"
        fi
        ;;
    stop)
        stop_streams
        ;;
    status)
        show_status
        ;;
    restart)
        stop_streams
        sleep 2
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -f "$SCRIPT_DIR/beta-wayland/beta-vm.sh" ]; then
            exec "$SCRIPT_DIR/beta-wayland/beta-vm.sh"
        else
            exec "$SCRIPT_DIR/configuration.sh"
        fi
        ;;
    logs)
        show_logs
        ;;
    url|urls)
        show_urls
        ;;
    *)
        usage
        ;;
esac
