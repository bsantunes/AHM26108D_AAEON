#!/bin/bash

# This script automates the process of cloning the Linux kernel,
# integrating the Morse Micro Wi-Fi driver, applying necessary patches,
# and building/installing the new kernel.

# --- Configuration Variables ---
# Define the working directory where all operations will be performed.
# It is recommended to use a path where you have sufficient write permissions.
WORKING_DIR="/opt/kernel_build"

# Define the kernel version to clone
KERNEL_VERSION="v6.6"

# Define URLs for configuration and driver files
CONFIG_URL="https://raw.githubusercontent.com/bsantunes/AHM26108D/refs/heads/main/config-6.8.0-60-generic"
DRIVER_ZIP_URL="https://github.com/bsantunes/AHM26108D/raw/refs/heads/main/morsemicro_driver_rel_1_12_4_2024_Jun_11.zip"
PATCHES_ZIP_URL="https://github.com/bsantunes/AHM26108D/raw/refs/heads/main/morsemicro_kernel_patches_rel_1_12_4_2024_Jun_11.zip"
SDIO_QUIRK_PATCH_URL="https://raw.githubusercontent.com/bsantunes/AHM26108D/refs/heads/main/0010-sdio_18v_quirk.patch"
DEBUG_H_PATCH_URL="https://raw.githubusercontent.com/bsantunes/AHM26108D/refs/heads/main/debug.h.patch"
FIRMWARE_H_PATCH_URL="https://raw.githubusercontent.com/bsantunes/AHM26108D/refs/heads/main/firmware.h.patch"
MORSE_H_PATCH_URL="https://raw.githubusercontent.com/bsantunes/AHM26108D/refs/heads/main/morse.h.patch"
MORSE_TYPES_H_URL="https://raw.githubusercontent.com/bsantunes/AHM26108D/refs/heads/main/morse_types.h"

# --- Error Handling ---
# Exit immediately if a command exits with a non-zero status.
set -e

# Function to clean up on script exit or error
cleanup() {
    echo "--- Script execution finished or encountered an error. ---"
    echo "You can find the kernel source and driver files in: $WORKING_DIR"
}
trap cleanup EXIT

# --- Prerequisites Check ---
echo "--- Checking for necessary tools ---"
command -v git >/dev/null 2>&1 || { echo >&2 "Git is not installed. Please install it (e.g., sudo apt install git). Aborting."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo >&2 "Curl is not installed. Please install it (e.g., sudo apt install curl). Aborting."; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo >&2 "Unzip is not installed. Please install it (e.g., sudo apt install unzip). Aborting."; exit 1; }
command -v make >/dev/null 2>&1 || { echo >&2 "Make is not installed. Please install it (e.g., sudo apt install make). Aborting."; exit 1; }
command -v sed >/dev/null 2>&1 || { echo >&2 "Sed is not installed. Please install it (e.g., sudo apt install sed). Aborting."; exit 1; }
command -v patch >/dev/null 2>&1 || { echo >&2 "Patch is not installed. Please install it (e.g., sudo apt install patch). Aborting."; exit 1; }
echo "All required tools are present."

# --- Step 1: Prepare the Kernel Source ---
echo "--- Step 1: Preparing the Kernel Source ---"
echo "Creating working directory: $WORKING_DIR"
mkdir -p "$WORKING_DIR"
cd "$WORKING_DIR"

echo "Cloning Linux kernel $KERNEL_VERSION (depth=1)..."
git clone --depth=1 --branch="$KERNEL_VERSION" https://github.com/torvalds/linux.git
cd linux

echo "Downloading default kernel configuration from $CONFIG_URL..."
curl -o .config "$CONFIG_URL"

echo "Configuring kernel based on new .config (non-interactive)..."
yes '' | make oldconfig

echo "Enabling CONFIG_CRYPTO_CCM and CONFIG_CRYPTO_GCM in .config..."
# Ensure these lines are set to 'y', or add them if not present.
sed -i '/CONFIG_CRYPTO_CCM/d' .config # Remove existing line if any
sed -i '/CONFIG_CRYPTO_GCM/d' .config # Remove existing line if any
echo "CONFIG_CRYPTO_CCM=y" >> .config
echo "CONFIG_CRYPTO_GCM=y" >> .config

