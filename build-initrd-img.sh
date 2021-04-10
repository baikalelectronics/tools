#!/bin/bash
#
# Baikal-M SDK helper functions
#
# Create initrd filesystem image for Baikal-M SoC
#
# (C) 2017-2018 Baikal Electronics JSC.
# All right reserved.
#
# Dependencies: bash coreutils genext2fs
# ------------------------------------------------------------

#----------------------------------
# Info
#----------------------------------
echo
echo " === Script for creating a filesystem image for Baikal-M SoC ==="
echo

#----------------------------------
# Include environment & functions
#----------------------------------
SCRIPTSDIR=`dirname $( readlink -f $0 )`
[[ -e ${SCRIPTSDIR}/environment.sh ]] && source ${SCRIPTSDIR}/environment.sh || exit 2

#----------------------------------
# Usage
#----------------------------------
show_help()
{
 cat << EOF

 Usage: $( basename $0 ) [platform] [options] [-p | --packages list]

 platform - optional platform to build

 Supported platforms:
    baikal    - Baikal-M platform (default)

 Options:
    -c, --clean     - cleanup operation only (skip build & image create)
    -s, --skipbuild - skip build, create image from existing build directory
    -m, --modules   - build & install kernel modules
    -d, --default   - build & install default packages
    -p, --packages  - specify extra packages as a list on the command line
    -l, --list      - list available packages & exit
EOF
}

#----------------------------------
# Build filesystem from .spec files
#----------------------------------
build_root_fs()
{
 local SRC_DIR=$1
 local DEST_DIR=$2
 local SPEC_FILE=${SRC_DIR}/files.spec
 local FILE

 if [[ ! -d ${SRC_DIR} ]]; then
     echo "Source directory ${SRC_DIR} doesn't exists"
     return 1
 fi

 if [[ ! -d ${DEST_DIR} ]]; then
     echo "Destination directory ${DEST_DIR} doesn't exists"
     return 2
 fi

 if [[ ! -f ${SPEC_FILE} ]]; then
     echo "Specification file ${SPEC_FILE} doesn't exists"
     return 3
 fi

 echo -n "Creating filesystem on specification..."
 while read MODE LNAME TYPE PARAM1 PARAM2
 do
 ( echo ${MODE} | grep "^[[:space:]]*$" > /dev/null ) && continue
 ( echo ${MODE} | grep "^#" > /dev/null ) && continue
 NAME=${DEST_DIR}${LNAME}
 DNAME=$( echo ${NAME} | sed s%"${TOP}"%{SDK_ROOT}% )
 case ${TYPE} in
 f)
   if [[ -z "${PARAM1}" ]]; then
       FILE=${SRC_DIR}${LNAME}
   else
       FILE=${SRC_DIR}${PARAM1}
   fi
   echo -n "Create file ${DNAME} ... "
   cp -af ${FILE} ${NAME}
   ;;
 d)
   echo -n "Create directory ${DNAME} ... "
   mkdir -p ${NAME}
   ;;
 l)
   echo -n "Create link ${DNAME} ... "
   ln -sf ${PARAM1} ${NAME}
   ;;
 b)
   mknod ${NAME} b ${PARAM1} ${PARAM2}
   echo -n "Create block dev ${DNAME} ... "
   ;;
 c)
   mknod ${NAME} c ${PARAM1} ${PARAM2}
   echo -n "Create char dev ${DNAME} ... "
   ;;
 p)
   echo -n "Create named pipe ${DNAME} ... "
   mkfifo ${NAME}
   ;;
 *)
   echo "Unknown type ${TYPE}"
   continue
   ;;
 esac
 if [[ $? != 0 ]]; then
     echo "Failed"
     continue
 fi
 chmod ${MODE} ${NAME}
 echo "Done"
 done < ${SPEC_FILE}

 return 0
}

