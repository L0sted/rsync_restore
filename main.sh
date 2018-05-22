#prepare
##check for root
if [ `id -u` != 0 ] ; then 
    echo "==> Need to be root"
    exit 1
fi
##check for network
ping -c 1 192.168.100.16 &> /dev/null
if [ "$?" != 0 ]
then
  echo "==> Host unavailable, exiting"
  exit 1
fi

##check for space

rsync_dir_list=($(rsync --password-file=/home/losted/.rsync_pass rsync://rsync@192.168.100.16/rsync/ | awk '{print $5}' | grep -v .DS_Store | grep -v "@Recently-Snapshot" | sort -r | head -n -1))

swapSize=$(free -m | grep "Mem" | awk '{print $2}')
let "swapSize += 512"
swapSize=$swapSize"M"
bootSize=256M

#begin

##chose backup

echo "==>" ${#rsync_dir_list[@]} backups: ${rsync_dir_list[@]}
read -p "Input backup number:" backupNum
let "backupNum -= 1"

##set target drive
lsblk -o NAME,LABEL,FSTYPE,SIZE,MOUNTPOINT,MODEL
read -p "Target drive is " targetDrive

targetDrive=/dev/$targetDrive

echo deployin\' ${rsync_dir_list[$backupNum]} on $targetDrive in 15s...

sleep 15

##clear mbr for sure

dd if=/dev/zero of=$targetDrive count=512

##fdisk
echo "==> fdisk is working..."
(
echo o # Create a new empty DOS partition table
echo n # Add a new partition
echo # Primary partition
echo # Partition number
echo # First sector (Accept default: 1)
echo +$swapSize  # Last sector (Accept default: varies)
echo y #remove sign
echo n
echo
echo
echo
echo +$bootSize
echo y
echo n
echo
echo
echo
echo
echo w
) | fdisk $targetDrive
    # IMHO this ^ is less obfuscated way

##mkfs's
echo "==> Making filesystems..."
echo "mkswap"
mkswap $targetDrive"1"
echo "mkfs.vfat"
mkfs.vfat $targetDrive"2"
echo "mkfs.ext4"
mkfs.ext4 $targetDrive"3"

##get disk's uuid
echo "==> Got UUIDs!"
UUIDS=($(blkid $targetDrive"1" $targetDrive"2" $targetDrive"3" -o value -s UUID))

##mount disks
echo "==> Mounting..."
mount $targetDrive"3" /mnt
mkdir /mnt/boot
mount $targetDrive"2" /mnt/boot

##rsync
echo "==> Copying from NAS..."
rsync --archive -P --password-file=/home/losted/.rsync_pass rsync://rsync@192.168.100.16/rsync/${rsync_dir_list[$backupNum]}/ /mnt/

##update fstab
echo "==> Updating fstab..."
rm /mnt/etc/fstab.orig
mv /mnt/etc/fstab /mnt/etc/fstab.orig
cat /mnt/etc/fstab.orig | grep "ext4" | sed 's/UUID=[A-Fa-f0-9-]*/UUID='${UUIDS[2]}'/' > /mnt/etc/fstab
cat /mnt/etc/fstab.orig | grep "vfat" | sed 's/UUID=[A-Fa-f0-9-]*/UUID='${UUIDS[1]}'/' >> /mnt/etc/fstab
cat /mnt/etc/fstab.orig | grep "swap" | sed 's/UUID=[A-Fa-f0-9-]*/UUID='${UUIDS[0]}'/' >> /mnt/etc/fstab
rm /mnt/etc/fstab.orig

echo "==> Result:"
cat /mnt/etc/fstab
##update grub linux options

cat /mnt/etc/default/grub | sed 's/cryptdevice=UUID=[A-Fa-f0-9-]*:cryptroot //' > /mnt/etc/default/grub #remove cryptdevice, no encrypted fs today :c

cat /mnt/etc/default/grub | sed 's/resume=UUID=[A-Fa-f0-9-]*/resume=UUID='${UUIDS[0]}'/' > /mnt/etc/default/grub

##mount system stuff
echo "==> Mounting /dev, /sys, /proc..."
mount /dev /mnt/dev --bind
mount /sys /mnt/sys --bind
mount /proc /mnt/proc --bind

##chroot, mkinitcpio and update grub
echo "==> mkinitcpio and update grub..."

#cat /mnt/etc/mkinitcpio.conf | sed 's/encrypt //' > /mnt/etc/mkinitcpio.conf #remove cryptdevice, no encrypted fs today :c

#chroot env
cat << EOF | chroot /mnt
mkinitcpio -P
grub-mkconfig -o /boot/grub/grub.cfg
grub-install $targetDrive
exit
EOF

#deinit
echo "==> Syncing..."
sync
echo "==> Unmounting..."
umount -R /mnt
echo "==> Done!"