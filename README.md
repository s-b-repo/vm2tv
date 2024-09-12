Linux VM Streaming Setup
#
linux vm screensharing with audio and video to your entire local network
#


RIP ANIWAVE
#
![Alt text](https://github.com/s-b-repo/vm2tv/blob/main/782c0e2e-a3de-4334-988f-b6c4597a1ff6.jpg)


This bash script sets up a Linux VM for streaming both screen and audio over the local network using HLS (HTTP Live Streaming) and optionally RTSP (Real-Time Streaming Protocol) for low-latency. It leverages open-source tools like FFmpeg, nginx, Avahi, and GStreamer for a seamless streaming experience.
Features

    HLS Streaming: Streams screen and audio via FFmpeg and nginx.
    RTSP Streaming (optional): Low-latency streaming using GStreamer and Avahi for network discovery.
    Avahi Service Discovery: Devices on the same network can easily discover the stream.
    Customizable: Configure screen resolution, display, and output paths.

Prerequisites

Before running the script, ensure that:

    You are running a Debian-based Linux distribution (e.g., Ubuntu).
    You have a graphical desktop environment set up if you want to capture the screen.

Installation

    Clone the repository:


git clone https://github.com//s-b-repo/vm2tv.git
cd linux-vm-streaming-setup

Make the script executable:


chmod +x vm_streaming_setup.sh

Run the script:



    ./vm_streaming_setup.sh

Usage

When running the script, it will:

    Install required packages: FFmpeg, nginx, Avahi, and GStreamer (if RTSP is enabled).
    Configure nginx: Set up HLS streaming by configuring nginx and asking for the directory where the stream files will be stored.
    Configure FFmpeg: Set up FFmpeg to capture the screen and audio and stream them as HLS.
    Configure Avahi: Set up Avahi for network service discovery, allowing other devices to find the stream easily.
    Optionally configure RTSP: If you enable RTSP, the script will set up a low-latency stream using GStreamer.

Options

During the script execution, you’ll be prompted for:

    The directory where HLS stream files will be stored (e.g., /var/www/html/hls).
    Screen resolution for streaming (e.g., 1920x1080).
    Display number (default is :0.0 for the default X11 session).
    Optionally, an RTSP port (default is 8554) if RTSP streaming is enabled.

Example: Accessing the Stream

After the setup is complete, your HLS stream will be available at:

http://<your-vm-ip>/hls/stream.m3u8

If RTSP is enabled, you can access it at:


rtsp://<your-vm-ip>:<rtsp-port>/live.sdp

Use a compatible player like VLC or an HLS/RTSP client to view the stream.
Troubleshooting

    nginx not starting: Ensure that port 80 is not in use by another service. You can check for conflicts with:

 

sudo lsof -i :80

No video displayed: Make sure you’ve provided the correct X11 display number (e.g., :0.0).
RTSP issues: Ensure GStreamer is properly installed and that the RTSP port you chose is not blocked by a firewall.