#----------------------------------
# Prepare build information
#----------------------------------
build_image_info()
{
 local FILE
 FILE=$1

 BUILD_COMMIT='-'
 BUILD_BRANCH='-'
 DEVELOPER=
 git log -n1 > /dev/null 2>&1
 if [[ $? -eq 0 ]]; then
     BUILD_COMMIT=`git rev-parse HEAD`
     BUILD_BRANCH=`git rev-parse --abbrev-ref HEAD`
     DEVELOPER="dev"
 fi

 BUILD_HOST=`hostname`
 BUILD_USER=`whoami`
 if [[ -n "${SUDO_USER}" ]]; then
     BUILD_USER=${BUILD_USER}"("${SUDO_USER}")"
 fi
 if [[ -z "${BUILDER}" ]]; then
     BUILDER="${BUILD_USER}@${BUILD_HOST}"
 fi

 BUILD_DATE=`LC_ALL=C date +%Y.%m.%d-%H:%M:%S`
 BEL_REV="r.$( LC_ALL=C date +%Y.%m )-B-M-${SDK_VERSION}${DEVELOPER}"

 if [[ -z "${BUILD_TAG}" ]]; then
     BUILD_TAG="-local"
 fi

 BUILD_NUM='-'
 if [[ -f "${TOP}/.build" ]]; then
     BUILD_NUM=`cat ${TOP}/.build`
 fi

 BUILD_KNUM='-'
 if [[ -f "${KERNELDIR}/.version" ]]; then
     BUILD_KNUM=`cat ${KERNELDIR}/.version`
 fi

 # Create build info
 BELKA="H4sIAIKifVoCA41UO47rMAzsfYocQIVq6ggCqJLqpU4C1PL4b/SxY22cfUsgQBJ6zOFwyNfrHtLj9Zc43pgYSm49sgYf5W9A8VpTqk21qOaWKOXA8l+g+EzUgj8flWi1Ui3+F2wHciHKfn9GYqmOmpdfgKyUAn9kxDdy9SvyeEkgKo9pX5rL8SuQs2lnVtgWexUX9JDsmtInMDaT+ZKWUnkDxSYK8hKLMeWys+4V3agoUROkvQkpMiuCU2qNSONHj3gtB8DsplEMbbxzNIO8a8VexhiquhS83knOgWSoamUCGQUaPJKqTspjjkqUXLL3HoRDdRMnqKU8qLMPJ+XpnJBMCrfm2JcuE4hxyHt3bOvgP73q63znMnsGqoXRDpesu56Q2qmsiue8xkgSVbXxpwPf/8zBDyDkqX7+WS5txWNRSpiAbkv8CKWUoMnUE5j715U/tcXKNOgI0qAKEyVjqK7AM4uqG1RBmcLWT5epoViEiypEZuZ1JKY46Lf7HBrlzzXpOmJLBNmqqlO0BewesN2a7mlPJA4HDcviOIzhnqejp/w3YHely8HagMhrCa+b09CBn9582MxkKK2oU73rykX4TvuHHytSiSP43J7jpgG8Rcblj2sBQQ38t5+uY/N1I2NMUr9XZZgJHKneR3X8OFCYmsOgFY4BLZ78vEWUapa9HoDT45phmEuMK/ZbeDyJKBy9n+rfYjf+8Q9PLTUEdQYAAA=="
 if [[ -n "${FILE}" ]]; then
     cat << EOF > ${FILE}

 $( echo ${BELKA} | base64 -d | gzip -d )

 ===    Baikal Embedded Linux (BEL)    ===
 Revision: ${BEL_REV}
 Baikal Electronics JSC, 2018


 Baikal-M SDK Version: ${SDK_VERSION}

 Build date:     ${BUILD_DATE}
 Build tag:      ${BUILD_TAG}
 SDK build num:  ${BUILD_NUM}
 SDK top commit: ${BUILD_COMMIT}
 SDK top branch: ${BUILD_BRANCH}
 Builder info:   ${BUILDER}

EOF
 fi

 return 0
}


#----------------------------------
# Main part
#----------------------------------
if [[ ${UID} == '0' && -n ${SUDO_UID} ]]; then
    echo " WARNING: This script has no need to be run under root user!"
fi

if [[ -z $@ ]]; then
    echo " No options supplied, build default platform & configuration"
fi

