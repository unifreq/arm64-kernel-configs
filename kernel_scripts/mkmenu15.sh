#!/bin/bash
source /usr/src/k15.env
cd $KERNEL_SRC_HOME

case $CC in
    clang*)
        scripts/config -e LTO_CLANG_THIN
        make CC=${CC} LD=${LD} LLVM=1 LLVM_IAS=1 menuconfig
        scripts/config -e LTO_CLANG_THIN
	;;
         *)
        scripts/config -d LTO_CLANG_THIN
        make CC=${CC} LD=${LD} menuconfig
        scripts/config -d LTO_CLANG_THIN
	;;
esac
