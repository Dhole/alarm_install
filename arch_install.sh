#! /bin/sh
set -uew

# Sources and inspiration:
# https://elatov.github.io/2014/11/install-chromeos-kernel-38-on-samsung-chromebook/
# https://elatov.github.io/2014/02/install-arch-linux-samsung-chromebook/
# http://archlinuxarm.org/platforms/armv7/samsung/samsung-chromebook
# http://linux-exynos.org/wiki/Samsung_Chromebook_XE303C12/Installing_Linux
# http://archlinuxarm.org/forum/viewtopic.php?f=47&t=7071
# https://dvikan.no/the-smallest-archlinux-install-guide

# TODO: Install in eMMC
# https://wiki.archlinux.org/index.php/Samsung_Chromebook_%28ARM%29

function install_deps {
    # Install necessary packages for ubuntu
    sudo apt-get install u-boot-tools gcc-arm-linux-gnueabihf \
        binutils-arm-linux-gnueabihf cgpt device-tree-compiler
}

function clone_kernel {
    # Download kernel 3.8 with ChromeOS patches
    git clone https://chromium.googlesource.com/chromiumos/third_party/kernel.git \
        -b $KERNEL_BRANCH --depth 1 chromeos
}

function download_arch {
    # Download rootfs tarball
    wget http://archlinuxarm.org/os/ArchLinuxARM-chromebook-latest.tar.gz
}

function install_arch {
    # Extract rootfs tarball
    tar -xf ArchLinuxARM-chromebook-latest.tar.gz -C root
}

function build_kernel {
    cd $KERNEL_BRANCH
    
    CROSS_COMPILE=arm-linux-gnueabihf- ARCH=arm make mrproper
    
    ./chromeos/scripts/prepareconfig chromeos-exynos5

    # Configure the kernel as needed (Alternativelly, download my custom .config)
    # Be sure to disable "Treat compiler warnings as errors" in menuconfig
    # CROSS_COMPILE=arm-linux-gnueabihf- ARCH=arm make menuconfig
    cp ../files/.config .

    # Compile the kernel
    CROSS_COMPILE=arm-linux-gnueabihf- ARCH=arm make uImage -j2
    CROSS_COMPILE=arm-linux-gnueabihf- ARCH=arm make modules -j2
    CROSS_COMPILE=arm-linux-gnueabihf- ARCH=arm make dtbs -j2
    
    rm -rf ../lib/modules/
    CROSS_COMPILE=arm-linux-gnueabihf- ARCH=arm INSTALL_MOD_PATH=$TMP_PATH \
        make modules_install
        
    # wget http://linux-exynos.org/dist/chromebook/snow/kernel.its \
    #    -O arch/arm/boot/kernel.its
    
    # Edit kernel.its
    cp ../files/kernel.its arch/arm/boot/.
    
    mkimage -f arch/arm/boot/kernel.its $TMP_PATH/vmlinux.uimg
    
    cd $TMP_PATH
}

function install_kernel {
    # Copy the kernel to the kernel partition
    cp vmlinux.uimg mnt
    rm -rf root/usr/lib/modules/3.8.11/
    cp -R lib root/usr
}

function mount_nomal {
    mount "${DISK}2" mnt
    mount "${DISK}3" root
}

function umount_normal {
    umount mnt
    umount root
}

function mount_luks {
    cryptsetup luksOpen "${DISK}3" alarm_rootfs -y --key-file rootfs.key
    mount /dev/mapper/alarm_rootfs root
    mount "${DISK}2" mnt
}

function umount_luks {
    umount mnt
    umount root
    cryptsetup close alarm_rootfs
}

function install_default_kernel {
    mount "${DISK}2" mnt
    mount "${DISK}3" root
    cp root/boot/vmlinux.uimg mnt
    umount mnt
    umount root
}

function install_uboot_script {
    # Copy the U-Boot script to the script partition
    mount "${DISK}12" mnt
    mkdir -p mnt/u-boot
    wget http://archlinuxarm.org/os/exynos/boot.scr.uimg -O boot.scr.uimg
    cp boot.scr.uimg mnt/u-boot
    umount mnt
}