if [[ -n "$1" ]]; then
    echo "$1" | grep -q -E "^-+[a-z_]+$"
    if [[ $? -ne 0 ]]; then
        # $1 - is not an option, treat as a "platform" 
        echo "$1" | grep -q -E "^[a-zA-Z]+[a-zA-Z0-9_-]+"
        if [[ $? -ne 0 ]]; then
            showerror "Platform parameter seems to be invalid: '$1'"
            show_help
            exit 1
        fi
        PLATFORM="$1"
        echo " Specified platform name on the command line: '${PLATFORM}'"
        shift
    fi
fi

# Build modes:
CLEANUP=     # <--- make clean & exit (no image created)
SKIPBUILD=   # <--- do not build packages or copy (or alter) any files,
             #      only create image using $BUILDDIR as a source

# Include kernel modules:
KERNELMODULES=

# Include packages ('busybox' is always included)
PACKAGES="busybox"

# Default packages:
# busybox, i2ctools, lmsensors, ethtool, dropbear, kexec-tools, pciutils
DEF_PKG="busybox i2ctools lmsensors ethtool dropbear kexec-tools pciutils"

# Available packages:
# e2fsprogs (e2fsck), fbtest, spitools, strace

# Additional (user defined) packages can be added as a list of package
# names to the EXTRA_PKG variable, for example:
# EXTRA_PKG="xutils xxxtools"
# You need to add package source files to
# {SDK_ROOT}/baikal/src/initrd/programs/ directory
# and create appropriate makefiles for them. For example,
# if you need packages 'xutils' and 'xxxtools', add the following to
# {SDK_ROOT}/baikal/src/initrd/programs :
# Directory "xutils" and makefile "xutils.mk",
# Directory "xxxtools" and makefile "xxxtools.mk",
EXTRA_PKG=

# You can also specify packages on the command line after the
# '-p' or '--packages' option, for example:
# ./build-initrd-img.sh -p procps strace


#----------------------------------
# Process command line parameters
#----------------------------------
PKG_LIST_CMD=
for param in $@
do
    firstchar=`echo ${param} | cut -c1`
    if [[ ${PKG_LIST_CMD} -eq 1 ]]; then
        # The remaining part of the command contains only package list
        echo "${param}" | grep -q -E "^[a-zA-Z]+[a-zA-Z0-9_.-]+"
        if [[ $? -ne 0 ]]; then
            showerror "'${param}' - invalid package name or invalid place for an option"
            show_help
            exit 1
        fi
        echo " Requested to add the package '${param}'"
        PACKAGES="${PACKAGES} ${param}"
        continue
    fi

    if [[ "${firstchar}" != '-' ]]; then
        # Non-option parameter, error
        showerror "Invalid parameter: '${param}'"
        show_help
        exit 1
    fi

    case ${param} in
    '-c'|'--clean')
      CLEANUP=1 && echo " Requested cleanup operation"
    ;;
    '-s'|'--skipbuild')
      SKIPBUILD=1 && echo " Requested create-image-only mode"
    ;;
    '-m'|'--modules')
      KERNELMODULES=1 && echo " Requested to build kernel modules"
    ;;
    '-p'|'--packages')
      PKG_LIST_CMD=1 && echo " Get package list from command line"
    ;;
    '-d'|'--default')
      echo " Requested to include default set of packages"
      PACKAGES=${DEF_PKG}
    ;;
    '-l'|'--list')
      LIST_PACKAGES=1
    ;;
    '-?'|'-h'|'--h'|'-help'|'--help'|'help')
      show_help
      exit 0
    ;;
    *)
      showerror "Unknown option '${param}'"
      show_help
      exit 1
    ;;
    esac
done

# Include extra packages to the build:
[[ -n ${EXTRA_PKG} ]] && PACKAGES="${PACKAGES} ${EXTRA_PKG}"


#----------------------------------
# Set toolchain & build parameters
#----------------------------------

# Build result (initrd image)
INITRD=${IMG}/initrd.gz

# Temporary build directorites
BUILDDIR=${BUILDS}/initrd
ROOTFS=${BUILDDIR}/rootfs
FROMXTOOLS=${BUILDDIR}/xfiles

