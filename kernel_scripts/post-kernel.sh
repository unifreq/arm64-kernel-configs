#!/bin/bash

# begin 检查环境参数
if [ $# -ne 2 ];then
    echo "$0 env_file kernel-version"
    exit 1
fi

ENV_FILE=$1
source $ENV_FILE
VER=$2
echo "Posting kernel $VER ..."

TMPFS_SIZE=3072M
TMP_SRC_DIR="lib/modules/linux"

case $CC in
    clang*) CLANG=1;;
         *) CLANG=0;;
esac

if [ $CLANG -eq 1 ];then
    export MFLAGS="LLVM=1 LLVM_IAS=1"
else
    export MFLAGS=""
fi

if [ -z "$FAKE_ROOT" ];then
    FAKE_ROOT=/opt/armbian-bullseye-root
fi

export LOCALVERSION=""
POST_HOME="/opt/kernel"
# end 检查环境参数

function set_localversion() {
    cd $KERNEL_SRC_HOME
    echo "Set localversion ... "
    scripts/setlocalversion
    echo "done"
    echo
}

function clean_env() {
    echo -n "Clean ${FAKE_ROOT} environments ... "
    MNTS="/lib/modules ${FAKE_ROOT}/lib/modules  ${FAKE_ROOT}/boot"
    for MNT in $MNTS;do
	 i=1
         while :;do
             umount -f ${MNT} 2>/dev/null
	     if [ $? -eq 0 ];then
                 break
             else
	         let i++

	         if [ $i -ge 3 ];then
		     echo "umount ${MNT} failed!"
                     exit 1
	         fi
		 sleep 1
	     fi
	 done
    done

    rm -rf ${FAKE_ROOT}/lib/modules && mkdir ${FAKE_ROOT}/lib/modules
    rm -rf ${FAKE_ROOT}/boot && mkdir ${FAKE_ROOT}/boot
    echo "done"
    echo
}

function clean_exit() {
    clean_env
    echo $1
    exit $2
}

function init_env() {
    echo -n "Init ${FAKE_ROOT} environments ... "
    rm -rf ${FAKE_ROOT}/lib/modules && mkdir ${FAKE_ROOT}/lib/modules
    rm -rf ${FAKE_ROOT}/boot && mkdir ${FAKE_ROOT}/boot 
    mount -t tmpfs -o size=$TMPFS_SIZE none ${FAKE_ROOT}/lib/modules || clean_exit "mount failed" 1
    mount -t tmpfs none ${FAKE_ROOT}/boot || clean_exit "mount failed" 2
    mount -o bind ${FAKE_ROOT}/lib/modules /lib/modules || clean_exit "mount failed" 3
    echo "done"
    echo
}

function make_dtbs() {
    (
        cd $KERNEL_SRC_HOME
        echo "Make dtbs ... "
        make CC=${CC} LD=${LD} $MFLAGS dtbs || clean_exit "make dtbs failed" 1
	echo "Dtbs make done!"
    )
}

function modules_install() {
    # make modules_install
    (
        cd $KERNEL_SRC_HOME
	echo "Install modules ..."
        make CC=${CC} LD=${LD} $MFLAGS modules_install || clean_exit "install modules failed" 1

	echo "Strip debug info ... "
        find ${FAKE_ROOT}/lib/modules -name '*.ko' -exec strip --strip-debug {} \;
	echo "Strip done"

	echo "Modules installed!"
	echo
    )
}

function is_enabled() {
	grep -q "^$1=y" include/config/auto.conf
}

