#!/bin/bash
#
# Copyright (c) 2017-2021, Baikal Electronics, JSC. All rights reserved.
#
# Dependencies: bash coreutils mke2fs sfdisk
#-------------------------------------------------------------------------------

echo "Multitarget build script for Baikal-M SoC development"

#-------------------------------------------------------------------------------
# Include environment & functions
#-------------------------------------------------------------------------------
SCRIPTSDIR=`dirname $( readlink -f $0 )`
[[ -e ${SCRIPTSDIR}/environment.sh ]] && source ${SCRIPTSDIR}/environment.sh || exit 2

err_trap()
{
  echo "ERROR in line: $1">&2
}

trap 'err_trap $LINENO' err

#-------------------------------------------------------------------------------
# Usage
#-------------------------------------------------------------------------------
showhelp()
{
  if [[ ${BAIKAL_SDK_MAJOR_VERSION} == '4' ]]; then
    MALI_OPTION=--mali
  else
    MALI_OPTION=
  fi

  cat << EOF
Usage: $( basename $0 ) <target> <options>

Supported targets:
  dbm         - Build images for DBM
  mbm10       - Build images for MBM10
  mbm20       - Build images for MBM20

Options:
  -c,  --clean             clean previous builds (kernel, uefi, arm-tf)
  -k,  --kernel            build Linux kernel with current config (.config)
  -d,  --defconfig         make kernel .config from defconfig
  -m,  --modules           build kernel modules with current config (.config)
  -u,  --uefi              build UEFI (release)
  -ud, --uefi-debug        build UEFI (debug)
  -t,  --armtf             build ARM TF (release)
  -td, --armtf-debug       build ARM TF (debug)
EOF

  if [[ ${BAIKAL_SDK_MAJOR_VERSION} == '4' ]]; then
    cat << EOF
  -M,  --mali              build mali kernel module (release)
EOF
  fi

  cat << EOF
  -D,  --vdec              build vdec kernel modules (release)
  -i,  --initrd            build initrd filesystem image
  -b,  --bootrom           build BootROM
  -bt, --bootrom-truncate  build BootROM and truncate 32 MiB
  -bl, --bootrom-linux     build BootROM with Linux rescue image
  -a,  --all               like --clean --defconfig --kernel --modules --initrd
                             ${MALI_OPTION} --vdec --uefi --armtf --bootrom
  -ad, --all-debug         like --clean --defconfig --kernel --modules --initrd
                             ${MALI_OPTION} --vdec --uefi-debug --armtf-debug --bootrom
  -h,  --help              display this help

Shell variables:
  BASETOOLS_SKIP=yes       skip UEFI 'BaseTools' build
EOF
}

BAIKAL_SDK_MAJOR_VERSION=$(cat ${TOP}/VERSION | cut -d . -f 1)

#-------------------------------------------------------------------------------
# Set build target & variables
#-------------------------------------------------------------------------------

# Process target argument
if [[ -z "$1" ]]; then
  showerror "No target provided"
  showhelp
  exit 1
fi

SUBTARGET=$1; shift
case ${SUBTARGET} in
  'dbm')
    ;;
  'mbm10'|'mbm20')
    SINGLE_IMG=1
    ;;
  'qemu')
    ;;
  'h'|'-h'|'--h'|'help'|'-help'|'--help'|'?'|'-?')
    showhelp
    exit 0
    ;;
  *)
    showerror "Unknown target '${SUBTARGET}'"
    showhelp
    exit 1
    ;;
esac

TARGET=${PLATFORM}
DEFTARGET=${TARGET}_defconfig

# Directories
BOOTROM_DIR=${SRC}/bootrom
QEMU_DIR=${SRC}/qemu
KERNEL_DIR=${SRC}/kernel
KMODULES_DIR=${BUILDS}/kernel/modules
INITRD_DIR=${SRC}/initrd
UEFI_DIR=${SRC}/uefi
ACPICA_DIR=${SRC}/acpica
ARMTF_DIR=${SRC}/arm-tf
MALI_DIR=${SRC}/mali
VDEC_DIR=${SRC}/vdec

# Kernel build info
KBUILD_BUILD_USER="Baikal-M-SDK"
if [[ -n "${SDK_VERSION}" ]]; then
  KBUILD_BUILD_USER=${KBUILD_BUILD_USER}-${SDK_VERSION}
fi

KBUILD_BUILD_VERSION=1
if [[ -f "${TOP}/.build" ]]; then
  TMP_VER=`cat ${TOP}/.build`
  KBUILD_BUILD_VERSION=`expr ${TMP_VER} + 1`
fi
echo ${KBUILD_BUILD_VERSION} > ${TOP}/.build

KBUILD_BUILD_HOST=${BUILDER}
if [[ -d "${TOP}/../.git" ]]; then
  KBUILD_BUILD_HOST="baikal.developer"
fi

export KBUILD_BUILD_VERSION
export KBUILD_BUILD_USER
export KBUILD_BUILD_HOST