echo "Kernel source preparation complete."

# --- Step 2: Extract the Morse Micro Driver ---
echo "--- Step 2: Extracting the Morse Micro Driver ---"
cd "$WORKING_DIR"

echo "Downloading driver archive from $DRIVER_ZIP_URL..."
curl -L -O "$DRIVER_ZIP_URL"

DRIVER_ZIP_FILENAME=$(basename "$DRIVER_ZIP_URL")
DRIVER_EXTRACTED_DIR=$(basename "$DRIVER_ZIP_FILENAME" .zip)

echo "Unzipping $DRIVER_ZIP_FILENAME..."
unzip "$DRIVER_ZIP_FILENAME"
# Rename the extracted directory to a consistent name for easier scripting,
# as the unzipped folder name might vary slightly from the zip name.
# The original tutorial seems to indicate 'morsemicro_driver_rel_1_11_3_2024_Mar_28'
# as the unzipped directory, even though the downloaded zip is newer.
# We will use the actual unzipped directory name if it exists, otherwise assume the zip name.
if [ -d "morsemicro_driver_rel_1_11_3_2024_Mar_28" ]; then
    MORSE_DRIVER_SOURCE_DIR="morsemicro_driver_rel_1_11_3_2024_Mar_28"
elif [ -d "$DRIVER_EXTRACTED_DIR" ]; then
    MORSE_DRIVER_SOURCE_DIR="$DRIVER_EXTRACTED_DIR"
else
    echo "Could not find expected driver directory after unzipping. Please check the unzipped contents."
    exit 1
fi
echo "Driver extracted to: $WORKING_DIR/$MORSE_DRIVER_SOURCE_DIR"

echo "Driver extraction complete."

# --- Step 3: Integrate the Driver into the Kernel Source ---
echo "--- Step 3: Integrating the Driver into the Kernel Source ---"
cd "$WORKING_DIR/linux"

echo "Creating target directory drivers/net/wireless/morse..."
mkdir -p drivers/net/wireless/morse

