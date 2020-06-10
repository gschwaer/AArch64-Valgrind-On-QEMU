#!/bin/bash
#
# This script follows the guides at
# https://www.centennialsoftwaresolutions.com/post/build-the-linux-kernel-and-busybox-and-run-them-on-qemu
# https://wiki.qemu.org/Documentation/9psetup
#

CROSS_COMPILE_ELF="$HOME/.local/opt/aarch64-toolchain/gcc-arm-9.2-2019.12-x86_64-aarch64-none-elf/bin/aarch64-none-elf-"
CROSS_COMPILE_LINUX="$HOME/.local/opt/aarch64-toolchain/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-"


set -e # exit on errors
set -u # exit on unset variables
set -o pipefail # propagate errors in pipes
#set -x # enable verbose output


main()
{
if [[ ! -x "${CROSS_COMPILE_ELF}gcc" ]]; then
	echo "Need to set CROSS_COMPILE_ELF path (AArch64 ELF bare-metal target: aarch64-none-elf)!"
	echo "Compiler can be downloaded from:"
	echo "  https://developer.arm.com/-/media/Files/downloads/gnu-a/9.2-2019.12/binrel/gcc-arm-9.2-2019.12-x86_64-aarch64-none-elf.tar.xz"
	exit 1
fi
if [[ ! -x "${CROSS_COMPILE_LINUX}gcc" ]]; then
	echo "Need to set CROSS_COMPILE_LINUX path (AArch64 GNU/Linux target: aarch64-none-linux-gnu)!"
	echo "Compiler can be downloaded from:"
	echo "  https://developer.arm.com/-/media/Files/downloads/gnu-a/9.2-2019.12/binrel/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu.tar.xz"
	exit 1
fi

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
TOP=$parent_path


echo_red "Checking Dependencies"
dpkg-query --show curl || sudo apt install curl
dpkg-query --show libncurses5-dev || sudo apt install libncurses5-dev


echo_red "Downloading Sources"
cd "$TOP"
echo "* Linux 5.6.16"
[ ! -d "linux-5.6.16" ] && curl "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.6.16.tar.xz" | tar xJf -
echo "* Busybox 1.31.1"
[ ! -d "busybox-1.31.1" ] && curl "https://busybox.net/downloads/busybox-1.31.1.tar.bz2" | tar xjf -
echo "* QEMU 5.0.0"
[ ! -d "qemu-5.0.0" ] && curl "https://download.qemu.org/qemu-5.0.0.tar.xz" | tar xJf -
echo "* Valgrind 3.16.0"
[ ! -d "valgrind-3.16.0" ] && curl "https://sourceware.org/pub/valgrind/valgrind-3.16.0.tar.bz2" | tar xjf -


build_linux

build_busybox

build_qemu

build_valgrind

create_initramfs
install_busybox_into_initramfs
install_valgrind_into_initramfs
install_libc_into_initramfs
bundle_initramfs

if [[ ! -e "$TOP/launch_qemu.sh" ]]; then
	# don't overwrite, in case the user modified the script
	echo "#!/bin/bash" > "$TOP/launch_qemu.sh"
	echo '"'"$TOP/obj/qemu-aarch64/aarch64-softmmu/qemu-system-aarch64"'"'" -machine virt -cpu cortex-a57 -m 2048 -smp 2 -nographic -kernel "'"'"$TOP/obj/linux-arm64-qemuconfig/arch/arm64/boot/Image"'"'" -append "'"'"console=ttyAMA0 earlyprintk=serial"'"'" -initrd "'"'"$TOP/initramfs.cpio"'"'" -virtfs local,id=x0,path="'"'"$TOP/exchange"'"'",security_model=none,mount_tag=exchange" >> "$TOP/launch_qemu.sh"
	chmod +x "$TOP/launch_qemu.sh"
	echo_red "Generated launch_qemu.sh"
fi

[ ! -d "$TOP/exchange" ] && mkdir -p "$TOP/exchange" && echo_red "Created exchange directory"

echo_red "done"
echo
echo "To launch qemu, use the script launch_qemu.sh or:"
echo "  "'"'"$TOP/obj/qemu-aarch64/aarch64-softmmu/qemu-system-aarch64"'"'" -machine virt -cpu cortex-a57 -m 2048 -smp 2 -nographic -kernel "'"'"$TOP/obj/linux-arm64-qemuconfig/arch/arm64/boot/Image"'"'" -append "'"'"console=ttyAMA0 earlyprintk=serial"'"'" -initrd "'"'"$TOP/initramfs.cpio"'"'" -virtfs local,id=x0,path="'"'"$TOP/exchange"'"'",security_model=none,mount_tag=exchange"
echo "  Terminate QEMU with ctrl-a x"
echo "An exchange folder is mounted:"
echo "  Host: "'"'"$TOP/exchange"'"'
echo "  Guest: /mnt"
echo "Start valgrind with:"
echo "  valgrind ./my_program"
echo "  valgrind --tool=cachegrind --cachegrind-out-file=/mnt/cachegrind.out.%p ./my_program"
echo
}