# Process options
OPTIONS="$@"
if [[ -z ${OPTIONS} ]]; then
  showerror "No options provided for target '${SUBTARGET}'"
  showhelp
  exit 1
fi

for i in ${OPTIONS}
do
  case 'x'${i} in
    'x-c'|'x--clean')
      MAKE_CLEAN=1
      ;;
    'x-d'|'x--defconfig')
      KERNEL_DEFCONFIG=1
      ;;
    'x-k'|'x--kernel')
      BUILD_KERNEL=1
      ;;
    'x-m'|'x--modules')
      BUILD_KERNEL_MODULES=1
      ;;
    'x-ud'|'x--uefi-debug')
      BUILD_UEFI=1
      ;;
    'x-u'|'x--uefi')
      BUILD_UEFI=1
      BUILD_UEFI_RELEASE=1
      ;;
    'x-td'|'x--armtf-debug')
      BUILD_ARMTF=1
      ;;
    'x-t'|'x--armtf')
      BUILD_ARMTF=1
      BUILD_ARMTF_RELEASE=1
      ;;
    'x-b'|'x--bootrom')
      BUILD_BOOTROM=1
      ;;
    'x-bt'|'x--bootrom-truncate')
      BUILD_BOOTROM=1
      BOOTROM_TRUNCATE=1
      ;;
    'x-bl'|'x--bootrom-linux')
      BUILD_BOOTROM=1
      BOOTROM_TRUNCATE=1
      BOOTROM_LINUX=1
      ;;
    'x-i'|'x--initrd')
      BUILD_INITRD=1
      ;;
    'x-M'|'x--mali')
      if [[ ${BAIKAL_SDK_MAJOR_VERSION} != '4' ]]; then
        showerror "Option '-M' ('--mali') is only compatible with Linux kernel 4.x"
        showhelp
        exit 1
      fi
      BUILD_MALI=1
      ;;
    'x-D'|'x--vdec')
      BUILD_VDEC=1
      ;;
    'x-q'|'x--qemu')
      if [[ ${SUBTARGET} != 'qemu' ]]; then
        showerror "Option '-q' ('--qemu') is only compatible with 'qemu' target"
        showhelp
        exit 1
      fi
      BUILD_QEMU=1
      ;;
    'x-e'|'x--empties')
      BUILD_EMPTIES=1
      ;;
    'x-a'|'x--all')
      MAKE_CLEAN=1
      KERNEL_DEFCONFIG=1
      BUILD_KERNEL=1
      BUILD_KERNEL_MODULES=1
      BUILD_INITRD=1
      BUILD_UEFI=1
      BUILD_UEFI_RELEASE=1
      BUILD_ARMTF=1
      BUILD_ARMTF_RELEASE=1
      if [[ ${BAIKAL_SDK_MAJOR_VERSION} == '4' ]]; then
        BUILD_MALI=1
      fi
      BUILD_VDEC=1
      BUILD_BOOTROM=1
      if [[ ${SUBTARGET} == 'qemu' ]]; then
        BOOTROM_TRUNCATE=1
        BOOTROM_LINUX=1
        BUILD_QEMU=1
        BUILD_EMPTIES=1
      fi
      ;;
    'x-ad'|'x--all-debug')
      MAKE_CLEAN=1
      KERNEL_DEFCONFIG=1
      BUILD_KERNEL=1
      BUILD_KERNEL_MODULES=1
      BUILD_INITRD=1
      BUILD_UEFI=1
      BUILD_ARMTF=1
      if [[ ${BAIKAL_SDK_MAJOR_VERSION} == '4' ]]; then
        BUILD_MALI=1
      fi
      BUILD_VDEC=1
      BUILD_BOOTROM=1
      if [[ ${SUBTARGET} == 'qemu' ]]; then
        BOOTROM_TRUNCATE=1
        BOOTROM_LINUX=1
        BUILD_QEMU=1
        BUILD_EMPTIES=1
      fi
      ;;
    'x-h'|'x--help'|'x-?'|'x--h'|'x-help')
      showhelp
      exit 0
      ;;
    *)
      showerror "Unknown option '${i}'"
      showhelp
      exit 1
      ;;
  esac
done

#-------------------------------------------------------------------------------
# Start build
#-------------------------------------------------------------------------------
showinfo "Starting build process #${KBUILD_BUILD_VERSION} ..."
[[ ! -d ${IMG} ]] && mkdir -p ${IMG}
cd ${TOP}
STATUS=0

