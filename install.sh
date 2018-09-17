#!/bin/bash

#host os should be arch or arch based

source lib.sh

installDistro() {
    case "$targetDistro" in
    "1")
        read -p "Enter packages/pkg groups you need:" targetPkgs
        [ $targetBoot == "1" ] && targetPkgs+="grub"
        
        pacstrap /mnt $targetPkgs 
        ;;
    "2")
        [ -z `pacman -Qqs debootstrap`] && pacman -Syu debootstrap --noconfirm #install debootstrap if not found
        read -p "stable/unstable/testing?" debVersion #ask for version
        debootstrap $debVersion /mnt http://deb.debian.org/debian/
        ;;
    "3")
        #install gentoo
        echo "WIP"
        ;;
    *)
        echo "no such distro"
        ;;
    esac
}
postInstall() {
    #genfstab, install bootloader
    genfstab -U /mnt >> /mnt/etc/fstab
    #check for efi

    case "$targetBoot" in
    "1")
        #grub
cat << EOF |arch-chroot /mnt
grub-mkconfig -o /boot/grub/grub.cfg
grub-install
exit
EOF
        ;;
    "2")
        #systemd-boot
cat << EOF | arch-chroot /mnt
bootctl install
exit
EOF
        # bootctl --path=/mnt/boot/efi install
        ;;
    *)
        echo "wtf"
        ;;
}

#distro
echo -e "Choose distro:\n1. arch\n2. debian (based)\n3. gentoo"
read  targetDistro
until [ $targetDistro -le  3]
do
read -p "Incorrect number:" targetDistro
done
#loader
echo -e "Choose loader:\n1. grub\n2. systemd-boot"
read  targetBoot
until [ $targetBoot -le  2]
do
read -p "Incorrect number:" targetBoot
done

#work
requestPartTable
setPartitions
installDistro
postInstall
echo "Now, theoretically system should work"