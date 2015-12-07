#! /bin/bash

################################################################################
#
# Build Android for the i.MX5X family
#
# Authors: Mauricio Cirelli
#          Remi Lorriaux
#
# - Images will be output to ../out directory.
# - Customizable parameters are at the top of this file.
#
# USAGE:
# - BOARD="your_board" ./build_android.sh
#   (the board has to be defined in the switch/case statement below)
#
################################################################################


print_usage()
{
echo -e "\nUSAGE: ${0} --board=[board name] --build-choice=[build type] [ --lunch-type=[lunch type] --cpus-android=[number of CPUs to build android] --cpus-kernel=[number of CPUs to build kernel + U-Boot] ]"
echo -e "* board name = {imx53_turing}"
echo -e "* build choice = {all, uboot, kernel, android}"
echo -e "* lunch-type = {eng, user}"
echo -e ""
echo -e "EXAMPLE:"
echo -e "${0} --board=imx53_loco --build-choice=all --lunch-type=eng\n"
echo -e "Avalable boards: imx53_loco imx53_smd imx53_turing\n"
return
}


#######################################
# Default parameters
#######################################

# Number of CPUs used to build [U-Boot+kernel] and [Android]
# Android can have issues building using several CPUs
CPUS_KERNEL=1
CPUS_ANDROID=1

# Android lunch type
LUNCH_TYPE=eng
BOARD="imx53_turing"

#######################################
# Parse command-line arguments
#######################################

for i in $*
do
	case $i in
    	--cpus-kernel=*)
		CPUS_KERNEL=`echo $i | sed 's/[-a-zA-Z0-9]*=//'`
		;;
	--cpus-android=*)
		CPUS_ANDROID=`echo $i | sed 's/[-a-zA-Z0-9]*=//'`
		;;
    	--board=*)
		BOARD=`echo $i | sed 's/[-a-zA-Z0-9]*=//'`
		;;
    	--build-choice=*)
		BUILD_CHOICE=`echo $i | sed 's/[-a-zA-Z]*=//'`
		;;
    	--lunch-type=*)
		LUNCH_TYPE=`echo $i | sed 's/[-a-zA-Z0-9]*=//'`
		;;
    	--default)
		DEFAULT=YES
		;;
    	*)
                # unknown option
		;;
  	esac
done


#######################################
# What to build (set to 0 to disable and > 0 to enable)
#######################################

BUILD_UBOOT=0
BUILD_KERNEL=0
BUILD_ANDROID=0

case "$BUILD_CHOICE" in
	"all")
		BUILD_UBOOT=1
		BUILD_KERNEL=1
		BUILD_ANDROID=1
		;;
	"uboot")
		BUILD_UBOOT=1
		;;

	"kernel")
		BUILD_KERNEL=1
		;;

	"android")
		BUILD_ANDROID=1
		;;
	*) 
		echo "ERROR: Incorrect build choice"
		print_usage
		exit 1
		;;
esac


#######################################
# Board-specific parameters
#######################################

case "$BOARD" in
	"imx53_loco")
		UBOOT_CFG=mx53_loco_android_config
		KERNEL_CFG=imx5_android_defconfig
		ANDROID_CFG=imx53_loco
		ANDROID_OUT_SUFFIX=imx53_loco
		;;
	"imx53_smd")
                UBOOT_CFG=mx53_smd_android_config
                KERNEL_CFG=imx5_android_defconfig
                ANDROID_CFG=imx53_smd
                ANDROID_OUT_SUFFIX=imx53_smd
                ;;
	"imx53_turing")
                UBOOT_CFG=mx53_turing_android_config
                KERNEL_CFG=imx53_turing_defconfig
                ANDROID_CFG=imx53_turing
                ANDROID_OUT_SUFFIX=imx53_turing
                ;;
	# Add other boards here

	*) 
		echo "ERROR: Incorrectly defined board"
		print_usage
		exit 1
		;;
esac


#######################################
# Android lunch type
#######################################

case "$LUNCH_TYPE" in
	"user")
		;;
	"eng")
		;;

	# Add other boards here

	*) 
		echo "ERROR: Incorrect Android lunch type"
		print_usage
		exit 1
		;;
esac


#######################################
# Set environment
#######################################

# The project root dir is one level above the script directory
ROOT_DIR=$(dirname ${0})/.. 
cd ${ROOT_DIR}
ROOT_DIR=$(pwd)

# Output directory (will contain images)
OUTPUT_DIR=${ROOT_DIR}/out/${ANDROID_OUT_SUFFIX}

# Android source root directory
ANDROID_SRC_ROOT=${ROOT_DIR}/src

UBOOT_SRC_ROOT=${ANDROID_SRC_ROOT}/bootable/bootloader/uboot-imx
KERNEL_SRC_ROOT=${ANDROID_SRC_ROOT}/kernel_imx
ANDROID_OUT_PATH=${ANDROID_SRC_ROOT}/out/target/product/${ANDROID_OUT_SUFFIX}