#-------------------------------------------------------------------------------
# make clean
#-------------------------------------------------------------------------------
if [[ -n ${MAKE_CLEAN} ]]; then
  showinfo "Executing target 'MAKE CLEAN':"

  # KERNEL
  cd ${KERNEL_DIR}
  echo " Clean 'kernel'..." && ${MAKE} clean
  STATUS=$(( $STATUS || $? ))

  if [[ ${SUBTARGET} == 'qemu' ]]; then
    if [[ -f Makefile ]]; then
      cd ${QEMU_DIR}
      echo " Clean 'qemu'..."
      ${MAKE} -C soc_term clean
      ${MAKE} clean
      ${MAKE} distclean
    fi
    STATUS=$(( $STATUS || $? ))

    if [[ -d aarch64-softmmu ]]; then
      rm -rf aarch64-softmmu
    fi
    STATUS=$(( $STATUS || $? ))
  fi

  # UEFI
  cd ${UEFI_DIR}
  echo " Clean 'UEFI'..."  # <--- TODO
  if [[ -d Build ]]; then
    rm -rf Build
  fi
  STATUS=$(( $STATUS || $? ))

  # ACPICA
  cd ${ACPICA_DIR}
  make clean
  STATUS=$(( $STATUS || $? ))

  # ARM-TF
  cd ${ARMTF_DIR}
  echo " Clean 'ARM TF'..." && ${MAKE} clean
  STATUS=$(( $STATUS || $? ))
  if [[ -d build ]]; then
    rm -rf build
  fi
  STATUS=$(( $STATUS || $? ))

  # initrd
  cd ${INITRD_DIR}/programs
  echo " Clean 'INITRD'..." && ${MAKE} clean
  STATUS=$(( $STATUS || $? ))

  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "MAKE CLEAN"
  cd ${TOP}
else
  showinfo "Skip 'MAKE CLEAN'"
fi

#-------------------------------------------------------------------------------
# make kernel defconfig
#-------------------------------------------------------------------------------
if [[ -n ${KERNEL_DEFCONFIG} ]]; then
  showinfo "Executing target 'KERNEL DEFCONFIG':"

  cd ${KERNEL_DIR}
  ${MAKE} ${DEFTARGET}
  STATUS=$(( $STATUS || $? ))

  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "KERNEL DEFCONFIG"
  cd ${TOP}
else
  showinfo "Skip 'KERNEL DEFCONFIG'"
fi

#-------------------------------------------------------------------------------
# build kernel
#-------------------------------------------------------------------------------
if [[ -n ${BUILD_KERNEL} ]]; then
  showinfo "Executing target 'BUILD KERNEL':"
  if [[ ! -d ${KERNEL_DIR} ]] || [[ ! -f ${KERNEL_DIR}/Makefile ]]; then
    showwarn " Kernel source corrupted or not present!"
    show_err_and_exit 1 "BUILD KERNEL"
  fi

  KERNEL_BUILD_OPTIONS=''
  # Example (to set specific version): KERNEL_BUILD_OPTIONS='LOCALVERSION=-xxx'
  KERNELVER=`cat ${KERNEL_DIR}/Makefile | head -4 | grep VERSION    | cut -d' ' -f3`
  KERNELPTL=`cat ${KERNEL_DIR}/Makefile | head -4 | grep PATCHLEVEL | cut -d' ' -f3`
  KERNELSUB=`cat ${KERNEL_DIR}/Makefile | head -4 | grep SUBLEVEL   | cut -d' ' -f3`
  showinfo "Building kernel ${KERNELVER}.${KERNELPTL}.${KERNELSUB}"

  LINUXBIN=${KERNEL_DIR}/arch/${ARCH}/boot/Image
  [[ ${SUBTARGET} == "dbm"   ]] && DTBBIN=${KERNEL_DIR}/arch/${ARCH}/boot/dts/baikal/bm-dbm.dtb
  [[ ${SUBTARGET} == "mbm10" ]] && DTBBIN=${KERNEL_DIR}/arch/${ARCH}/boot/dts/baikal/bm-mbm10.dtb
  [[ ${SUBTARGET} == "mbm20" ]] && DTBBIN=${KERNEL_DIR}/arch/${ARCH}/boot/dts/baikal/bm-mbm20.dtb
  [[ ${SUBTARGET} == "qemu"  ]] && DTBBIN=${KERNEL_DIR}/arch/${ARCH}/boot/dts/baikal/bm-qemu.dtb

  cd ${KERNEL_DIR}

  # Build kernel defconfig
  if [[ ! -f .config ]]; then
    showwarn "No kernel config found. Build default"
    ${MAKE} ${DEFTARGET}
    STATUS=$(( $STATUS || $? ))
  fi

  # Build kernel
  ${MAKE} ${KERNEL_BUILD_OPTIONS}
  STATUS=$(( $STATUS || $? ))

  # Build kernel device tree
  ${MAKE} dtbs
  STATUS=$(( $STATUS || $? ))

  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD KERNEL"

  # Copy build results
  cp -f ${DTBBIN} ${IMG}/${SUBTARGET}.dtb
  cp -f ${LINUXBIN} ${IMG}/${SUBTARGET}.$(basename ${LINUXBIN})
  cat ${LINUXBIN} | gzip -9 > ${IMG}/${SUBTARGET}.$(basename ${LINUXBIN}).gz
  cp -f System.map ${IMG}/${SUBTARGET}.System.map
  STATUS=$(( $STATUS || $? ))

  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD KERNEL"
  cd ${TOP}
else
  showinfo "Skip 'BUILD KERNEL'"
fi

