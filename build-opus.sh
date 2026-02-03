#!/bin/bash
set -e

cd /c/Users/Preston/git/honeyclip/ffmpeg_sources/opus
export PATH="/c/Users/Preston/.choosenim/toolchains/mingw64/bin:$PATH"

# Force disable FORTIFY_SOURCE at all levels - undefine it completely
export CFLAGS="-O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0"
export CPPFLAGS="-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0"

make distclean 2>/dev/null || true
./configure --prefix=/c/Users/Preston/git/honeyclip/build --disable-shared --enable-static --disable-hardening --disable-extra-programs
make -j8
make install
