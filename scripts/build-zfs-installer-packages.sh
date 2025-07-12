#!/bin/bash
# scripts/build-zfs-installer-packages.sh
# Build ZFS packages for exact installer kernel

set -euo pipefail

# Configuration
INSTALLER_KERNEL="6.1.0-35-amd64"
ZFS_VERSION="2.1.11"  # Start with stable, can upgrade to 2.3.1 later
BUILD_DIR="$HOME/zfs-installer/custom-repo/build"
REPO_DIR="$HOME/zfs-installer/custom-repo"
PACKAGES_DIR="$REPO_DIR/packages"

echo "=== Building ZFS packages for installer kernel: $INSTALLER_KERNEL ==="

# Ensure clean environment
sudo apt update
mkdir -p "$BUILD_DIR" "$PACKAGES_DIR"
cd "$BUILD_DIR"

# Step 1: Install exact installer kernel headers
echo "Installing kernel headers for $INSTALLER_KERNEL..."
if ! dpkg -l | grep -q "linux-headers-$INSTALLER_KERNEL"; then
    sudo apt install -y "linux-headers-$INSTALLER_KERNEL"
else
    echo "Kernel headers already installed"
fi

# Verify headers installation
if [ ! -d "/usr/src/linux-headers-$INSTALLER_KERNEL" ]; then
    echo "ERROR: Kernel headers not found at /usr/src/linux-headers-$INSTALLER_KERNEL"
    exit 1
fi

echo "✅ Kernel headers installed: $(ls -d /usr/src/linux-headers-$INSTALLER_KERNEL)"

# Step 2: Get ZFS source
echo "Downloading ZFS source..."
rm -rf zfs-linux-*
apt source zfs-linux

# Find the source directory
ZFS_SOURCE_DIR=$(find . -maxdepth 1 -name "zfs-linux-*" -type d | head -1)
if [ -z "$ZFS_SOURCE_DIR" ]; then
    echo "ERROR: Could not find ZFS source directory"
    exit 1
fi

echo "✅ ZFS source: $ZFS_SOURCE_DIR"
cd "$ZFS_SOURCE_DIR"

# Step 3: Install build dependencies
echo "Installing build dependencies..."
sudo apt build-dep -y zfs-linux

# Step 4: Configure for installer kernel
echo "Configuring ZFS for kernel $INSTALLER_KERNEL..."
./configure \
    --with-linux="/usr/src/linux-headers-$INSTALLER_KERNEL" \
    --with-linux-obj="/usr/src/linux-headers-$INSTALLER_KERNEL" \
    --prefix=/usr \
    --sysconfdir=/etc \
    --sbindir=/sbin \
    --with-systemdunitdir=/lib/systemd/system \
    --enable-systemd

# Step 5: Build packages
echo "Building ZFS packages..."
make clean || true
make -j$(nproc)

# Build both userspace and kernel packages
echo "Creating Debian packages..."
make deb-utils deb-kmod

# Step 6: Organize packages with proper naming
echo "Organizing packages..."
cd "$BUILD_DIR"

# Find generated packages
UTILS_DEB=$(find . -name "*zfsutils-linux*.deb" | head -1)
KMOD_DEB=$(find . -name "*zfs-modules-${INSTALLER_KERNEL}*.deb" -o -name "*zfs-dkms*.deb" | head -1)

if [ -z "$UTILS_DEB" ] || [ -z "$KMOD_DEB" ]; then
    echo "ERROR: Could not find generated packages"
    echo "Available packages:"
    ls -la *.deb || echo "No .deb files found"
    exit 1
fi

# Copy to packages directory with clear naming
cp "$UTILS_DEB" "$PACKAGES_DIR/zfsutils-linux_${ZFS_VERSION}-installer_amd64.deb"
cp "$KMOD_DEB" "$PACKAGES_DIR/zfs-modules-${INSTALLER_KERNEL}_${ZFS_VERSION}-installer_amd64.deb"

# Copy any other related packages
find . -name "*.deb" -exec cp {} "$PACKAGES_DIR/" \;

echo "✅ Packages built and organized:"
ls -la "$PACKAGES_DIR/"

# Step 7: Test module loading
echo "Testing ZFS module compilation..."
cd "$ZFS_SOURCE_DIR"
if [ -f "module/zfs/zfs.ko" ]; then
    echo "✅ ZFS kernel module built successfully"
    file "module/zfs/zfs.ko"
    modinfo "module/zfs/zfs.ko" | head -10
else
    echo "⚠️  ZFS kernel module not found, checking build output..."
    find . -name "zfs.ko" -ls
fi

# Step 8: Create metapackage info
echo "Creating installation metadata..."
cat > "$PACKAGES_DIR/INSTALLER_INFO.txt" << EOF
ZFS Packages for Debian Installer
=================================

Installer Kernel: $INSTALLER_KERNEL
ZFS Version: $ZFS_VERSION
Build Date: $(date)
Build Host: $(hostname)

Installation order:
1. zfsutils-linux_${ZFS_VERSION}-installer_amd64.deb
2. zfs-modules-${INSTALLER_KERNEL}_${ZFS_VERSION}-installer_amd64.deb

Test installation:
sudo dpkg -i zfsutils-linux_${ZFS_VERSION}-installer_amd64.deb
sudo dpkg -i zfs-modules-${INSTALLER_KERNEL}_${ZFS_VERSION}-installer_amd64.deb
sudo modprobe zfs
zpool version

EOF

echo "=== Build Complete ==="
echo "Packages available in: $PACKAGES_DIR"
echo "Next steps:"
echo "1. Test package installation"
echo "2. Set up custom repository"
echo "3. Integrate with simple-cdd"

# Optional: Quick test if running as non-root
if [ "$EUID" -ne 0 ]; then
    echo ""
    echo "Run this to test the packages:"
    echo "cd $PACKAGES_DIR"
    echo "sudo dpkg -i zfsutils-linux_${ZFS_VERSION}-installer_amd64.deb"
    echo "sudo dpkg -i zfs-modules-${INSTALLER_KERNEL}_${ZFS_VERSION}-installer_amd64.deb"
    echo "sudo modprobe zfs && zpool version"
fi