#-------------------------------------------------------------------------------
# build kernel modules
#-------------------------------------------------------------------------------
if [[ -n ${BUILD_KERNEL_MODULES} ]]; then
  showinfo "Executing target 'BUILD KERNEL MODULES':"

  MODULES_BUILD_OPTIONS=''
  # Example (to set specific version): MODULES_BUILD_OPTIONS='LOCALVERSION=-xxx'
  cd ${KERNEL_DIR}
  ${MAKE} ${MODULES_BUILD_OPTIONS} modules
  STATUS=$(( $STATUS || $? ))
  [[ -d ${KMODULES_DIR} ]] && rm -rf ${KMODULES_DIR}
  mkdir -p ${KMODULES_DIR}
  ${MAKE} modules_install INSTALL_MOD_PATH=${KMODULES_DIR}
  STATUS=$(( $STATUS || $? ))
  find ${KMODULES_DIR} -type l -print | xargs rm -f
  STATUS=$(( $STATUS || $? ))

  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD KERNEL MODULES"
  cd ${TOP}
else
  showinfo "Skip 'BUILD KERNEL MODULES'"
fi

#-------------------------------------------------------------------------------
# build initrd image
#-------------------------------------------------------------------------------
if [[ -n ${BUILD_INITRD} ]]; then
  showinfo "Executing target 'BUILD INITRD':"

  cd ${INITRD_DIR}
  ${SCRIPTSDIR}/build-initrd-img.sh ${PLATFORM} -d
  STATUS=$(( $STATUS || $? ))

  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD INITRD"
  cd ${TOP}
else
  showinfo "Skip 'BUILD INITRD'"
fi

#-------------------------------------------------------------------------------
# build mali kernel module
#-------------------------------------------------------------------------------
if [[ -n ${BUILD_MALI} ]]; then
  showinfo "Executing target 'BUILD MALI':"

  ARCHTMP=${ARCH}
  echo $ARCH
  echo $CROSS_COMPILE
  export KDIR=$KERNEL_DIR
  echo $KDIR
  export MALI_REL=r26p0-01rel0

  cd ${MALI_DIR}/TX011-SW-99002-${MALI_REL}/driver/product/kernel/drivers/gpu/arm/midgard
  ${MAKE} clean
  ${MAKE} PLATFORM=dummy MALI_RELEASE_NAME=${MALI_REL} \
CONFIG_MALI_PLATFORM_NAME=devicetree CONFIG_MALI_NO_MALI_DEFAULT_GPU=t62x \
CONFIG_MALI_MIDGARD=m CONFIG_SMC_PROTECTED_MODE_SWITCHER=m \
MALI_CUSTOMER_RELEASE=1 MALI_USE_CSF=0 MALI_COVERAGE=0 CONFIG_MALI_KUTF=n \
MALI_UNIT_TEST=0 MALI_KERNEL_TEST_API=0 MALI_MOCK_TEST=0

  STATUS=$(( $STATUS || $? ))
  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD MALI"
  cp mali_kbase.ko ${IMG}

  cd ${TOP}
else
  showinfo "Skip 'BUILD MALI'"
fi

#-------------------------------------------------------------------------------
# build vdec kernel modules
#-------------------------------------------------------------------------------
if [[ -n ${BUILD_VDEC} ]]; then
  showinfo "Executing target 'BUILD VDEC':"
  echo $ARCH
  echo $CROSS_COMPILE
  export KDIR=${KERNEL_DIR}
  echo $KDIR

  cd ${VDEC_DIR}
  make clean
  make
  STATUS=$(( $STATUS || $? ))
  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD VDEC"
  cp linux/mem_man/img_mem.ko ${IMG}
  cp linux/vxd/vxd.ko ${IMG}

  cd ${TOP}
else
  showinfo "Skip 'BUILD VDEC'"
fi

#-------------------------------------------------------------------------------
# build qemu
#-------------------------------------------------------------------------------
if [[ -n ${BUILD_QEMU} ]]; then
  showinfo "Executing target 'BUILD QEMU':"

  QEMU_OPTIONS="--target-list=aarch64-softmmu --enable-sdl --with-sdlabi=2.0 --enable-gtk"
  QEMU_EXECUTABLE=aarch64-softmmu/qemu-system-aarch64

  ARCHTMP=${ARCH}
  unset ARCH
  CROSSTMP=${CROSS_COMPILE}
  unset CROSS_COMPILE

  cd ${QEMU_DIR}

  ./configure ${QEMU_OPTIONS}
  STATUS=$(( $STATUS || $? ))
  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD QEMU"

  ${MAKE}
  STATUS=$(( $STATUS || $? ))
  [[ ! -f ${QEMU_EXECUTABLE} ]] && show_err_and_exit $STATUS "BUILD QEMU"

  cp -f ${QEMU_EXECUTABLE} ${IMG}
  STATUS=$(( $STATUS || $? ))
  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD QEMU"

  cp -f pc-bios/keymaps/en-us ${IMG}
  cp -f pc-bios/keymaps/common ${IMG}

  cd soc_term
  ${MAKE}
  STATUS=$(( $STATUS || $? ))
  [[ ! -f soc_term ]] && show_err_and_exit $STATUS "BUILD QEMU"
  cp -f soc_term ${IMG}

  export ARCH=${ARCHTMP}
  export CROSS_COMPILE=${CROSSTMP}
  cd ${TOP}
