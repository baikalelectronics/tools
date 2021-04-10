#!/bin/bash
#
# Baikal-M SDK helper functions
#
# Setup build environment
#
# (C) 2017-2018 Baikal Electronics JSC.
# All right reserved.
#
# Dependencies: bash coreutils
# ------------------------------------------------------------

# SDK root directory
TOP=`readlink -f $( dirname $( readlink -f $0 ) )/..`

# Prebuilt host (x86) utilities
BIN=${TOP}/utils

# SDK source directories
SRC=${TOP}/src

# Build results (firmware, images, ...)
IMG=${TOP}/img

# Temporary build directory
BUILDS=${TOP}/_build

# Platform name
PLATFORM='baikal'

# SDK Version
SDK_VERSION='-'
if [[ -f "${TOP}/VERSION" ]]; then
    SDK_VERSION=`cat ${TOP}/VERSION`
    git log -n1 > /dev/null 2>&1 && SDK_VERSION="${SDK_VERSION}+"
fi

# Enable parallel builds for multicore CPUs
MAKE="make"
CPU_THREADS=`cat /proc/cpuinfo | grep processor | wc --lines`
if [[ "${CPU_THREADS}" -gt 1 ]]; then
    MAKE="make -j${CPU_THREADS}"
fi

# Export architecture and crosstools
if [[ -z "${ARCH}" ]]; then
    export ARCH=arm64
fi

if [[ -z "${CROSS_COMPILE}" ]]; then
    export CROSS_COMPILE=${TOP}/xtools/aarch64-unknown-linux-gnu/bin/aarch64-unknown-linux-gnu-
fi

# Add local utils to $PATH
export PATH=${BIN}:$PATH

# Helper message functions

showinfo()
{
  echo " INFO: " $@
}

showerror()
{
  echo " ERROR: " $@
}

showwarn()
{
  echo " WARN: " $@
}

header() {
  local STRING

  STRING=$1
  echo
  echo " === ${STRING} ==="
  return 0
}

success() {
  echo "    ОК"
  return 0
}

failure() {
  local rc
  rc=$?
  echo "    ERROR"
  exit 10
}

# Gzipped & base64 coded "success" and "error" banners
E0="H4sIABi3gloCA1NWBgEFCAmjFJB5XCABkBiEwEZxIWlDmAJTgmGKMgoFNQWkBOoWFBsUkA3jAgCw5zlwrwAAAA=="
E1="H4sIAEemgVoCA3WMywkAMAhD706Ro+5U6CIZvvEDnhqE5wsibgb4w1hLEFktIHCsbwIC4AvPrs1Y30LQnIXCMXuSIv25jgAAAA=="
E2="H4sIAE6mgVoCA1OIj49XACJkzBUNJIBYE4RrFBRqQDRIMB7IiQFjIBNEcwEA4cNcjT8AAAA="
E3="H4sIAFWmgVoCA0XLsQ0AIAhE0Z4pfqkVC5HcIgwvnoXNywcCkuDzjR57oAxp3ffWk5CGvbTXW0Tr/qlVhpo5cccBqFKsgm8AAAA="
S0="H4sIACi3gloCA1NQBgIFBSACExAelFJWRtAwQS6wSrgGLJQCKsWlgGIDmhKIyag2KOA0Gq4dxQwuVFcT4QcAGorT0/UAAAA="
S1="H4sIAGumgVoCA3WNMQ4AIAgDd17RUSc+ZOJHeLy0YoyDIjka2oDJB+RnH/WFuYYeUAVjVAfc+QMbSo90z51oqS/SgrIUrOmUhxAb/UVZCrYANuBqvccAAAA="
S2="H4sIAHKmgVoCA1OIj1cAAxANwfFQmksDSNcoKNToKygkgHA0kK8BwVxAec2a+PiaGCAfhKMh+jRBmAsA0eq1tVUAAAA="
S3="H4sIAHmmgVoCA2WMMQ4AIAgDd17RUSc+ZMJH+nhL1clALwUaUFWAunX8h0iRhMv+Lp4zYim+lChpDg2GUoRPRlAPsxeXNPiQ2YgNNsrZbZcAAAA="
RET_OK=${S0}
RET_ER=${E0}
B=0
[[ -f "${TOP}/.build" ]] && B=$(( $( cat ${TOP}/.build ) % 4 ))
case ${B} in
  1) RET_OK=${S1} ; RET_ER=${E1} ;;
  2) RET_OK=${S2} ; RET_ER=${E2} ;;
  3) RET_OK=${S3} ; RET_ER=${E3} ;;
esac

# Display status banner
banner()
{
  echo
  if [[ $1 == '0' ]]; then
      echo "${RET_OK}" | base64 -d | gzip -d >&2
  else
      echo "${RET_ER}" | base64 -d | gzip -d >&2
      echo
      echo "Target: '$2', exit code: $1" >&2
  fi
  echo
}

# Display error message and exit
show_err_and_exit()
{
  echo
  echo "${RET_ER}" | base64 -d | gzip -d >&2
  echo
  echo "Target: '$2', exit code: $1" >&2
  echo
  exit $1
}

# Execute command with helper message & return code check 
action()
{
  local STRING rc out
  STRING=$1
  echo -n " ${STRING} ... "
  shift
  "$@" && success || failure
  rc=$?
  return ${rc}
}