function install_custom_uboot_script {
    # Copy the U-Boot script to the script partition
    mount "${DISK}12" mnt
    mkdir -p mnt/u-boot
    #wget http://archlinuxarm.org/os/exynos/boot.scr.uimg
    mkimage -A arm -T script -C none -n 'Chromebook Boot Script' \
        -d boot_custom2.scr boot.scr.uimg
    cp boot.scr.uimg mnt/u-boot
    umount mnt
}

function download_install_nv_uboot_fb {
    wget -O - http://commondatastorage.googleapis.com/chromeos-localmirror/distfiles/nv_uboot-snow-simplefb.kpart.bz2 \
        | bunzip2 > nv_uboot.kpart
    dd if=nv_uboot.kpart of="${DISK}1"
}

function download_install_nv_uboot {
    wget -O - http://commondatastorage.googleapis.com/chromeos-localmirror/distfiles/nv_uboot-snow.kpart.bz2 \
        | bunzip2 > nv_uboot-snow.kpart
    dd if=nv_uboot-snow.kpart of="${DISK}1"
}

function prepare_sd {
    umount $DISK*
    # Create a new disk label for GPT. Type y when prompted after running
    parted $DISK mklabel gpt
    # Partition the SD card:
    cgpt create -z $DISK 
    cgpt create $DISK 
    cgpt add -i 1 -t kernel -b 8192 -s 32768 -l U-Boot -S 1 -T 5 -P 10 $DISK 
    cgpt add -i 2 -t data -b 40960 -s 32768 -l Kernel $DISK
    cgpt add -i 12 -t data -b 73728 -s 32768 -l Script $DISK
    # Create root partition
    PART_SIZE=$(cgpt show $DISK | egrep '[0-9\ ]*Sec GPT table' | awk '{print $1}')
    cgpt add -i 3 -t data -b 106496 -s `expr $PART_SIZE - 106496` -l Root $DISK
    # Tell the system to refresh what it knows about the disk partitions:
    partprobe $DISK
    # Format partitions
    mkfs.ext2 "${DISK}2"
    mkfs.ext4 "${DISK}3"
    mkfs.vfat -F 16 "${DISK}12"
}

function prepare_crypt_root {
    # Create key file. Store this safely!!!
    dd if=/dev/urandom of=rootfs.key bs=128 count=1
    # Create luks container with key file
    cryptsetup luksFormat "${DISK}3" rootfs.key -c aes-xts-plain64 -s 256 --hash sha512
    # Add password to luks container
    cryptsetup luksAddKey "${DISK}3" --key-file rootfs.key
    cryptsetup luksOpen "${DISK}3" alarm_rootfs -y --key-file rootfs.key
    mkfs.ext4 /dev/mapper/alarm_rootfs
    
    # Install arch
    mount /dev/mapper/alarm_rootfs root
    
    umount root
    cryptsetup close alarm_rootfs
}

function arch_mkinitcpio {
    pacman -Sy
    pacman -S mkinitcpio uboot-mkimage
    # Download custom /etc/mkinitcpio.conf
    mkinitcpio -g ~/uInitrd.img
    mount /dev/mmcblk1p2 /boot
    mkimage -A arm -T ramdisk -C none -n initramfs -d ~/uInitrd.img /boot/uInitrd.uimg
    umount /boot
}

function install_custom_files {
    cp files/arch_mkinitcpio.sh root/root/
    cp files/postinstall.sh root/root/   
    cp files/arch/private/mlan0-wrt54gl root/etc/netctl/
    
    mkdir -p root/root/files/
    cp -R files/arch/* root/root/files/
}

function install_files {
    mount "${DISK}2" mnt
    mount "${DISK}3" root
    # Install initramfs
    cp files/uInitrd.img mnt
    # Copy mkinitcpio.conf
    cp files/mkinitcpio.conf root/etc
    
    umount mnt
    umount root
}

DISK=/dev/sde
# DISK=$1
#KERNEL_BRANCH="release-R40-6457.B-chromeos-3.8"
KERNEL_BRANCH="chromeos-3.8"

install_deps

TMP_PATH=$(pwd)/chromeos
mkdir -p $TMP_PATH
cd $TMP_PATH
mkdir -p root
mkdir -p mnt

download_arch

clone_kernel
build_kernel

prepare_sd
download_install_nv_uboot_fb
prepare_crypt_root
mount_luks
install_arch
install_kernel
install_files
install_custom_files
umount_luks

install_custom_uboot_script

##### Do your stuff ######



#### Stop doing stuff ####

sudo umount $DISK*
sync