echo "Copying driver files from $MORSE_DRIVER_SOURCE_DIR to kernel source..."
cp -r "$WORKING_DIR/$MORSE_DRIVER_SOURCE_DIR"/* drivers/net/wireless/morse/

echo "Driver integration complete."

# --- Step 4: Update the Kernel’s Build System ---
echo "--- Step 4: Updating the Kernel’s Build System ---"
cd "$WORKING_DIR/linux"

echo "Modifying drivers/net/wireless/Kconfig to include Morse driver Kconfig..."
# Add 'source "drivers/net/wireless/morse/Kconfig"' after other vendor-specific drivers
# This sed command inserts the line after the first occurrence of a 'source' line in drivers/net/wireless/Kconfig,
# or at the end of the file if no such line is found.
if ! grep -q 'source "drivers/net/wireless/morse/Kconfig"' drivers/net/wireless/Kconfig; then
    sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/morse\/Kconfig"' drivers/net/wireless/Kconfig || \
    sed -i '$ a source "drivers/net/wireless/morse/Kconfig"' drivers/net/wireless/Kconfig
fi


echo "Modifying drivers/net/wireless/Makefile to include Morse driver build rule..."
# Add 'obj-$(CONFIG_WLAN_VENDOR_MORSE) += morse/'
# This sed command inserts the line after the first occurrence of a 'obj-$' line in drivers/net/wireless/Makefile,
# or at the end of the file if no such line is found.
if ! grep -q 'obj-$(CONFIG_WLAN_VENDOR_MORSE) += morse/' drivers/net/wireless/Makefile; then
    sed -i '/obj-$(CONFIG_WLAN_VENDOR_TI) += ti\//a obj-$(CONFIG_WLAN_VENDOR_MORSE) += morse/' drivers/net/wireless/Makefile || \
    sed -i '$ a obj-$(CONFIG_WLAN_VENDOR_MORSE) += morse/' drivers/net/wireless/Makefile
fi

echo "Kernel build system updated."

# --- Step 5: Configure the Kernel with Morse Options ---
echo "--- Step 5: Configuring the Kernel with Morse Options ---"
cd "$WORKING_DIR/linux"

echo "Adding/modifying Morse Micro configuration options in .config..."
# Function to add/modify config options
set_config_option() {
    local option_name=$1
    local option_value=$2
    # Remove existing lines for the option to avoid duplicates
    sed -i "/^${option_name}=/d" .config
    sed -i "/^# ${option_name} is not set/d" .config
    # Add the desired option
    echo "${option_name}=${option_value}" >> .config
}

set_config_option "CONFIG_WLAN_VENDOR_MORSE" "m"
set_config_option "CONFIG_MORSE_SDIO" "y"
set_config_option "CONFIG_MORSE_USER_ACCESS" "y"
set_config_option "CONFIG_MORSE_VENDOR_COMMAND" "y"
set_config_option "CONFIG_CFG80211" "m"
set_config_option "CONFIG_MAC80211" "m"

echo "Kernel configuration for Morse Micro complete."

# --- Step 6: Apply Kernel Patches ---
echo "--- Step 6: Applying Kernel Patches ---"
cd "$WORKING_DIR"

echo "Downloading kernel patches archive from $PATCHES_ZIP_URL..."
curl -L -O "$PATCHES_ZIP_URL"

PATCHES_ZIP_FILENAME=$(basename "$PATCHES_ZIP_URL")
PATCHES_EXTRACTED_DIR=$(basename "$PATCHES_ZIP_FILENAME" .zip)

echo "Unzipping $PATCHES_ZIP_FILENAME..."
unzip "$PATCHES_ZIP_FILENAME"

echo "Downloading 0010-sdio_18v_quirk.patch..."
curl -L -O "$SDIO_QUIRK_PATCH_URL"
cp 0010-sdio_18v_quirk.patch "$PATCHES_EXTRACTED_DIR/6.6.x/"

echo "Applying bulk kernel patches to linux/ directory..."
cat "$PATCHES_EXTRACTED_DIR/6.6.x"/*.patch | patch -g0 -p1 -E -d linux/

echo "Creating 'patches' directory for individual patches..."
mkdir -p "$WORKING_DIR/patches"
cd "$WORKING_DIR/patches"

echo "Downloading individual header file patches..."
curl -L -O "$DEBUG_H_PATCH_URL"
curl -L -O "$FIRMWARE_H_PATCH_URL"
curl -L -O "$MORSE_H_PATCH_URL"

cd "$WORKING_DIR"

echo "Applying debug.h.patch..."
patch -p1 -d linux/ < patches/debug.h.patch
echo "Applying firmware.h.patch..."
patch -p1 -d linux/ < patches/firmware.h.patch
echo "Applying morse.h.patch..."
patch -p1 -d linux/ < patches/morse.h.patch

echo "Downloading morse_types.h..."
curl -L -O "$MORSE_TYPES_H_URL"
echo "Copying morse_types.h to kernel driver directory..."
cp morse_types.h linux/drivers/net/wireless/morse/

echo "Kernel patches applied."

# --- Step 7: Build the Kernel and Driver ---
echo "--- Step 7: Building the Kernel and Driver ---"
cd "$WORKING_DIR/linux"

echo "Building kernel modules and kernel (this may take a long time)..."
make -j"$(nproc)"

echo "Installing kernel modules (requires sudo)..."
sudo make modules_install

echo "Installing new kernel (requires sudo)..."
sudo make install

echo "Kernel and driver build complete."

# --- Step 8: Update the Bootloader ---
echo "--- Step 8: Updating the Bootloader and Rebooting ---"
echo "Updating GRUB bootloader configuration (requires sudo)..."
sudo update-grub

echo "---------------------------------------------------------"
echo "Kernel compilation and Morse Micro driver integration are complete."
echo "Please reboot your system for the changes to take effect and to boot into the new kernel."
echo "You can reboot now by running: sudo reboot"
echo "---------------------------------------------------------"
