#!/bin/bash
set -e

cd /c/Users/Preston/git/honeyclip/ffmpeg_sources/ffmpeg

export PATH="/c/Users/Preston/.choosenim/toolchains/mingw64/bin:$PATH"
export PKG_CONFIG_PATH="/c/Users/Preston/git/honeyclip/build/lib/pkgconfig"

# Clean previous build
make clean 2>/dev/null || true

# Configure with our ar wrapper
./configure \
  --prefix=/c/Users/Preston/git/honeyclip/build \
  --enable-gpl \
  --enable-version3 \
  --enable-static \
  --disable-shared \
  --disable-schannel \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libvpx \
  --enable-libsvtav1 \
  --enable-libdav1d \
  --enable-libmp3lame \
  --enable-libopus \
  --extra-cflags="-I/c/Users/Preston/git/honeyclip/build/include" \
  --extra-ldflags="-L/c/Users/Preston/git/honeyclip/build/lib" \
  --ar="/c/Users/Preston/git/honeyclip/ar-wrapper.sh" \
  --enable-response-files

echo "Configuration complete. Building..."

make -j1

echo "Build complete. Installing..."

make install

echo "FFmpeg build and installation complete!"
