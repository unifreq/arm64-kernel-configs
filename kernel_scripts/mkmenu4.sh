#!/bin/bash

source /usr/src/k4.env
cd $KERNEL_SRC_HOME

case $CC in
    clang*) make CC=${CC} LD=${LD} LLVM=1 LLVM_IAS=1 menuconfig
	    ;;
         *) make CC=${CC} LD=${LD} menuconfig
	    ;;
esac
