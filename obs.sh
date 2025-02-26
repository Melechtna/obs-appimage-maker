#!/bin/bash

# Build script for OBS Studio AppImage on Arch Linux using JuNest
# Modular steps with toggles for debugging, builds latest stable OBS with ALL features into an 
# Created by Melechtna Antelecht
# Date: February 25, 2025

set -e

# Define variables
BASE_DIR="$HOME/.OBSBUILD"
JUNEST_DIR="$BASE_DIR/junest"
JUNEST_SYSTEM_DIR="$BASE_DIR/junest-system"
OBS_SRC_DIR="$JUNEST_SYSTEM_DIR/tmp/obs-studio"
BUILD_DIR="$OBS_SRC_DIR/build"
PORTABLE_DIR="$BUILD_DIR/rundir/RelWithDebInfo"
APPDIR="$JUNEST_SYSTEM_DIR/tmp/AppDir"
CPU_CORES=$(nproc)
APPIMAGE_FILE="$HOME/obs-studio.AppImage"

# Always export JUNEST_HOME
export JUNEST_HOME="$JUNEST_SYSTEM_DIR"

# Boolean toggles for each step (true = run, false = skip)
DO_SETUP_JUNEST=true
DO_INSTALL_DEPS=true
DO_CLONE_OBS=true
DO_BUILD_OBS=true
DO_INSTALL_OBS=true
DO_CREATE_APPIMAGE=true
DO_FINAL_CLEANUP=true

# Function: Setup JuNest
setup_junest() {
    if [ "$DO_SETUP_JUNEST" = true ]; then
        echo "Setting up JuNest environment..."
        mkdir -p "$JUNEST_DIR"
        cd "$JUNEST_DIR"
        echo "Cloning JuNest repo to $JUNEST_DIR..."
        git clone https://github.com/fsquillace/junest.git . || { echo "Failed to clone JuNest!"; exit 1; }
        mkdir -p "$JUNEST_SYSTEM_DIR"
        cd "$JUNEST_DIR/bin"
        echo "Initializing JuNest in $JUNEST_SYSTEM_DIR..."
        ./junest setup || { echo "JuNest setup failed!"; exit 1; }
    else
        echo "Skipping JuNest setup..."
    fi
}

# Function: Install dependencies
install_deps() {
    if [ "$DO_INSTALL_DEPS" = true ]; then
        echo "Installing base dependencies in JuNest..."
        "$JUNEST_DIR/bin/junest" -- sudo pacman -Syu --needed --noconfirm
        "$JUNEST_DIR/bin/junest" -- sudo pacman -S --needed --noconfirm \
            base-devel git cmake ninja pkgconf asio swig \
            qt6-base qt6-svg qt6-wayland uthash \
            libx11 libxcb libxcomposite libxinerama libxrandr libxkbcommon libdatachannel \
            pipewire pipewire-jack libpipewire pciutils \
            freetype2 fontconfig \
            luajit python nlohmann-json qrcodegencpp \
            websocketpp mbedtls \
            x264 x265 libvpx aom dav1d rav1e lame opus libvorbis libass fribidi speexdsp \
            libva libva-mesa-driver curl jansson \
            sndio vst3sdk mesa-libgl zlib openssl \
            vlc
        echo "Installing ffmpeg-obs and cef-minimal-obs-bin from AUR in JuNest..."
        "$JUNEST_DIR/bin/junest" -- yay -S --needed --noconfirm ffmpeg-obs cef-minimal-obs-bin
    else
        echo "Skipping dependency installation..."
    fi
}

# Function: Clone OBS
clone_obs() {
    if [ "$DO_CLONE_OBS" = true ]; then
        echo "Cloning OBS Studio into JuNest at $OBS_SRC_DIR..."
        "$JUNEST_DIR/bin/junest" -- git clone --recursive https://github.com/obsproject/obs-studio.git "$OBS_SRC_DIR"
        LATEST_TAG=$("$JUNEST_DIR/bin/junest" -- git -C "$OBS_SRC_DIR" tag -l --sort=-v:refname | grep -E "^[0-9]+\.[0-9]+\.[0-9]+$" | head -n 1)
        if [ -z "$LATEST_TAG" ]; then
            echo "Error: Could not determine latest release tag!"
            exit 1
        fi
        echo "Checking out latest release tag: $LATEST_TAG..."
        "$JUNEST_DIR/bin/junest" -- git -C "$OBS_SRC_DIR" checkout "$LATEST_TAG"
        "$JUNEST_DIR/bin/junest" -- git -C "$OBS_SRC_DIR" submodule update --init --recursive --force
    else
        echo "Skipping OBS clone..."
    fi
}

