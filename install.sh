#!/bin/bash
set -e

clear
# Original Script Repo: https://github.com/RickzDO/Installer_script_Binwalk3.1_sasquatch4.3
# Thanks a lot Rick, it'd have been a pain in the ass to get this done from scratch
echo "====================================================="
echo "🔧 Binwalk 3.1 + SquashFS 4.3 Patch Installer RickzDO"
echo "🔧 Adapted for OpenSUSE by ReKon64 with Claude Sonnet"
echo "====================================================="

# Variables
HOME_DIR="$HOME"
BINWALK_DIR="$HOME_DIR/binwalk"
VENV_DIR="$HOME_DIR/venv_binwalk"
SASQ_SRC="$HOME_DIR/sasquatch"
BUILD_FILES_DIR="$HOME_DIR/build_files_sasquatch"
SQUASHFS_TAR="$HOME_DIR/squashfs4.3.tar.gz"
SQUASHFS_DIR="$HOME_DIR/squashfs4.3"
PATCH_FILE="$SASQ_SRC/patches/patch0.txt"

echo "=== 1. Cleaning previous partial installs (if any) ==="
rm -rf "$BINWALK_DIR" "$VENV_DIR" "$SASQ_SRC" "$BUILD_FILES_DIR" "$SQUASHFS_DIR" "$SQUASHFS_TAR"

echo "=== 2. Installing system dependencies ==="
sudo zypper refresh
sudo zypper install -y \
    python3 \
    gcc \
    gcc-c++ \
    make \
    xz-devel \
    lzo-devel \
    zlib-devel \
    wget \
    git \
    patch \
    mtd-utils \
    gzip \
    bzip2 \
    tar \
    arj \
    p7zip \
    p7zip-full \
    cabextract \
    squashfs \
    sleuthkit \
    lzop \
    lhasa \
    zstd \
    dos2unix \
    fontconfig-devel \
    freetype2-devel \
    pkg-config \
    libopenssl-devel

echo "=== 3. Creating and activating Python virtual environment ==="
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

echo "=== 4. Installing Rust (via rustup) ==="
if ! command -v cargo &> /dev/null; then
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    source "$HOME/.cargo/env"
else
    echo "[i] cargo already available at $(which cargo), skipping rustup install"
    [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
fi

echo "=== 5. Updating pip, setuptools and wheel ==="
pip install --upgrade pip setuptools wheel

echo "=== 6. Installing required Python packages ==="
pip install kaleido toml six cstruct capstone pycryptodome matplotlib numpy pyusb git+https://github.com/sviehb/jefferson.git
pip install ubi_reader

# pyqt5 install on opensuse - prefer system package over pip
if ! python3 -c "import PyQt5" &>/dev/null; then
    echo "[i] PyQt5 not found in venv, attempting pip install..."
    pip install pyqt5 || echo "[!] PyQt5 install failed, continuing anyway - not critical"
fi

echo "=== 7. Cloning ReFirmLabs Binwalk ==="
if [ -d "$BINWALK_DIR" ]; then
    echo "binwalk dir exists, updating..."
    cd "$BINWALK_DIR"
    git pull
else
    git clone https://github.com/ReFirmLabs/binwalk.git "$BINWALK_DIR"
    cd "$BINWALK_DIR"
fi

echo "=== 8. Installing binwalk via Cargo ==="
cargo install --path .

echo "=== 9. Creating global symlink for binwalk ==="
BINWALK_BIN="$HOME/.cargo/bin/binwalk"
if [ -f "$BINWALK_BIN" ]; then
    sudo ln -sf "$BINWALK_BIN" /usr/local/bin/binwalk
    echo "Symlink created at /usr/local/bin/binwalk"
else
    echo "[!] binwalk binary not found at $BINWALK_BIN"
fi

echo "=== 10. Adding ~/.cargo/bin to PATH in ~/.profile ==="
if ! grep -q 'export PATH="$HOME/.cargo/bin:$PATH"' "$HOME/.profile"; then
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$HOME/.profile"
    echo "Added ~/.cargo/bin to ~/.profile"
fi

echo "=== 11. Cloning Sasquatch repo and checking out PR56 branch ==="
if [ -d "$SASQ_SRC" ]; then
    cd "$SASQ_SRC"
    git fetch origin
else
    git clone https://github.com/devttys0/sasquatch.git "$SASQ_SRC"
    cd "$SASQ_SRC"
fi
git fetch origin pull/56/head:pr-56
git checkout pr-56

echo "=== 12. Downloading and extracting squashfs4.3 ==="
cd "$HOME_DIR"
if [ ! -f "$SQUASHFS_TAR" ]; then
    wget -O "$SQUASHFS_TAR" \
        https://downloads.sourceforge.net/project/squashfs/squashfs/squashfs4.3/squashfs4.3.tar.gz
fi
rm -rf "$SQUASHFS_DIR"
mkdir -p "$SQUASHFS_DIR"
tar -xzf "$SQUASHFS_TAR" -C "$SQUASHFS_DIR" --strip-components=1

echo "=== 12. Cloning RickzDO build files and copying to squashfs-tools ==="
if [ -d "$BUILD_FILES_DIR" ]; then
    cd "$BUILD_FILES_DIR" && git pull
else
    git clone https://github.com/RickzDO/build_-_Makefile_for_sasquatch.git "$BUILD_FILES_DIR"
fi

if [ ! -d "$SQUASHFS_DIR/squashfs-tools" ]; then
    echo "[!] ERROR: squashfs-tools directory not found in $SQUASHFS_DIR"
    exit 1
fi

cp -v "$BUILD_FILES_DIR/Makefile" "$SQUASHFS_DIR/squashfs-tools/Makefile"
dos2unix "$SQUASHFS_DIR/squashfs-tools/Makefile"

echo "=== 13. Applying patch to squashfs-tools ==="
if [ ! -f "$PATCH_FILE" ]; then
    echo "[!] ERROR: patch0.txt not found at $PATCH_FILE"
    exit 1
fi

cd "$SQUASHFS_DIR"
if ! patch -p0 < "$PATCH_FILE"; then
    echo "[⚠️] WARNING: Patch did not apply cleanly. Check squashfs-tools/Makefile.rej for conflicts."
fi

echo "=== 14. Compiling squashfs-tools ==="
cd squashfs-tools

# Fix signal handler signatures for newer GCC
sed -i 's/void sigwinch_handler()/void sigwinch_handler(int sig)/' unsquashfs.c
sed -i 's/void sigalrm_handler()/void sigalrm_handler(int sig)/' unsquashfs.c

make && sudo make install

echo "=== 15. Building Sasquatch binary ==="
cd "$SASQ_SRC"
if [ -f Makefile ]; then
    make && sudo make install
fi

if command -v sasquatch &>/dev/null; then
    echo "✅ sasquatch available at $(which sasquatch)"
    sasquatch -v
    echo "=== Cleaning up build files ==="
    rm -rf "$SQUASHFS_DIR" "$SQUASHFS_TAR" "$BUILD_FILES_DIR" "$BINWALK_DIR" "$SASQ_SRC"
    echo "=== Installation complete! sasquatch is ready globally. ==="
    echo ""
    echo "NOTE: ~/venv_binwalk kept — contains ubireader and jefferson."
    echo "      Add 'source ~/venv_binwalk/bin/activate' to ~/.bashrc to always have them available. Or don't and fix their dockerfile I for sure dunno how"
else
    echo "[!] ERROR: sasquatch binary not found in PATH."
    exit 1
fi
