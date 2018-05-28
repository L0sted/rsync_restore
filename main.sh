#not working encrypted setup

#vars
IP="192.168.100.16"
source="rsync@"$IP"/rsync/"
swapSize=$(free -m | grep "Mem" | awk '{print $2}')
let "swapSize += 512"
swapSize=$swapSize"M"
bootSize=256M

#prepare
##check for root
if [ `id -u` != 0 ] ; then 
    echo "==> Need to be root"
    exit 1
fi
##check for network
ping -c 1 $IP &> /dev/null
if [ "$?" != 0 ]
then
  echo "==> Host unavailable, exiting"
  exit 1
fi

##check for space

rsync_dir_list=($(rsync --password-file=rsync_pass rsync://$source | awk '{print $5}' | grep -v .DS_Store | grep -v "@Recently-Snapshot" | sort -r | head -n -1))

##choose backup

echo "==>" ${#rsync_dir_list[@]} backups: ${rsync_dir_list[@]}
read -p "Input backup number:" backupNum

until [ $backupNum -le ${#rsync_dir_list[@]} ]
do
read -p "Input backup number:" backupNum
done
let "backupNum -= 1"


##set target drive
lsblk -o NAME,LABEL,FSTYPE,SIZE,MOUNTPOINT,MODEL
until [ ! -f $targetDrive ]
do
read -p "Target drive is " targetDrive
targetDrive=/dev/$targetDrive
done
echo "Encrypted?"
while read -r -n 1 -s answer ; do
  if [[ $answer = [YyNn] ]]; then
    [[ $answer = [Yy] ]] && encryptedDevice=true && read -p "Password: " encryptedPassword
    [[ $answer = [Nn] ]] && encryptedDevice=false
    break
  fi
done
#DEPLOY

echo deployin\' ${rsync_dir_list[$backupNum]} on $targetDrive in 15s...

sleep 15


trap 'echo "==> Interrupted by user"; exit 1' 2

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
if $encryptedDevice
then
cryptsetup luksFormat -v $targetDrive"3" | echo $encryptedPassword
cryptsetup open $targetDrive"3" targetLuks | echo $encryptedPassword
mkfs.ext4 /dev/mapper/targetLuks
else
mkfs.ext4 $targetDrive"3"
fi

sleep 15

##get disk's uuid
echo "==> Got UUIDs!"
UUIDS=($(blkid $targetDrive"1" $targetDrive"2" $targetDrive"3" -o value -s UUID))
if $encryptedDevice
then
UUIDS[3]=UUIDS[2]
UUIDS[2]=`blkid /dev/mapper/targetLuks -o value -s UUID`
fi

##mount disks
echo "==> Mounting..."
if $encryptedDevice
then
mount /dev/mapper/targetLuks /mnt
else
mount $targetDrive"3" /mnt
fi

mkdir /mnt/boot
mount $targetDrive"2" /mnt/boot

##rsync
echo "==> Copying from NAS..."
rsync --archive --password-file=rsync_pass rsync://$source${rsync_dir_list[$backupNum]}/ /mnt/
retVal=$?
if [ $retVal -ne 0 ]; then
    exit 1
fi

##update fstab
echo "==> Updating fstab..."
mv /mnt/etc/fstab /mnt/etc/fstab.orig
cat /mnt/etc/fstab.orig | grep "ext4" | sed 's/UUID=[A-Fa-f0-9-]*/UUID='${UUIDS[2]}'/' > /mnt/etc/fstab
cat /mnt/etc/fstab.orig | grep "vfat" | sed 's/UUID=[A-Fa-f0-9-]*/UUID='${UUIDS[1]}'/' >> /mnt/etc/fstab
cat /mnt/etc/fstab.orig | grep "swap" | sed 's/UUID=[A-Fa-f0-9-]*/UUID='${UUIDS[0]}'/' >> /mnt/etc/fstab
rm /mnt/etc/fstab.orig

echo "==> Result:"
cat /mnt/etc/fstab
##update grub linux options
if $encryptedDevice
cat /mnt/etc/default/grub | sed 's/cryptdevice=UUID=[A-Fa-f0-9-]*:cryptroot /cryptdevice=UUID='${UUIDS[3]}':cryptroot/' > /mnt/etc/default/grub 
else
cat /mnt/etc/default/grub | sed 's/cryptdevice=UUID=[A-Fa-f0-9-]*:cryptroot //' > /mnt/etc/default/grub
fi

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