else
  showinfo "Skip 'BUILD QEMU'"
fi

#-------------------------------------------------------------------------------
# build uefi
#-------------------------------------------------------------------------------
if [[ -n ${BUILD_UEFI} ]]; then
  showinfo "Executing target 'BUILD UEFI':"

  # Build IASL if not present
  IASL=${BIN}/iasl
  if [[ ! -x ${IASL} ]]; then
    showinfo " --> subtarget 'BUILD IASL':"
    cd ${ACPICA_DIR}
    make clean
    OPT_CFLAGS="-Wno-error=format" make iasl
    cp generate/unix/bin/iasl ${IASL}
    STATUS=$(( $STATUS || $? ))
    [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD IASL"
  fi

  cd ${UEFI_DIR}

  BAIKAL_SDK_VERSION=`cat ${TOP}/VERSION`
  BAIKAL_SDK_REVISION=0x`echo $BAIKAL_SDK_VERSION | awk '{split($0,ver,"."); print ver[1]ver[2]}'`

  if [[ -n ${BUILD_UEFI_RELEASE} ]]; then
    UEFI_BIN=./Build/Baikal/RELEASE_GCC6/FV/BAIKAL_EFI.fd
    UEFI_BUILD=RELEASE
  else
    UEFI_BIN=./Build/Baikal/DEBUG_GCC6/FV/BAIKAL_EFI.fd
    UEFI_BUILD=DEBUG
  fi

  [[ -f ${UEFI_BIN} ]] && rm -f ${UEFI_BIN}
  [[ ${SUBTARGET} == "qemu" ]] && UEFI_BUILD="${UEFI_BUILD} -DBE_QEMU_M"

  ARCHTMP=${ARCH}
  unset ARCH

  if [[ -z ${BASETOOLS_SKIP} ]]; then
    make -C BaseTools
    STATUS=$(( $STATUS || $? ))
  fi

  export WORKSPACE= # for Jenkins' workspace to not interfere with UEFI's one
  export EDK_TOOLS_PATH=${UEFI_DIR}/BaseTools
  export GCC6_AARCH64_PREFIX=${CROSS_COMPILE}
  . ./edksetup.sh BaseTools
  STATUS=$(( $STATUS || $? ))

  NUM_CPUS=$((`getconf _NPROCESSORS_ONLN` + 2))
  build -n $NUM_CPUS -p Platform/Baikal/Baikal.dsc -b ${UEFI_BUILD} -DFIRMWARE_VERSION_STRING=$BAIKAL_SDK_VERSION -DFIRMWARE_REVISION=$BAIKAL_SDK_REVISION
  STATUS=$(( $STATUS || $? ))

  if [[ -f ${UEFI_BIN} ]]; then
    stat ${UEFI_BIN}
    cp -f ${UEFI_BIN} ${IMG}/${SUBTARGET}.efi.fd
  fi
  STATUS=$(( $STATUS || $? ))

  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD UEFI"
  export ARCH=${ARCHTMP}
  cd ${TOP}
else
  showinfo "Skip 'BUILD UEFI'"
fi

#-------------------------------------------------------------------------------
# build ARM Trusted Firmware
#-------------------------------------------------------------------------------
if [[ -n ${BUILD_ARMTF} ]]; then
  showinfo "Executing target 'BUILD ARM TF':"

  BAIKAL_SDK_VERSION=`cat ${TOP}/VERSION`
  convert -size 90x20 -pointsize 13 -background black -fill white -gravity center caption:"== SDK ${BAIKAL_SDK_VERSION} ==" ${TOP}/tools/logo.bmp
  xxd -i ${TOP}/tools/logo.bmp ${TOP}/tools/logo.c
  sed -i '$ d' ${TOP}/tools/logo.c
  sed -i 's/unsigned.*/const unsigned char bl31_sdk_version_logo[] = {/' ${TOP}/tools/logo.c
  cp ${TOP}/tools/logo.c ${TOP}/src/arm-tf/plat/baikal/bm1000/bm1000_bl31_sdk_version_logo.c
  rm ${TOP}/tools/logo.bmp ${TOP}/tools/logo.c

  if [[ -n ${BUILD_ARMTF_RELEASE} ]]; then
    ARMTF_BUILD_DIR=build/bm1000/release/
    ARMTF_DEBUG=0
  else
    ARMTF_BUILD_DIR=build/bm1000/debug/
    ARMTF_DEBUG=1
  fi

  UEFI_BIN=${IMG}/${SUBTARGET}.efi.fd
  BL1_BIN=${ARMTF_BUILD_DIR}/bl1.bin
  BL2_BIN=${ARMTF_BUILD_DIR}/bl2.bin
  BL31_BIN=${ARMTF_BUILD_DIR}/bl31.bin
  FIP_BIN=${ARMTF_BUILD_DIR}/fip.bin

  cd ${ARMTF_DIR}

  # Create BL* files and FIP image
  if [ -e build/subtarget ]; then
    OLD_TARGET=`cat build/subtarget`
    if [ x"${SUBTARGET}" != x"${OLD_TARGET}" ]; then
      echo "Error: old target \"${OLD_TARGET}\" != \"${SUBTARGET}\". Clean src/arm-tf/build directory to fix."
      STATUS=1
    fi
  else
    echo ${SUBTARGET} > build/subtarget
  fi
  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD ARM TF"

  case ${SUBTARGET} in
    'mbm10'|'mbm20')
      BE_TARGET="mitx"
      ;;
    *)
      BE_TARGET=${SUBTARGET}
      ;;
  esac

  # all
  make BE_TARGET=${BE_TARGET} PLAT=bm1000 DEBUG=${ARMTF_DEBUG} all
  STATUS=$(( $STATUS || $? ))
  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD ARM TF"

  # fip
  make BE_TARGET=${BE_TARGET} PLAT=bm1000 DEBUG=${ARMTF_DEBUG} BL33=${UEFI_BIN} fip
  STATUS=$(( $STATUS || $? ))
  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD ARM TF"

  cp -f ${FIP_BIN} ${IMG}/${SUBTARGET}.$( basename ${FIP_BIN} )
  cp -f ${BL1_BIN} ${IMG}/${SUBTARGET}.$( basename ${BL1_BIN} )
  echo ${SUBTARGET} > build/subtarget

  cd ${TOP}
