#!/bin/bash

# Function to install packages
install_packages() {
    echo "Updating package lists and installing required packages..."
    sudo apt-get update
    if sudo apt-get install -y ffmpeg avahi-daemon nginx gstreamer1.0-tools; then
        echo "Installation complete."
    else
        echo "Failed to install packages. Exiting."
        exit 1
    fi
}

# Function to configure nginx for HLS
configure_nginx() {
    echo "Configuring nginx for HLS streaming..."

    # Ask user for web server directory
    read -p "Enter the directory where the HLS stream files will be stored (e.g., /var/www/html/hls): " webserver_dir
    sudo mkdir -p "$webserver_dir"

    # Add HLS configuration to nginx
    nginx_conf="/etc/nginx/sites-available/default"
    if ! grep -q "location /hls" "$nginx_conf"; then
        sudo bash -c "cat >> $nginx_conf <<EOF

        location /hls {
            types {
                application/vnd.apple.mpegurl m3u8;
                video/mp2t ts;
            }
            root $webserver_dir;
            add_header Cache-Control no-cache;
        }
EOF"
    fi

    # Restart nginx
    sudo systemctl restart nginx
    if [ $? -eq 0 ]; then
        echo "nginx configuration complete."
    else
        echo "nginx failed to restart. Exiting."
        exit 1
    fi
}

# Function to configure FFmpeg HLS stream
configure_ffmpeg_hls() {
    echo "Starting FFmpeg for HLS streaming..."

    # Ask user for screen size and display
    read -p "Enter the screen resolution (e.g., 1920x1080): " screen_size
    read -p "Enter the display number (default: :0.0): " display_number
    display_number=${display_number:-":0.0"}

    # Ask user for output file location
    read -p "Enter the output path for the HLS stream (default: $webserver_dir/stream.m3u8): " hls_output
    hls_output=${hls_output:-"$webserver_dir/stream.m3u8"}

    # Run FFmpeg command to stream the screen and audio
    echo "Starting FFmpeg stream..."
    ffmpeg -f x11grab -s "$screen_size" -i "$display_number" -f pulse -ac 2 -i default \
        -c:v libx264 -pix_fmt yuv420p -preset fast -crf 28 -g 50 -c:a aac \
        -f hls -hls_time 2 -hls_list_size 10 -hls_flags delete_segments \
        "$hls_output" &
    
    if [ $? -eq 0 ]; then
        echo "FFmpeg is running and streaming to $hls_output"
    else
        echo "FFmpeg failed to start. Exiting."
        exit 1
    fi
}

# Function to configure Avahi for network discovery
configure_avahi() {
    echo "Configuring Avahi for service discovery..."

    avahi_service="/etc/avahi/services/stream.service"
    sudo bash -c "cat > $avahi_service <<EOF
<?xml version=\"1.0\" standalone='no'?>
<!DOCTYPE service-group SYSTEM \"avahi-service.dtd\">
<service-group>
  <name replace-wildcards=\"yes\">VM Stream on %h</name>
  <service>
    <type>_http._tcp</type>
    <port>80</port>
    <txt-record>path=/hls/stream.m3u8</txt-record>
  </service>
</service-group>
EOF"

    # Restart Avahi
    sudo systemctl restart avahi-daemon
    if [ $? -eq 0 ]; then
        echo "Avahi configuration complete."
    else
        echo "Failed to restart Avahi. Exiting."
        exit 1
    fi
}

# Function to offer RTSP setup
configure_rtsp() {
    echo "Would you like to set up RTSP streaming for low-latency? (y/n)"
    read -r enable_rtsp

    if [ "$enable_rtsp" == "y" ]; then
        # Install GStreamer if not already installed
        echo "Installing GStreamer for RTSP streaming..."
        sudo apt-get install -y gstreamer1.0-tools

        # Ask user for RTSP port
        read -p "Enter the RTSP stream port (default: 8554): " rtsp_port
        rtsp_port=${rtsp_port:-8554}

        # Start RTSP stream using GStreamer (revised to work properly)
        echo "Starting RTSP stream on port $rtsp_port..."
        gst-launch-1.0 -v ximagesrc ! videoconvert ! x264enc tune=zerolatency ! rtph264pay ! udpsink host=127.0.0.1 port=$rtsp_port &

        # Create Avahi service for RTSP
        rtsp_avahi_service="/etc/avahi/services/rtsp.service"
        sudo bash -c "cat > $rtsp_avahi_service <<EOF
<?xml version=\"1.0\" standalone='no'?>
<!DOCTYPE service-group SYSTEM \"avahi-service.dtd\">
<service-group>
  <name replace-wildcards=\"yes\">RTSP Stream on %h</name>
  <service>
    <type>_rtsp._tcp</type>
    <port>$rtsp_port</port>
    <txt-record>path=/live.sdp</txt-record>
  </service>
</service-group>
EOF"
        sudo systemctl restart avahi-daemon
        if [ $? -eq 0 ]; then
            echo "RTSP streaming is running on port $rtsp_port."
        else
            echo "Failed to start RTSP stream. Exiting."
            exit 1
        fi
    else
        echo "Skipping RTSP setup."
    fi
}

# Main script execution
echo "Welcome to the Linux VM Streaming Setup!"

# Step 1: Install required packages
install_packages

# Step 2: Configure nginx for HLS
configure_nginx

# Step 3: Configure FFmpeg for HLS streaming
configure_ffmpeg_hls

# Step 4: Configure Avahi for service discovery
configure_avahi

# Step 5: Optionally configure RTSP for low-latency streaming
configure_rtsp

echo "Setup complete! Your stream is now available on the local network."