# Function: Build OBS
build_obs() {
    if [ "$DO_BUILD_OBS" = true ]; then
        echo "Building OBS in JuNest with all features enabled..."
        "$JUNEST_DIR/bin/junest" -- mkdir -p "$BUILD_DIR"
        "$JUNEST_DIR/bin/junest" -- bash -c "cd '$BUILD_DIR' && cmake -G Ninja \
            -DCMAKE_INSTALL_PREFIX=\"/usr\" \
            -DENABLE_VLC=ON \
            -DENABLE_BROWSER=ON \
            -DCEF_ROOT_DIR=\"/opt/cef-obs\" \
            -DENABLE_WEBRTC=ON \
            -DENABLE_JACK=ON \
            -DENABLE_SNDIO=ON \
            -DENABLE_VST=ON \
            -DENABLE_WAYLAND=ON \
            -DENABLE_PIPEWIRE=ON \
            -DENABLE_AJA=OFF \
            -DENABLE_NEW_MPEGTS_OUTPUT=ON \
            -DENABLE_NVENC=ON \
            -DENABLE_SCRIPTING=ON \
            -DENABLE_SCRIPTING_LUA=ON \
            -DENABLE_SCRIPTING_PYTHON=ON \
            -DCMAKE_C_FLAGS=\"-Wno-error=deprecated-declarations\" \
            -DCMAKE_CXX_FLAGS=\"-Wno-error=deprecated-declarations\" \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            '$OBS_SRC_DIR'"
        "$JUNEST_DIR/bin/junest" -- ninja -C "$BUILD_DIR" -j"$CPU_CORES"
    else
        echo "Skipping OBS build..."
    fi
}

# Function: Install OBS into JuNest system
install_obs() {
    if [ "$DO_INSTALL_OBS" = true ]; then
        echo "Installing OBS into JuNest system..."
        "$JUNEST_DIR/bin/junest" -- ninja -C "$BUILD_DIR" install || { echo "Failed to install OBS into JuNest system!"; exit 1; }
    else
        echo "Skipping OBS install..."
    fi
}