# Static files & directories (prebuilt files, scripts, configs, etc.)
SKELETION=${SRC}/initrd/static/skeletion
PLATFORMFILES=${SRC}/initrd/static/${PLATFORM}

# Source file directories
PROGRAMS=${SRC}/initrd/programs
if [[ -n "${LIST_PACKAGES}" ]]; then
    echo " Packages that will be included with the current command: "
    for pkg in ${PACKAGES}; do
        echo "   + ${pkg}"
    done
    echo " All available packages: "
    for pkg in `find "${PROGRAMS}" -maxdepth 1 -name "*.mk" | sort`; do
        p=`basename -s .mk "${pkg}"`
        [[ -d "${PROGRAMS}"/"${p}" ]] && echo "   * ${p}"
        [[ -d "${PROGRAMS}"/benchmarks/"${p}" ]] && echo "   * ${p}"
    done
    exit 0
fi
if [[ -n "${KERNELMODULES}" ]]; then
    [[ -n ${KERNEL} ]] || KERNEL=${SRC}/kernel
    [[ -n ${MODULES} ]] || MODULES=${BUILDS}/kernel/modules
fi

# Image parameters
IMAGE=${BUILDDIR}/${PLATFORM}.img
# WARNING! Image size must be in consistency with dts inird_start/initrd_end
# nodes, and either CONFIG_BLK_DEV_RAM_SIZE kernel configuration parameter or
# ramdisk_size kernel boot argument. Additionally there must be enough flash
# memory to hold the gziped image, so file src/bootrom/<target>.map must be
# correspondingly altered.
IMGSIZEMEGS=64
IMGSIZEKBYTES=$(( 9 * $IMGSIZEMEGS * 1024 / 10))
IMAGEINFO=${ROOTFS}/.build

# Toolchain settings
TRIPLET=`basename $CROSS_COMPILE | sed s/-$//`
# Toolchain top dir:
TOOLCHAIN=`readlink -f $( dirname $CROSS_COMPILE )/../../`
# Prebuilt programs & libs from toolchain:
TOOLCHAIN_SYSROOT=$TOOLCHAIN/$TRIPLET/$TRIPLET/sysroot

# Toolchain libraries to be installed in rootfs
LIBATOMIC="libatomic.so libatomic.so.1 libatomic.so.1.2.0"
LIBGOMP="libgomp.so libgomp.so.1 libgomp.so.1.0.0"
GLIBC_NSS="libnss_compat-*.so libnss_compat.so.2 libnss_db-*.so libnss_db.so.2
    libnss_dns-*.so libnss_dns.so.2 libnss_files-*.so libnss_files.so.2
    libnss_hesiod-*.so libnss_hesiod.so.2"
GLIBC_MIN="ld-*.so ld-linux-aarch64.so.1 libc-*.so libc.so.6 libdl-*.so libdl.so.2
    libpthread-*.so libpthread.so.0 libutil-*.so libutil.so.1"
GLIBC_MID=${GLIBC_MIN}" libanl-*.so libanl.so.1 libcrypt-*.so libcrypt.so.1
    libm-*.so libm.so.6 libmemusage.so libnsl-*.so libnsl.so.1
    libresolv-*.so libresolv.so.2 librt-*.so librt.so.1"
GLIBC_MAX=${GLIBC_MID}" "${GLIBC_NSS}" libBrokenLocale-*.so libBrokenLocale.so.1
    libpcprofile.so libSegFault.so libgcc_s.so.1"
# C++ runtime libraries (~1300 k)
LIBSTDCXX="libstdc++.so libstdc++.so.6 libstdc++.so.6.0.28"
# Full set of libs (~4300 k)
TOOLCHAIN_LIBS_MAX=${LIBSTDCXX}" "${GLIBC_MAX}" "${LIBATOMIC}" "${LIBGOMP}
LIBSIZE_MAX=4300
# Reduced set of libs (~2700 k)
LIBSIZE_MID=2700
TOOLCHAIN_LIBS_MID=${GLIBC_MID}" "${LIBATOMIC}" "${LIBGOMP}
# Minimum set of libs (~1600 k)
TOOLCHAIN_LIBS_MIN=${GLIBC_MIN}

