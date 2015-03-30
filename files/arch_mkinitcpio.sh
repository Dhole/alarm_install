#! /bin/sh
set -uew

pacman -Sy
pacman -S mkinitcpio uboot-mkimage
cp /root/files/mkinitcpio.conf /etc/mkinitcpio.conf
mkinitcpio -g ~/uInitrd.img
mount /dev/mmcblk1p2 /boot
mkimage -A arm -T ramdisk -C none -n initramfs -d ~/uInitrd.img /boot/uInitrd.uimg
umount /boot