else
  showinfo "Skip 'BUILD ARM TF'"
fi

#-------------------------------------------------------------------------------
# build empty images for emulator
#-------------------------------------------------------------------------------
if [[ -n ${BUILD_EMPTIES} ]]; then
  showinfo "Executing target 'BUILD EMPTY IMAGES':"
  PFLASH_IMG_NAME=pflash.img
  PFLASH_IMG_SIZE=32 # Megabytes
  SATA_IMG_NAME1=sata1.img
  SATA_IMG_NAME2=sata2.img
  SATA_IMG_SIZE=128 # Megabytes

  # Create partitioned empty disk image
  if [[ ! -f ${IMG}/${SATA_IMG_NAME1} ]]; then
    dd status=noxfer if=/dev/zero of=${IMG}/${SATA_IMG_NAME1} bs=1M count=${SATA_IMG_SIZE} > /dev/null 2>&1
    STATUS=$(( $STATUS || $? ))
    if [[ $STATUS -ne 0 ]]; then
      echo " Image file (${SATA_IMG_NAME1}) creation failed"
      show_err_and_exit $STATUS "BUILD EMPTY IMAGES"
    fi
    echo " Created empty image file: ${SATA_IMG_NAME1}, ${SATA_IMG_SIZE}M"
    /sbin/mke2fs -q -F -E offset=512 ${IMG}/${SATA_IMG_NAME1} $(( ${SATA_IMG_SIZE} * 1024 - 1 ))
    echo ",2048,0x83,-,,,;" | /sbin/sfdisk -q --no-reread -f ${IMG}/${SATA_IMG_NAME1}
    cat ${IMG}/${SATA_IMG_NAME1} | gzip -9 > ${IMG}/${SATA_IMG_NAME1}.gz
    STATUS=$(( $STATUS || $? ))
    [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD EMPTY IMAGES"
    echo " Created empty disk image: ${SATA_IMG_NAME1}"
  else
    echo " Disk image: ${SATA_IMG_NAME1} already exists: "$( stat -c %s ${IMG}/${SATA_IMG_NAME1} )" bytes"
  fi
  STATUS=$(( $STATUS || $? ))

  # Create SATA disk #2 image (from 1st empty image)
  if [[ ! -f ${IMG}/${SATA_IMG_NAME2} ]]; then
    cp -f ${IMG}/${SATA_IMG_NAME1} ${IMG}/${SATA_IMG_NAME2}
    echo " Created empty disk image: ${SATA_IMG_NAME2}"
  else
    echo " Disk image: ${SATA_IMG_NAME2} already exists: "$( stat -c %s ${IMG}/${SATA_IMG_NAME2} )" bytes"
  fi
  STATUS=$(( $STATUS || $? ))

  # Create pflash zero file
  if [[ ! -f ${IMG}/${PFLASH_IMG_NAME} ]]; then
    dd status=noxfer if=/dev/zero of=${IMG}/${PFLASH_IMG_NAME} bs=1M count=${PFLASH_IMG_SIZE} > /dev/null 2>&1
    STATUS=$(( $STATUS || $? ))
    if [[ $STATUS -ne 0 ]]; then
      echo " Image file (${PFLASH_IMG_NAME}) creation failed"
      show_err_and_exit $STATUS "BUILD EMPTY IMAGES"
    fi
    echo " Created empty pflash image file: ${PFLASH_IMG_NAME}, ${PFLASH_IMG_SIZE}M"
  else
    echo " Pflash image: ${PFLASH_IMG_NAME} already exists: "$( stat -c %s ${IMG}/${PFLASH_IMG_NAME} )" bytes"
  fi
  STATUS=$(( $STATUS || $? ))

  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD EMPTY IMAGES"
  cd ${TOP}
else
  showinfo "Skip 'BUILD EMPTY IMAGES'"
fi

#-------------------------------------------------------------------------------
# build board ROM image
#-------------------------------------------------------------------------------
if [[ -n ${BUILD_BOOTROM} ]]; then
  showinfo "Executing target 'BUILD BOOTROM':"

  # ----------
  # MAP:
  # ----------
  # scp - system control processor image (optional)
  # -----
  # bl1 - armtf.bl1
  # ids - MAC address
  # dtb - device tree blob
  # var - uefi variables
  # fip - armtf.bl2\bl3
  # -----
  # fat - fat32 rescue files (optional)
  # ----------

  # Copy BL* files
  # cp -f ${BL1_BIN} ${IMG}/${SUBTARGET}.$( basename ${BL1_BIN} )
  # cp -f ${BL2_BIN} ${IMG}/${SUBTARGET}.$( basename ${BL2_BIN} )
  # cp -f ${BL31_BIN} ${IMG}/${SUBTARGET}.$( basename ${BL31_BIN} )

  # Make FLASH_IMG: concatenate BL1, board IDs, DTB, FIP_BIN and reserve area for UEFI vars
  FLASH_IMG=${IMG}/${SUBTARGET}.flash.img
  FIP_BIN=${IMG}/${SUBTARGET}.fip.bin

  # size
  SCP_SIZE=$(( 512 * 1024 ))
  if [[ ${SUBTARGET} == 'mbm10' ]] || [[ ${SUBTARGET} == 'mbm20' ]]; then
    FLASH_SIZE=$(( 32 * 1024 * 1024 - $SCP_SIZE))
  else
    FLASH_SIZE=$(( 32 * 1024 * 1024 ))
  fi
  IDS_SIZE=$(( 4  * 1024 ))
  BL1_SIZE=$(( 4  * 64 * 1024 - $IDS_SIZE ))
  DTB_SIZE=$(( 1  * 64 * 1024 ))
  VAR_SIZE=$(( 12 * 64 * 1024 ))
  FAT_OFFSET=$(( 8 * 1024 * 1024 ))
  FAT_SIZE=$(( $FLASH_SIZE - $FAT_OFFSET ))

  # bl1
  cp -f ${IMG}/${SUBTARGET}.bl1.bin ${FLASH_IMG}
  STATUS=$(( $STATUS || $? ))
  truncate --no-create --size=${BL1_SIZE} ${FLASH_IMG}
  STATUS=$(( $STATUS || $? ))

  # ids
  BOARD_IDS_SRC=${IMG}/${SUBTARGET}.board.ids
  if [ ! -f ${BOARD_IDS_SRC} ]; then
    # Generate MAC addresses
    GMAC0_MACADDR=$(( (0x4ca515 << 24) | ((RANDOM % 0xff) << 16) | ((RANDOM & 0xff) << 8) | (RANDOM & 0xfc) ))
    printf "BL1_GMAC0_MACADDR=0x%.12x\n" $(( GMAC0_MACADDR + 0 )) >  ${BOARD_IDS_SRC}
    printf "BL1_GMAC1_MACADDR=0x%.12x\n" $(( GMAC0_MACADDR + 1 )) >> ${BOARD_IDS_SRC}
    printf "BL1_XGBE0_MACADDR=0x%.12x\n" $(( GMAC0_MACADDR + 2 )) >> ${BOARD_IDS_SRC}
    printf "BL1_XGBE1_MACADDR=0x%.12x\n" $(( GMAC0_MACADDR + 3 )) >> ${BOARD_IDS_SRC}
  fi

  source ${BOARD_IDS_SRC}
  echo -n " INFO:  BL1 GMAC0 MAC address: "
  echo ${BL1_GMAC0_MACADDR} | cut -c 3- | sed -e 's/[0-9a-f]\{2\}/&:/g' -e 's/:$//'
  echo -n " INFO:  BL1 GMAC1 MAC address: "
  echo ${BL1_GMAC1_MACADDR} | cut -c 3- | sed -e 's/[0-9a-f]\{2\}/&:/g' -e 's/:$//'

  BOARD_IDS_BIN=${IMG}/${SUBTARGET}.board.ids.bin
  printf "0:%.12x" $BL1_GMAC0_MACADDR | xxd -groupsize4 -revert >  ${BOARD_IDS_BIN}
  printf "0:%.12x" $BL1_GMAC1_MACADDR | xxd -groupsize4 -revert >> ${BOARD_IDS_BIN}
  printf "0:%.12x" $BL1_XGBE0_MACADDR | xxd -groupsize4 -revert >> ${BOARD_IDS_BIN}
  printf "0:%.12x" $BL1_XGBE1_MACADDR | xxd -groupsize4 -revert >> ${BOARD_IDS_BIN}
  printf "0:%.8x" "0x$(crc32 <(cat ${BOARD_IDS_BIN}))" | \
    sed -E 's/0:(..)(..)(..)(..)/0:\4\3\2\1/' | xxd -groupsize4 -revert >> ${BOARD_IDS_BIN}

  cat ${BOARD_IDS_BIN} >> ${FLASH_IMG}
  STATUS=$(( $STATUS || $? ))
  rm ${BOARD_IDS_BIN}
  truncate --no-create --size=$(($BL1_SIZE + $IDS_SIZE)) ${FLASH_IMG}
  STATUS=$(( $STATUS || $? ))

  # dtb
  cat ${IMG}/${SUBTARGET}.dtb >> ${FLASH_IMG}
  STATUS=$(( $STATUS || $? ))
  truncate --no-create --size=$(($BL1_SIZE + $IDS_SIZE + $DTB_SIZE)) ${FLASH_IMG}
  STATUS=$(( $STATUS || $? ))

  # var
  truncate --no-create --size=$(($BL1_SIZE + $IDS_SIZE + $DTB_SIZE + $VAR_SIZE)) ${FLASH_IMG}
  STATUS=$(( $STATUS || $? ))

  # fip
  cat ${FIP_BIN} >> ${FLASH_IMG}
  STATUS=$(( $STATUS || $? ))

  # Pad flash image to make it FLASH_SIZE bytes, then copy it to IMG
  if [[ -n ${BOOTROM_TRUNCATE} ]]; then
    echo "Truncate flash: ${FLASH_SIZE}"
    truncate --no-create --size=${FLASH_SIZE} ${FLASH_IMG}
    STATUS=$(( $STATUS || $? ))
  fi
  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD BOOTROM"

  # fat
  if [[ -n ${BOOTROM_LINUX} ]]; then
    echo "Update flash with Linux"
    FAT_IMG=${IMG}/${SUBTARGET}.fat.img
    if [[ ! -e ${IMG}/tmp ]]; then
      mkdir ${IMG}/tmp
    fi
    if [[ ! -e /usr/bin/mcopy ]]; then
      echo "Install mtools pkg!"
      STATUS=1
    fi
    STATUS=$(( $STATUS || $? ))
    dd if=/dev/zero of=${FAT_IMG} count=$(( $FAT_SIZE / 1024 )) bs=1024
    STATUS=$(( $STATUS || $? ))

    mkfs.fat ${FAT_IMG}
    STATUS=$(( $STATUS || $? ))

    cd ${IMG}
    mcopy -i ${FAT_IMG} ${SUBTARGET}.Image ::
    STATUS=$(( $STATUS || $? ))
    mcopy -i ${FAT_IMG} initrd.gz ::
    STATUS=$(( $STATUS || $? ))
    mcopy -i ${FAT_IMG} ${SUBTARGET}.dtb ::
    STATUS=$(( $STATUS || $? ))

    RAMDISK_SIZE=65536

    echo "${SUBTARGET}.Image root=/dev/ram rw console=ttyS0,115200n8 initrd=initrd.gz ramdisk_size=${RAMDISK_SIZE} earlyprintk=uart8250-32bit,0x20230000 initcall_debug ignore_loglevel maxcpus=%1 %2 %3 %4 %5 %6" > startup.nsh

    mcopy -i ${FAT_IMG} startup.nsh ::
    rm startup.nsh
    mdir -i ${FAT_IMG} ::
    dd if=${FAT_IMG} of=${FLASH_IMG} seek=$(( $FAT_OFFSET / 1024 )) bs=1024 conv=notrunc
    STATUS=$(( $STATUS || $? ))
  fi  # BOOTROM_LINUX
  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD BOOTROM"

  # SCP_IMG
  [[ -f ${TOP}/prebuilts/mitx.scp.flash.bin    ]] && SCP_IMG=${TOP}/prebuilts/mitx.scp.flash.bin
  [[ -f ${TOP}/scp_firmware/mitx.scp.flash.bin ]] && SCP_IMG=${TOP}/scp_firmware/mitx.scp.flash.bin
  [[ -z $SCP_IMG ]] && show_err_and_exit $STATUS "BUILD BOOTROM"

  if [[ -n ${SINGLE_IMG} ]]; then
    cat ${SCP_IMG} >                      ${IMG}/${SUBTARGET}.full.img
    truncate --no-create --size=$SCP_SIZE ${IMG}/${SUBTARGET}.full.img
    cat ${FLASH_IMG} >>                   ${IMG}/${SUBTARGET}.full.img
    STATUS=$(( $STATUS || $? ))
  fi

  [[ $STATUS -ne 0 ]] && show_err_and_exit $STATUS "BUILD BOOTROM"
  cd ${TOP}
else
  showinfo "Skip 'BUILD BOOTROM'"
fi

# Show final status
showinfo "Build process is done"
banner $STATUS "ALL"
exit $STATUS