echo_red()
{
	# tput checks if colors are available (from bashrc)
	[ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null && echo -en "\033[1;31m" # set forground color: red
	echo -n "$1"
	[ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null && echo -e "\033[0m" # reset coloring
}


build_linux()
{
	echo_red "Building Linux"
	#rm -r "$TOP/obj/linux-arm64-qemuconfig" || true
	mkdir -pv "$TOP/obj/linux-arm64-qemuconfig"
	cd "$TOP/linux-5.6.16"
	echo_red "-> configuring"
	#make O="$TOP/obj/linux-arm64-qemuconfig" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE_ELF" allnoconfig
	#make O="$TOP/obj/linux-arm64-qemuconfig" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE_ELF" menuconfig; exit 0
cat > "$TOP/obj/linux-arm64-qemuconfig/.config.fragment" << EOF
CONFIG_BLK_DEV_INITRD=y
# CONFIG_RD_GZIP=y # we are not using a gzip'ed initramfs right now
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y # for init
CONFIG_TTY=y
CONFIG_SERIAL_AMBA_PL011=y
CONFIG_SERIAL_AMBA_PL011_CONSOLE=y
CONFIG_PROC_FS=y # required for valgrind's --trace-children
# CONFIG_SYSFS=y
# CONFIG_DEVTMPFS=y
CONFIG_PRINTK=y
CONFIG_PRINTK_TIME=y
# VirtFS (Plan 9 folder sharing over Virtio - I/O virtualization framework)
CONFIG_NET=y
CONFIG_NET_9P=y
CONFIG_NET_9P_VIRTIO=y
# CONFIG_NET_9P_DEBUG=y # (Optional)
CONFIG_NETWORK_FILESYSTEMS=y
CONFIG_INET=y
CONFIG_9P_FS=y
CONFIG_9P_FS_POSIX_ACL=y
CONFIG_PCI=y
CONFIG_VIRTIO_MENU=y
CONFIG_VIRTIO_PCI=y
CONFIG_PCI_HOST_GENERIC=y
EOF
	make O="$TOP/obj/linux-arm64-qemuconfig" KCONFIG_ALLCONFIG="$TOP/obj/linux-arm64-qemuconfig/.config.fragment" ARCH="arm64" CROSS_COMPILE="$CROSS_COMPILE_ELF" allnoconfig
	echo_red "-> compiling ..."
	make O="$TOP/obj/linux-arm64-qemuconfig" ARCH="arm64" CROSS_COMPILE="$CROSS_COMPILE_ELF" -j$(nproc)
}


build_busybox()
{
	echo_red "Building Busybox"
	#rm -r "$TOP/obj/busybox-aarch64" || true
	mkdir -pv "$TOP/obj/busybox-aarch64"
	echo_red "-> configuring"
	cd "$TOP/busybox-1.31.1"
	make O="$TOP/obj/busybox-aarch64" ARCH="arm64" CROSS_COMPILE="$CROSS_COMPILE_LINUX" defconfig
	#cp "$TOP/obj/busybox-aarch64/.config" "$TOP/obj/busybox-aarch64/.config_cmp"
	#make O="$TOP/obj/busybox-aarch64" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE_LINUX" menuconfig
	#diff "$TOP/obj/busybox-aarch64/.config_cmp" "$TOP/obj/busybox-aarch64/.config"
	#exit 0
# Static build is not necessary anymore, since we include shared objects of libc.
#patch "$TOP/obj/busybox-aarch64/.config" << EOF
#44c44
#< # CONFIG_STATIC is not set
#---
#> CONFIG_STATIC=y
#EOF
	echo_red "-> compiling ..."
	cd "$TOP/obj/busybox-aarch64"
	make O="$TOP/obj/busybox-aarch64" ARCH="arm64" CROSS_COMPILE="$CROSS_COMPILE_LINUX" -j$(nproc)
	make O="$TOP/obj/busybox-aarch64" ARCH="arm64" CROSS_COMPILE="$CROSS_COMPILE_LINUX" install
}


install_busybox_into_initramfs()
{
	cp -av "$TOP/obj/busybox-aarch64/_install/"* "$TOP/initramfs/"
cat > "$TOP/initramfs/init" << EOF
#!/bin/sh
mount -t proc none /proc
# mount -t sysfs none /sys
# mount -t devtmpfs devtmpfs /dev
mount -t 9p -o trans=virtio exchange /mnt -oversion=9p2000.L
echo "Hand over from Kernel to Init succeeded. Dropping to Busybox shell."
echo "Note: Terminate QEMU with Ctrl-A X"
export VALGRIND_LIB=/lib/valgrind
exec /bin/sh
EOF
	chmod +x "$TOP/initramfs/init"
}


build_qemu()
{
	echo_red "Building QEMU"
	#rm -r "$TOP/obj/qemu-aarch64" || true
	mkdir -pv "$TOP/obj/qemu-aarch64"
	echo_red "-> check dependencies"
	dpkg-query --show libcap-ng-dev || sudo apt install libcap-ng-dev
	dpkg-query --show libattr1-dev || sudo apt install libattr1-dev
	echo_red "-> configuring"
	cd "$TOP/obj/qemu-aarch64"
	"$TOP/qemu-5.0.0/configure" --enable-kvm --enable-virtfs --target-list="aarch64-softmmu" #aarch64-linux-user
	echo_red "-> compiling ..."
	make -j$(nproc)
}


build_valgrind()
{
	echo_red "Building Valgrind"
	rm -r "$TOP/obj/valgrind-aarch64" || true
	mkdir -pv "$TOP/obj/valgrind-aarch64"
	echo_red "-> configuring"
	cd "$TOP/valgrind-3.16.0"
	CC=${CROSS_COMPILE_LINUX}gcc LD=${CROSS_COMPILE_LINUX}ld AR=${CROSS_COMPILE_LINUX}ar ./autogen.sh
	CC=${CROSS_COMPILE_LINUX}gcc LD=${CROSS_COMPILE_LINUX}ld AR=${CROSS_COMPILE_LINUX}ar ./configure --prefix="/" --host="aarch64-unknown-linux" --enable-only64bit
	echo_red "-> compiling ..."
	CC=${CROSS_COMPILE_LINUX}gcc LD=${CROSS_COMPILE_LINUX}ld AR=${CROSS_COMPILE_LINUX}ar make -j$(nproc)
	CC=${CROSS_COMPILE_LINUX}gcc LD=${CROSS_COMPILE_LINUX}ld AR=${CROSS_COMPILE_LINUX}ar make -j$(nproc) install DESTDIR="$TOP/obj/valgrind-aarch64"
}


install_valgrind_into_initramfs()
{
	cp -av "$TOP/obj/valgrind-aarch64/"* "$TOP/initramfs/"
}


install_libc_into_initramfs()
{
	cp -av "$(dirname $CROSS_COMPILE_LINUX)/../aarch64-none-linux-gnu/libc/"* "$TOP/initramfs/"
}


create_initramfs()
{
	echo_red "Creating initramfs"
	rm -rf "$TOP/initramfs" || true
	mkdir -pv "$TOP/initramfs"
	cd "$TOP/initramfs"
	mkdir -pv {bin,dev,sbin,etc,proc,sys/kernel/debug,usr/{bin,sbin},lib,lib64,mnt,root,tmp}
}


bundle_initramfs()
{
	echo_red "Bundling initramfs"
	cd "$TOP/initramfs"
	find . | cpio --create --format=newc --owner=root:root > "$TOP/initramfs.cpio"
	# Skipping gzip since loading raw from RAM is faster than decompression.
	#cat "$TOP/initramfs.cpio" | gzip > "$TOP/initramfs.img.gz"
}


main "$@"; exit