TOOLCHAIN_LIBS=${TOOLCHAIN_LIBS_MAX}

#----------------------------------
# Check settings & directory existence
#----------------------------------
 
header "Check settings & directory existence"
action "Check platform" test -n ${PLATFORM}
action "Check 'ARCH'" test -n ${ARCH}
action "Check 'CROSS_COMPILE'" test -n ${CROSS_COMPILE}
action "Check Toolchain directory" test -d ${TOOLCHAIN}
action "Check Toolchain bin directory" test -d ${TOOLCHAIN}/${TRIPLET}/bin
action "Check Toolchain sysroot directory" test -d ${TOOLCHAIN_SYSROOT}
action "Check Programs directory" test -d ${PROGRAMS}
action "Check platform files directory" test -d ${PLATFORMFILES}

if [[ -z ${CLEANUP} ]]; then
    if [[ -n ${SKIPBUILD} ]]; then
        action "Check build top directory" test -d ${BUILDDIR}
        action "Check build rootfs directory" test -d ${ROOTFS}
        action "Check build xfiles directory" test -d ${FROMXTOOLS}
    fi
fi

if [[ -n ${KERNELMODULES} ]]; then
    action "Check kernel source directory" test -d ${KERNEL}
    action "Check kernel modules directory" test -d ${MODULES}
fi


#----------------------------------
# Show target information
#----------------------------------

header "Show target information"
showinfo "Toolchain: '$TRIPLET'"
showinfo "Toolchain dir: '$( echo ${TOOLCHAIN} | sed s%"${TOP}"%{SDK_ROOT}% )'"
showinfo "Platform name: '$PLATFORM'"
echo " Build options summary:"
if [[ -z ${CLEANUP} ]]; then
    echo "  * Rootfs filesystem size: ${IMGSIZEMEGS} M"
    if [[ -z ${SKIPBUILD} ]]; then
        [[ -n ${KERNELMODULES} ]] && echo "  * Install kernel modules"
        if [[ -n ${PACKAGES} ]]; then
            echo "  * Include packages in rootfs:"
            for pkg in ${PACKAGES}; do
                echo "    + ${pkg}"
            done
        fi
    else
        echo "  * SKIP-BUILD mode is on"
    fi
else
    echo "  * CLEANUP: perform cleanup & exit"
fi


#----------------------------------
# Create image
#----------------------------------

header "Perform requested actions"

# Cleanup & exit:
if [[ -n ${CLEANUP} ]]; then
    action "make clean for programs directory" ${MAKE} -C ${PROGRAMS} clean
    [[ -d ${BUILDDIR} ]] && action "Remove temporary build directory" rm -rf ${BUILDDIR}
    header "Cleanup completed"
    exit 0
fi