#
# NOTE: unlike Freescale's 10.3 documentation, we also choose 4.4.0 to build the
# kernel because 4.4.3 breaks unwinding (and therefore a lot of kernel hacking
# options)
#
# Toolchain for U-Boot and kernel
TOOLCHAIN_PATH=${ANDROID_SRC_ROOT}/prebuilt/linux-x86/toolchain/arm-eabi-4.4.0/bin
# Toolchain for Android
TOOLCHAIN_ANDROID_PATH=${ANDROID_SRC_ROOT}/prebuilt/linux-x86/toolchain/arm-eabi-4.4.3/bin

# Save original PATH
PATH_BASE=${PATH}


#######################################
# Display settings
#######################################

echo -e "\n################################################"
echo "Building for ${BOARD}:"
echo "  BUILD_UBOOT=${BUILD_UBOOT}"
echo "  BUILD_KERNEL=${BUILD_KERNEL}"
echo "  BUILD_ANDROID=${BUILD_ANDROID}"
echo ""
echo "Android Lunch type: ${LUNCH_TYPE}"
echo ""
echo "Using:"
echo "  CPUS_KERNEL=${CPUS_KERNEL}"
echo "  CPUS_ANDROID=${CPUS_ANDROID}"
echo "################################################"

# Create output directory
mkdir -p ${OUTPUT_DIR}


#######################################
# Build U-Boot
#######################################

# Add toolchain to the PATH
export PATH=${PATH_BASE}:${TOOLCHAIN_PATH}

if [ ${BUILD_UBOOT} -gt 0 ]; then
	cd ${UBOOT_SRC_ROOT}	&& \
        make distclean && \
	make ARCH=arm CROSS_COMPILE=arm-eabi- ${UBOOT_CFG}	&& \
	make ARCH=arm CROSS_COMPILE=arm-eabi- -j${CPUS_KERNEL} | tee ${ANDROID_SRC_ROOT}/build_${ANDROID_CFG}_uboot.log	&& \
	cp u-boot.bin ${OUTPUT_DIR}	&& \
	cd - || exit 1
fi


#######################################
# Build the kernel
#######################################

# Add toolchain and mkimage to the PATH
export PATH=${PATH_BASE}:${TOOLCHAIN_ANDROID_PATH}
export PATH=${PATH}:${UBOOT_SRC_ROOT}/tools

# Build
if [ ${BUILD_KERNEL} -gt 0 ]; then
	cd ${KERNEL_SRC_ROOT} || exit 1

	# Only configure if there is no .config
	if [ ! -f .config ]; then
		make ARCH=arm CROSS_COMPILE=arm-eabi- ${KERNEL_CFG} -j${CPUS_KERNEL}
	else
		echo ".config already exists - not configuring again"
		make ARCH=arm CROSS_COMPILE=arm-eabi- oldconfig
	fi

	make ARCH=arm CROSS_COMPILE=arm-eabi- uImage -j${CPUS_KERNEL} | tee ${ANDROID_SRC_ROOT}/build_${ANDROID_CFG}_kernel.log	&& \
#	make ARCH=arm CROSS_COMPILE=arm-eabi- modules -j${CPUS_KERNEL} && \
#	make ARCH=arm firmware_install INSTALL_FW_PATH=/tmp/firmware && \
#	make ARCH=arm headers_install INSTALL_HDR_PATH=${ANDROID_OUT_PATH} && \
#	mkdir -p ${ANDROID_OUT_PATH}/system/lib/modules && \
#	echo "Copying all modules to system/lib/modules" && \
#	find . -name "*.ko" -exec cp {} ${ANDROID_OUT_PATH}/system/lib/modules \; && \
#	mkdir -p ${ANDROID_OUT_PATH}/system/etc/firmware/ti-connectivity && \
#	cp /tmp/firmware/ti-connectivity/* ${ANDROID_OUT_PATH}/system/etc/firmware/ti-connectivity || : && \
#	rm -rf /tmp/firmware && \
	cp arch/arm/boot/uImage ${OUTPUT_DIR}	&& \
	cd - || exit 1
fi


#######################################
# Build Android
#######################################

# Add toolchain and mkimage to the PATH
export PATH=${PATH_BASE}:${TOOLCHAIN_ANDROID_PATH}
export PATH=${PATH}:${UBOOT_SRC_ROOT}/tools

# Build
if [ ${BUILD_ANDROID} -gt 0 ]; then
	cd ${ANDROID_SRC_ROOT}	&& \
	make PRODUCT-${ANDROID_CFG}-${LUNCH_TYPE} -j${CPUS_ANDROID} 2>&1   \
        | tee ${ANDROID_SRC_ROOT}/build_${ANDROID_CFG}_android.log	&& \
	cd - || exit 1
fi

# Package and copy images to our output directory
if [ ${BUILD_ANDROID} -gt 0 ]; then
	cd ${ANDROID_OUT_PATH}	&& \
	mkimage -A arm -O linux -T ramdisk -C none -a 0x70308000 -n \
		"Android Root Filesystem" -d ./ramdisk.img ./uramdisk.img	&& \
	mkdir -p ${OUTPUT_DIR}	&& \
	cp ramdisk.img ${OUTPUT_DIR}	&& \
	cp uramdisk.img ${OUTPUT_DIR}	&& \
	cp system.img ${OUTPUT_DIR}	&& \
	cp recovery.img ${OUTPUT_DIR}	&& \
	cd -
fi