function if_enabled_echo() {
	if is_enabled "$1"; then
		echo -n "$2"
	elif [ $# -ge 3 ]; then
		echo -n "$3"
	fi
}

function deploy_kernel_headers () {
	src_home=$1
	dest_dir=$2
	src_arch=$3

        head_list=$(mktemp /tmp/head_list.XXXXXX)
	(
		cd $src_home
		find . arch/$src_arch -maxdepth 1 -name Makefile\*
		find include scripts -type f -o -type l
		find arch/$src_arch -name Kbuild.platforms -o -name Platform
		find $(find arch/$src_arch -name include -o -name scripts -type d) -type f
	) > $head_list

	obj_list=$(mktemp /tmp/obj_list.XXXXXX)
	{
		if is_enabled CONFIG_OBJTOOL; then
			echo tools/objtool/objtool
		fi

		find arch/$src_arch/include Module.symvers include scripts -type f

		if is_enabled CONFIG_GCC_PLUGINS; then
			find scripts/gcc-plugins -name \*.so
		fi
	} > $obj_list

	rm -rf $dest_dir
	mkdir -p $dest_dir
	tar --exclude '*.orig' -c -f - -C $src_home -T $head_list | tar -xf - -C $dest_dir
	tar --exclude '*.orig' -c -f - -T $obj_list | tar -xf - -C $dest_dir
	rm -f $head_list $obj_list

	# copy .config manually to be where it's expected to be
	cp .config $dest_dir/.config
}

function headers_install() {
    (
    	cd $KERNEL_SRC_HOME
	echo "Install headers ..."
	if [ -d $HDR_PATH ];then
	    rm -rf $HDR_PATH/*
	else
	    mkdir -p $HDR_PATH
	fi

	deploy_kernel_headers $KERNEL_SRC_HOME $HDR_PATH "arm64"
	echo "Header installed!"
	echo
    )
}

function cross_headers_install() {
    (
	cd "$FAKE_ROOT/$TMP_SRC_DIR"
	echo "Install headers ..."
	if [ -d $HDR_PATH ];then
	    rm -rf $HDR_PATH/*
	else
	    mkdir -p $HDR_PATH
	fi

	deploy_kernel_headers "${FAKE_ROOT}/${TMP_SRC_DIR}" $HDR_PATH "arm64"
	echo "Header installed!"
	echo
    )
    rm -rf $FAKE_ROOT/${TMP_SRC_DIR}
}

function update_initramfs() {
    (
        cd $KERNEL_SRC_HOME
        echo "Copy kernel files to ${FAKE_ROOT}/boot/ ..."
        cp -v System.map ${FAKE_ROOT}/boot/System.map-${VER}
        cp -v .config ${FAKE_ROOT}/boot/config-${VER}

        [ -f arch/arm64/boot/Image ] && \
		cp -v arch/arm64/boot/Image ${FAKE_ROOT}/boot/vmlinuz-${VER}

	echo "Copy done!"
	echo

	cp -v /etc/resolv.conf ${FAKE_ROOT}/etc/

	# for cross compile
	if [ `uname -m` == 'x86_64' ];then
	    rm -f ${FAKE_ROOT}/usr/bin/qemu-aarch64*

 	    # debian & ubuntu, can install qemu-user-static
	    # otherwise, install qemu-linux-user
	    if [ -f /usr/bin/qemu-aarch64-static ];then
	        [ -f ${FAKE_ROOT}/usr/bin/qemu-aarch64-static ] || cp -v /usr/bin/qemu-aarch64-static ${FAKE_ROOT}/usr/bin/
            elif [ -f /usr/bin/qemu-aarch64 ];then
	        [ -f ${FAKE_ROOT}/usr/bin/qemu-aarch64 ] || cp -v /usr/bin/qemu-aarch64 ${FAKE_ROOT}/usr/bin/
	        [ -f ${FAKE_ROOT}/usr/bin/qemu-aarch64-binfmt ] || cp -v /usr/bin/qemu-aarch64-binfmt ${FAKE_ROOT}/usr/bin/
	        echo "Start systemd-binfmt.service ... "
  	        [ -f /sbin/qemu-binfmt-conf.sh ] && /sbin/qemu-binfmt-conf.sh --systemd aarch64
	        systemctl start systemd-binfmt.service
	        if [ $? -ne 0 ];then
	            echo "start systemd-binfmt.service failed!"
	            exit 1
	        else
	            systemctl status systemd-binfmt.service
                fi
	    fi

	    # Make cross platform scripts
	    echo
	    echo "======================================================================="
	    echo "Make the cross platform headers ..."
	    echo "Copy kernel sources to ${FAKE_ROOT}/${TMP_SRC_DIR} ... "
	    [ -d "${FAKE_ROOT}/${TMP_SRC_DIR}" ] && rm -rf "${FAKE_ROOT}/${TMP_SRC_DIR}"
	    mkdir -p "${FAKE_ROOT}/${TMP_SRC_DIR}" && \
		git archive --format=tar main | tar xf - -C "${FAKE_ROOT}/${TMP_SRC_DIR}/" && \
		cp -v .config Module.symvers "${FAKE_ROOT}/${TMP_SRC_DIR}/"
		echo "Copy done!"
	    echo

	    echo "Make kernel/scripts for arm64 ... "
            chroot ${FAKE_ROOT} <<EOF
cd ${TMP_SRC_DIR} && make scripts
exit
EOF
	    if [ $? -ne 0 ];then
		clean_exit "make kernel/scripts failed!" 1
	    fi
	    echo "Make kernel/scripts done!"
	    echo "======================================================================="
	    echo
	    # The end of make cross platform scripts
	fi

        if [ -z ${INITRAMFS_COMPRESS} ];then
            INITRAMFS_COMPRESS=gzip
        fi

        echo "Use [${INITRAMFS_COMPRESS}] to compress initrd ... "
        sed -e "/COMPRESS=/d" -i ${FAKE_ROOT}/etc/initramfs-tools/initramfs.conf
        echo "COMPRESS=${INITRAMFS_COMPRESS}" >> ${FAKE_ROOT}/etc/initramfs-tools/initramfs.conf
        chroot ${FAKE_ROOT} update-initramfs -c -k ${VER} || clean_exit "update initramfs failed!" 1
        echo "Update initramfs done!"
	echo

	# for cross compile
	if [ `uname -m` == 'x86_64' ] && [ ! -f /usr/bin/qemu-aarch64-static ];then
	   echo "Stop systemd-binfmt.service ... "
	   systemctl stop systemd-binfmt.service 
	   systemctl status systemd-binfmt.service 
	fi
    )
}

function archive_dtbs() {
    (
        cd $KERNEL_SRC_HOME
	echo "Archive dtbs ..."
	PLATFORMS="allwinner amlogic rockchip"
	for PLAT in $PLATFORMS;do
            echo -n "  -> Archive platform ${PLAT} dtbs to $POST_HOME/dtb-${PLAT}-${VER}.tar.gz ... "
            cd $KERNEL_SRC_HOME/arch/arm64/boot/dts/${PLAT}
	    dtbs=$(ls *.dtb 2>/dev/null)
	    if [ "$dtbs" != "" ];then
	        file_list=$(mktemp /tmp/file_list.XXXXXX)
	        find . -name '*.dtb' > $file_list
	        find . -name '*.dtbo' >> $file_list
	        find . -name '*.scr' >> $file_list
	        find . -name 'README*' >> $file_list
                tar -czf $POST_HOME/dtb-${PLAT}-${VER}.tar.gz -T $file_list || clean_exit "archive dtbs failed!" 1
	        rm -f $file_list
            fi
            echo "done"
        done
        echo "Archive dtbs done!"
    )
}

function archive_boot() {
    (
        echo -n "Archive boot files to $POST_HOME/boot-${VER}.tar.gz ... "
        cd ${FAKE_ROOT}/boot && \
	   tar cf - *${VER} | pigz -9 > $POST_HOME/boot-${VER}.tar.gz || clean_exit "archive boot files failed!" 1
	echo "done!"
    )
}

function archive_modules {
    (
        echo -n "Archive modules to $POST_HOME/modules-${VER}.tar.gz ... "
        cd ${FAKE_ROOT}/lib/modules && \
	    tar cf - ${VER} | pigz -9 > $POST_HOME/modules-${VER}.tar.gz || clean_exit "archive modules failed!" 1
	echo "done!"
    ) 
}

function archive_headers {
    (
        echo -n "Archive headers to $POST_HOME/header-${VER}.tar.gz ... "
        cd ${HDR_PATH} && \
	    tar cf - . | pigz -9 > $POST_HOME/header-${VER}.tar.gz || clean_exit "archive headers failed!" 1
	echo "done!"
    ) 
}

trap "clean_exit" 2 3 15

echo
echo "#########################################################################################"
echo -n `date`
echo " : Post kernel starting ..."
echo "#########################################################################################"
echo
# 环境初始化
init_env
set_localversion
make_dtbs
modules_install
update_initramfs
if [ `uname -m` == 'x86_64' ];then
    cross_headers_install
else
    headers_install
fi
archive_dtbs 
archive_boot
archive_modules
archive_headers
clean_env
sync
echo "#########################################################################################"
echo -n `date`
echo " : Post Kernel Done!"
echo "#########################################################################################"
echo
exit 0