# Build filesystem & install programs:
if [[ -z ${SKIPBUILD} ]]
then
    header "Build filesystem & install programs"

    # Create build directories
    action "Create directory for built images" mkdir -p ${IMG}
    [[ -d ${ROOTFS} ]] && action "Cleanup previous rootfs build" rm -rf ${ROOTFS}
    action "Create temporary rootfs build directory" mkdir -p ${ROOTFS}
    action "Create temporary xfiles build directory" mkdir -p ${FROMXTOOLS}

    # Create rootfs filesystem & static files
    action "Build skeletion filesystem" build_root_fs ${SKELETION} ${ROOTFS}
    action "Build platform '${PLATFORM}' filesystem" build_root_fs ${PLATFORMFILES} ${ROOTFS}
    MOTD_DATE=$( date +%Y.%m )
    MOTD_SDK=$( echo ${SDK_VERSION} | cut -c1-5 )
    [[ $( echo ${SDK_VERSION} | wc -c ) -eq 5 ]] && MOTD_SDK=${MOTD_SDK}" "
    sed -i 's/'"YYYY.MM"'/'"${MOTD_DATE}"'/' ${ROOTFS}/etc/motd
    sed -i 's/'"XXXXX"'/'"${MOTD_SDK}"'/' ${ROOTFS}/etc/motd

    # Build packages
    action "Build Programs"  ${MAKE} -C ${PROGRAMS} PREFIX=${ROOTFS}
    for p in ${PACKAGES}; do
        action "Build ${p}"  ${MAKE} -C ${PROGRAMS} -f ${p}.mk PREFIX=${ROOTFS}
    done

    # Install packages
    action "Install Programs"  ${MAKE} -C ${PROGRAMS} install PREFIX=${ROOTFS}
    for p in ${PACKAGES}; do
        action "Install ${p}"  ${MAKE} -C ${PROGRAMS} -f ${p}.mk install PREFIX=${ROOTFS}
    done

    # Build & install kernel modules
    if [[ -n ${KERNELMODULES} ]]; then
        MODULES_BUILD_OPTIONS=''
        # Example (to set specific version): MODULES_BUILD_OPTIONS='LOCALVERSION=-xxx'
        action "Make kernel modules" ${MAKE} -C ${KERNEL} ${MODULES_BUILD_OPTIONS} modules
        action "Install kernel modules" ${MAKE} -C ${KERNEL} modules_install INSTALL_MOD_PATH=${ROOTFS}
        find ${ROOTFS}/lib/modules -type l -print | xargs rm -f
    fi
else
    echo " Skip 'build filesystem & install programs' stage"
fi

# Copy files from toolchain:
if [[ -z ${SKIPBUILD} && -d ${TOOLCHAIN_SYSROOT} ]]
then
    header "Copy files from toolchain"

    # Copy executables (ldd, ldconfig for now):
    action "Copy ldconfig" cp -af ${TOOLCHAIN_SYSROOT}/sbin/ldconfig ${ROOTFS}/sbin/
    cat ${TOOLCHAIN_SYSROOT}/usr/bin/ldd | sed s/"^#! \/bin\/bash"/"#\!\/bin\/sh"/ > ${ROOTFS}/sbin/ldd
    chmod +x ${ROOTFS}/sbin/ldd
    action "Copy ldd" test $? == 0

    # Choose predefined set of libraries (by size):
    BUILD_SIZE=`du -ks ${ROOTFS} | cut -f1`
    if [[ $(( ${BUILD_SIZE} + ${LIBSIZE_MAX} )) -lt ${IMGSIZEKBYTES} ]]; then
        TOOLCHAIN_LIBS=${TOOLCHAIN_LIBS_MAX} && echo " Use full library set"
    else
        if [[ $(( ${BUILD_SIZE} + ${LIBSIZE_MID} )) -lt ${IMGSIZEKBYTES} ]]; then
            TOOLCHAIN_LIBS=${TOOLCHAIN_LIBS_MID} && echo " Use reduced library set"
        else
            echo " Use minimum library set"
        fi
    fi
    mkdir -p ${FROMXTOOLS}/lib
    for lib in ${TOOLCHAIN_LIBS}; do
        cp -af ${TOOLCHAIN_SYSROOT}/lib/${lib} ${FROMXTOOLS}/lib/
        RC=$?
        [[ ${RC} != '0' ]] && break
    done
    action "Prepare toolchain libs" test \"${RC}\" == \"0\"

    # ! TODO: Must be moved to Makefiles !
    # ! TODO: Check: ARM64 strip options !
    find ${FROMXTOOLS} -type f -print | xargs file | grep "not stripped" | \
        cut -d':' -f1 | xargs ${CROSS_COMPILE}strip

    # Debug info:
    echo " Use $( find ${FROMXTOOLS} -type f -print | xargs file | grep "shared object" | wc -l ) toolchain libs"
    echo " Toolchain libraries size: $( du -ks ${FROMXTOOLS}/lib | cut -f1 )k"

    # Copy predefined set of libraries
    if [[ ${ONLY_REQ_LIBS} -ne 1 ]]; then
      action "Copy files from toolchain" cp -af ${FROMXTOOLS}/* ${ROOTFS}
    fi

    # Copy only required libraries
    if [[ ${ONLY_REQ_LIBS} -eq 1 ]]; then
      echo " Copy only required libraries:"
      XLIBS=$( 
        for p in $( find ${ROOTFS} -type f -print | xargs file | grep "executable, ARM" | cut -d':' -f1 ); do
          ${CROSS_COMPILE}ldd --root ${TOOLCHAIN_SYSROOT}/lib $p | sed s/^[[:space:]]*// | cut -d' ' -f1
        done )
      for lib in $( echo ${XLIBS} | sed s/'[[:space:]][[:space:]]*'/'\n'/g | sort | uniq ); do
        L="${TOOLCHAIN_SYSROOT}/lib/${lib}"
        if [[ -f "$( readlink -f ${L} )" ]]; then
            cp -af ${L} ${ROOTFS}/lib/
            echo "   Copy: ${lib} - > {ROOTFS}/lib/"
            while [ -h "${L}" ]; do
                L=`readlink ${L}`
                cp -af ${TOOLCHAIN_SYSROOT}/lib/${L} ${ROOTFS}/lib/
                echo "   Copy: ${L} - > {ROOTFS}/lib/"
            done
        fi
      done
    fi

    # Strip & cleanup installation
    [[ -d "${ROOTFS}/lib" ]] && \
        find ${ROOTFS}/lib -type f -name "*.a" -print | xargs rm -f
    find ${ROOTFS} -type f ! -path "${ROOTFS}/lib/modules/*" -print | xargs file | grep "not stripped" | \
        cut -d':' -f1 | xargs ${CROSS_COMPILE}strip

    # Debug info:
    echo " Rootfs /lib size: $( du -ks ${ROOTFS}/lib | cut -f1 )k"
    echo " Rootfs has $( find ${ROOTFS} -type f -print | xargs file | grep "shared object" | wc -l ) shared libs"
    echo " Rootfs has $( find ${ROOTFS} -type f -print | xargs file | grep "executable, ARM aarch64" | wc -l ) executables"
