#!/bin/bash

##################################################################################################################
#
# flash_android.sh
#
# Flashes the images for Android:
# - bootloader
# - kernel
# - uramdisk
# - rootfs
#
# CAUTION: 	This will entirely repartition and reformat the destination device!
# NOTE:		This script must run in the Android target/{product} output directory
#
# SYNTAX: 	flash_android.sh <board> <destination device> --<flags>
# 		flags: 		all			    creates partitions and flashes all images (default)
#				kernel			    flashes kernel image
#				u-boot			    flashes u-boot image
#				rootfs			    flashes file system images
#				ramdisk			    flashes Android RamDisk
#				recovery		    flashes Android Recovery partition
#				create-partitions	    creates all Android partitions
#                               userdata                    flashes the userdata image (not included in --all)
#
##################################################################################################################


#######################################
# Check input parameters
#######################################

SDCARD_DEV=$2
FLASH_FLAGS=$3
# The project root dir is one level above the script directory
ROOT_DIR=$(dirname ${0})/..
cd ${ROOT_DIR} || exit 1
ROOT_DIR=$(pwd)

# Output directory (will contain images)
ANDROID_PATH=${ROOT_DIR}/out/${1}

function main {
	cd ${ROOT_DIR} || exit 1
	ROOT_DIR=$(pwd)
	# Prints command options
	echo "Device	 	: $SDCARD_DEV"
	echo "Flags	 	: $FLASH_FLAGS"
	echo "Path		: $ANDROID_PATH"
	# Simplify the device to its minimal expression
	SDCARD_DEV="$(dirname $SDCARD_DEV)/$(basename $SDCARD_DEV)"

	if [ -z $SDCARD_DEV ]; then
		echo "\ERROR: Must set the destination device\n"
		echo "Syntax:  $0 [device]"
		echo "Example: $0 /dev/sdg\n"
		exit 1
	fi

	# Make sure we are not trying to write to the primary partition
	if [ $SDCARD_DEV = "/dev/sda" ]; then
		echo "\nERROR: Forbidden to write to /dev/sda\n"
		echo "Syntax:  $0 [device]"
		echo "Example: $0 /dev/sdg\n"
		exit 1
	fi

	# Check that we are writing to a block device
	if [ ! -b $SDCARD_DEV ]; then
		echo "\nERROR: $SDCARD_DEV is not a block device\n"
		exit 1
	fi

    # Check if the device name is mmcblkX
	if echo "${SDCARD_DEV}" | grep -q mmcblk; then
		PART_NAME=${SDCARD_DEV}p
	else
		PART_NAME=${SDCARD_DEV}
	fi

	run_command_options

	exit 0
}

#######################################
# Parse command-line arguments
#######################################
function run_command_options {
	case "$FLASH_FLAGS" in
	--kernel)
		echo "Option --kernel"
		flash_kernel;;
	--rootfs)
		echo "Option --rootfs"
		flash_rootfs;;
	--recovery)
		echo "Option --recovery"
		flash_recovery;;
	--u-boot)
		echo "Option --u-boot"
		erase_uboot
		flash_uboot;;
	--ramdisk)
		echo "Option --ramdisk"
		generate_ramdisk
		flash_uramdisk;;
	--create-partitions)
		echo "Option --create-partitions"
		check_erase_partitions
		create_partitions;;
    --userdata)
        echo "Option --userdata"
		flash_userdata;;
	*)
		echo "Option --all (default)"
		erase_uboot
		flash_uboot
		flash_kernel
		generate_ramdisk
		flash_uramdisk
		flash_rootfs
		flash_recovery;;
  	esac
	sync
	echo "Done"
}


#######################################
# Create Partition Table
#######################################
function check_erase_partitions {
	# One last confirmation
	echo -e "\n\nWARNING: ${SDCARD_DEV} will be entirely erased!"
	echo "Are you sure you want to continue (\"y\" to continue) y/*"
	read confirm
	if [ $confirm != "y" ]; then
		exit 0
	fi
}

function create_partitions {
	# Unmount all mounted partitions
	sudo umount ${SDCARD_DEV}*

	# Zero out Partition Table
	sudo dd if=/dev/zero of=${SDCARD_DEV} bs=1024 count=1

	# Extract the number of cylinders
	SIZE=`sudo fdisk -l ${SDCARD_DEV} | grep -i "disk\|disco" | awk '{print $5}'`
	CYLINDERS=`echo $SIZE/8225280 | bc`

	echo DISK SIZE - $SIZE bytes
	echo CYLINDERS - $CYLINDERS
	
	# Create all partitions
	# TODO: Create each Android partition using parted or fdisk

	# Format all partitions
	echo "Formatting partitions..."
	sudo dd if=/dev/zero of=${PART_NAME}1 bs=512 count=1
	sudo mkfs.vfat -F 32 ${PART_NAME}1 -n media		&& \
	sudo mkfs.ext4 ${PART_NAME}2 -O ^extent -L system	&& \	
	sudo mkfs.ext4 ${PART_NAME}4 -O ^extent -L recovery	&& \
	sudo mkfs.ext4 ${PART_NAME}5 -O ^extent -L data		&& \
	sudo mkfs.ext4 ${PART_NAME}6 -O ^extent -L cache

	if [ $? -ne 0 ]; then
		exit 1
	fi
}

#######################################
# Erase U-Boot environment
#######################################
function erase_uboot {
	echo "Erasing U-Boot environment..."
	sudo dd if=/dev/zero of=${SDCARD_DEV} bs=1024 seek=1 count=1023 || exit 1
	sync
}

#######################################
# Generates uramdisk image
#######################################
function generate_ramdisk {
	echo "Creating uramdisk..."
	mkimage -A arm -O linux -T ramdisk -C none -a 0x70408000 -n "Android Root Filesystem" -d ${ANDROID_PATH}/ramdisk.img ${ANDROID_PATH}/uramdisk.img
}

#######################################
# Copy the bootloader
#######################################
function flash_uboot {
	echo "Copying u-boot..."
	sudo dd if=${ANDROID_PATH}/u-boot.bin of=${SDCARD_DEV} bs=1K skip=1 seek=1 || exit -1
	sync
}

#######################################
# Copy the Android RamDisk
#######################################
function flash_uramdisk {
	echo "Copying uramdisk..."
	sudo dd if=${ANDROID_PATH}/uramdisk.img of=${SDCARD_DEV} bs=1M seek=6 || exit -1
	sync
}

#######################################
# Copy the kernel
#######################################
function flash_kernel {
	echo "Copying kernel..."
	sudo dd if=${ANDROID_PATH}/uImage of=${SDCARD_DEV} bs=1M seek=1 || exit -1
	sync
}

#######################################
# Write the root filesytem
#######################################
function flash_rootfs {
	echo "Writing root filesystem to ${PART_NAME}2..."
	sudo dd if=${ANDROID_PATH}/system.img of=${PART_NAME}2 || exit -1
	sync
}

#######################################
# Write the userdata filesytem
#######################################
function flash_userdata {
	echo "Writing userdata filesystem to ${PART_NAME}5..."
	sudo dd if=${ANDROID_PATH}/userdata.img of=${PART_NAME}5 || exit -1
	sync
}

#######################################
# Write the recovery filesytem
#######################################
function flash_recovery {
	echo "Writing recovery filesystem to ${PART_NAME}4..."
	sudo dd if=${ANDROID_PATH}/recovery.img of=${PART_NAME}4 || exit -1
	sync
}


# call script entry point
main
