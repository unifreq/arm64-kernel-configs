#!/bin/bash

if [ $# -lt 1 ];then
    echo "Usage: $0 <env_file> [clean]"
    exit 1
fi

#############################################
######  env file shoud like this: #####
#
#KERNEL_SRC_HOME=/usr/src/linux-5.13.y
#CC=clang or gcc
#LD=ld.lld or ld 
#INITRAMFS_COMPRESS=zstd or xz or lzma or gzip or lzop
#FAKE_ROOT=/opt/armbian-bullseye-root  # extract from armbian image: https://dl.armbian.com
#
#############################################

export PATH=/usr/local/clang/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
POST_SCRIPT="/usr/src/post-kernel.sh"
ENV_FILE=$1
if [ ! -f $ENV_FILE ];then
    echo "Env file: $ENV_FILE not exists!"
    exit 1
fi
source $ENV_FILE

if [ -z "$CC" ];then
    CC=gcc
fi

if [ -z "$LD" ];then
    LD=ld
fi

if [ -z "$KERNEL_SRC_HOME" ];then
    KERNEL_SRC_HOME=/usr/src/linux
fi

if [ ! -d "${KERNEL_SRC_HOME}" ];then
    echo "Kernel source dir: ${KERNEL_SRC_HOME} not exists!"
    exit 1
fi
export CC LD KERNEL_SRC_HOME

# ccache flag
if which ccache;then
    CCACHE=1
else
    CCACHE=0
fi

case $CC in
    clang*) export MFLAGS="LLVM=1 LLVM_IAS=1"
	    CLANG=1
	    ;;
         *) export MFLAGS=""
	    CLANG=0
	    ;;
esac
export CLANG

cd $KERNEL_SRC_HOME
if [ ! -f "Makefile" ];then
    echo "Makefile not exists!"
    exit 1
fi


VERSION=$(grep -e '^VERSION = ' Makefile |awk '{print $3}')
PATCHLEVEL=$(grep -e '^PATCHLEVEL = ' Makefile |awk '{print $3}')
SUBLEVEL=$(grep -e '^SUBLEVEL = ' Makefile |awk '{print $3}')
EXTRAVERSION=$(grep -e '^EXTRAVERSION = ' Makefile |awk '{print $3}')

LTO=0
if [ $VERSION -eq 5 ] &&  [ $PATCHLEVEL -ge 12 ] && [ $CLANG -eq 1 ];then
    LTO=1
fi

if [ $VERSION -ge 6 ] && [ $CLANG -eq 1 ];then
    LTO=1
fi

echo 
echo "########################################################################"
echo `date` " : Start working ... "
echo

export LOCALVERSION=""
make CC=${CC} LD=${LD} ${MFLAGS} dtbs
VERSION_ADD=$(scripts/setlocalversion)
KERNEL_VER=${VERSION}.${PATCHLEVEL}.${SUBLEVEL}${EXTRAVERSION}${VERSION_ADD}
echo "Kernel version is $KERNEL_VER"

if [ "$2" == "clean" ];then
    make CC=${CC} LD=${LD} ${MFLAGS} clean
fi

if [ $LTO -eq 1 ] && [ $CLANG -eq 1 ];then
    scripts/config -e LTO_CLANG_THIN
else
    scripts/config -d LTO_CLANG_THIN
fi

PROCESS=$(cat /proc/cpuinfo | grep "processor" | wc -l)
if [ -z "$PROCESS" ];then
    PROCESS=1
fi

echo "*************************************************************************"
echo -n `date` 
echo " : Start building the kernel ... "
if [ $CCACHE -eq 1 ] && [ $CLANG -eq 0 ];then
    make CC="ccache ${CC}" LD=${LD} ${MFLAGS} Image modules dtbs -j${PROCESS}
    make_ret=$?
else
    make CC=${CC} LD=${LD} ${MFLAGS} Image modules dtbs -j${PROCESS}
    make_ret=$?
fi
echo -n `date` 
echo " : End of building the kernel"
echo "*************************************************************************"

if [ $make_ret -eq 0 ];then
	${POST_SCRIPT} ${ENV_FILE} "${KERNEL_VER}"
	if [ $? -eq 0 ];then
	    echo "Build the kernel [${KERNEL_VER}] successfully!"
	else
	    echo "Post the kernel [${KERNEL_VER}] failed!"
	fi
else
    echo "Build the kernel [${KERNEL_VER}] failed!"
fi

echo
echo -n `date` 
echo " : The end "
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
exit $make_ret