else
    echo " Skip 'copy files from toolchain' stage"
fi

# Final actions
header "Finalization"
# WARNING: command fixed for old version of dd, for new dd do:
# "dd status=none if=/dev/urandom of=${ROOTFS}/etc/random-seed bs=512 count=1"
action "Update random seed file" dd status=noxfer if=/dev/urandom of=${ROOTFS}/etc/random-seed bs=512 count=1 > /dev/null 2>&1
action "Write image info" build_image_info ${IMAGEINFO}

[[ -f ${INITRD} ]] && action "Remove old images" rm -f ${INITRD}
[[ -f ${IMAGE} ]] && action "Remove temporary image" rm -f ${IMAGE}
action "ROOTFS synchronization" sync

# Create image with ext2 filesystem using 'genext2fs' utility
# genext2fs info:   http://genext2fs.sourceforge.net/
echo " Create filesystem image with genext2fs:"
BLOCKSIZE=$(( ${IMGSIZEMEGS} * 1024 ))
${BIN}/genext2fs -b ${BLOCKSIZE} -N 4096 -U -d ${ROOTFS} -D ${SKELETION}/dev.spec ${IMAGE}
RC=$?
action "Create image" test \"${RC}\" == \"0\"
action "Check image" test -f ${IMAGE}
echo " View created image:"
echo "   $( echo ${IMAGE} | sed s%"${TOP}"%{SDK_ROOT}% )"
echo "   Created: "$( date +"%Y-%m-%d %H:%M:%S" -d "$( stat -c %z ${IMAGE} )" )
echo "   Size: "$( stat -c %s ${IMAGE} )
action "Compress image" $( cat ${IMAGE} | gzip -9 > ${INITRD} )

# Done
header 'Initrd build completed'
echo
echo " View compressed image info:" 
echo "   $( echo ${INITRD} | sed s%"${TOP}"%{SDK_ROOT}% )"
echo "   Created: "$( date +"%Y-%m-%d %H:%M:%S" -d "$( stat -c %z ${INITRD} )" )
echo "   Size: "$( stat -c %s ${INITRD} )
echo "   MD5: "$( md5sum ${INITRD} | cut -d' ' -f1 )
echo

# End of build-initrd-img.sh