# Function: Create AppImage
create_appimage() {
    if [ "$DO_CREATE_APPIMAGE" = true ]; then
        echo "Preparing lean AppImage structure..."
        mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$APPDIR/usr/lib/obs-plugins" "$APPDIR/usr/share" "$APPDIR/usr/lib/qt6/plugins/platforms" "$APPDIR/usr/lib/qt6/plugins/imageformats" "$APPDIR/usr/lib/gdk-pixbuf-2.0"

        # Copy OBS binary from JuNest install
        "$JUNEST_DIR/bin/junest" -- cp -r "$JUNEST_SYSTEM_DIR/usr/bin/obs" "$APPDIR/usr/bin/"

        # Copy required libs, Qt plugins, VLC, Wayland, SVG support, and all OBS plugins
        echo "Copying required libraries, Qt plugins, VLC, Wayland, SVG support, and OBS plugins..."
        "$JUNEST_DIR/bin/junest" -- bash -c "ldd '$JUNEST_SYSTEM_DIR/usr/bin/obs' | grep -o '/usr/lib/[^ ]*' | sort -u | xargs -I {} cp -v {} '$APPDIR/usr/lib/'"
        "$JUNEST_DIR/bin/junest" -- cp -r "$JUNEST_SYSTEM_DIR/usr/lib/libobs"* "$APPDIR/usr/lib/"
        "$JUNEST_DIR/bin/junest" -- cp -r "$JUNEST_SYSTEM_DIR/usr/lib/obs-scripting"* "$APPDIR/usr/lib/"
        "$JUNEST_DIR/bin/junest" -- cp -r "$JUNEST_SYSTEM_DIR/usr/lib/libQt6Svg"* "$APPDIR/usr/lib/"
        "$JUNEST_DIR/bin/junest" -- cp -r "$JUNEST_SYSTEM_DIR/usr/lib/libvlc"* "$APPDIR/usr/lib/"
        "$JUNEST_DIR/bin/junest" -- cp -r "$JUNEST_SYSTEM_DIR/usr/lib/libwayland-client"* "$APPDIR/usr/lib/"
        "$JUNEST_DIR/bin/junest" -- cp -r "$JUNEST_SYSTEM_DIR/usr/lib/libwayland-server"* "$APPDIR/usr/lib/"
        "$JUNEST_DIR/bin/junest" -- cp -r "$JUNEST_SYSTEM_DIR/usr/lib/libwayland-egl"* "$APPDIR/usr/lib/"
        "$JUNEST_DIR/bin/junest" -- cp -r "$JUNEST_SYSTEM_DIR/usr/lib/qt6/plugins/platforms/"* "$APPDIR/usr/lib/qt6/plugins/platforms/"
        "$JUNEST_DIR/bin/junest" -- cp -r "$JUNEST_SYSTEM_DIR/usr/lib/qt6/plugins/imageformats/libqsvg.so" "$APPDIR/usr/lib/qt6/plugins/imageformats/"
        "$JUNEST_DIR/bin/junest" -- cp -r "$JUNEST_SYSTEM_DIR/usr/lib/gdk-pixbuf-2.0/"* "$APPDIR/usr/lib/gdk-pixbuf-2.0/"
        "$JUNEST_DIR/bin/junest" -- cp -r "$JUNEST_SYSTEM_DIR/usr/lib/obs-plugins/"* "$APPDIR/usr/lib/obs-plugins/"
        "$JUNEST_DIR/bin/junest" -- cp -r "$JUNEST_SYSTEM_DIR/usr/share/obs" "$APPDIR/usr/share/"
        "$JUNEST_DIR/bin/junest" -- cp -r "$JUNEST_SYSTEM_DIR/usr/share/icons/hicolor" "$APPDIR/usr/share/icons/"
        "$JUNEST_DIR/bin/junest" -- cp "$JUNEST_SYSTEM_DIR/usr/share/icons/hicolor/256x256/apps/com.obsproject.Studio.png" "$APPDIR/obs.png"
        ln -sf "$APPDIR/obs.png" "$APPDIR/.DirIcon"

        # Desktop file
        cat > "$APPDIR/obs-studio.desktop" << EOF
[Desktop Entry]
Name=OBS Studio
Exec=obs
Type=Application
Icon=obs
Categories=AudioVideo;Recorder;
Terminal=false
EOF

        # AppRun script
        cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib:$LD_LIBRARY_PATH"
export OBS_PLUGINS_PATH="$HERE/usr/lib/obs-plugins"
export QT_QPA_PLATFORM_PLUGIN_PATH="$HERE/usr/lib/qt6/plugins/platforms"
export QT_PLUGIN_PATH="$HERE/usr/lib/qt6/plugins"
export GDK_PIXBUF_MODULEDIR="$HERE/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders"
export OBS_DATA_PATH="$HERE/usr/share/obs/obs-studio"
export QT_DEBUG_PLUGINS=1
exec "$HERE/usr/bin/obs" --verbose
EOF
        chmod +x "$APPDIR/AppRun"

        # Package AppImage
        echo "Packaging as AppImage..."
        cd "$BASE_DIR"
        wget https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage -O appimagetool
        chmod +x appimagetool
        ./appimagetool "$APPDIR" "$APPIMAGE_FILE"

        # Test the AppImage directly on host
        echo "Testing AppImage on host..."
        "$APPIMAGE_FILE" || echo "Warning: Testing failed - ensure FUSE is set up on your host (e.g., 'sudo pacman -S fuse2')"
    else
        echo "Skipping AppImage creation..."
    fi
}

# Function: Final cleanup
final_cleanup() {
    if [ "$DO_FINAL_CLEANUP" = true ] && [ -f "$APPIMAGE_FILE" ]; then
        echo "Final cleanup: Removing build files..."
        rm -rf "$BASE_DIR"
    else
        echo "Skipping final cleanup (AppImage not created or disabled)..."
    fi
}

# Execute steps
setup_junest
install_deps
clone_obs
build_obs
install_obs
create_appimage
final_cleanup

# Verify result
if [ -f "$APPIMAGE_FILE" ]; then
    echo "Success! OBS AppImage created at $APPIMAGE_FILE"
    echo "Run it with: $APPIMAGE_FILE"
else
    echo "Error: AppImage creation failed or skipped!"
    exit 1
fi
