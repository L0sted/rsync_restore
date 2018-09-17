requestPartTable() {
    lsblk -o NAME,LABEL,FSTYPE,SIZE,MOUNTPOINT,MODEL
    until [ ! -f $targetDrive ]
    do
    read -p "Target drive is " targetDrive
    targetDrive=/dev/$targetDrive
    done
    echo "Encrypted?"
    while read -r -n 1 -s answer ; do
    if [[ $answer = [YyNn] ]]; then
        [[ $answer = [Yy] ]] && encryptedDevice=true && echo "WARNING You will be asked for password later" #read -p "Password: " encryptedPassword
        [[ $answer = [Nn] ]] && encryptedDevice=false
        break
    fi
    done

    #get swap size
    swapSize=$(free -m | grep "Mem" | awk '{print $2}') #get ram size
    read -p "Enter extra amount of swap (empty == 512):" swapExtra #request extra swap above ram size
    [ -z "$swapExtra" ] && swapExtra=512
    let "swapSize += swapExtra" #add 512 mbs to swap
    swapSize=$swapSize"M"
    return $TRUE
}

setPartitions(){
    ##clear mbr for sure

    dd if=/dev/zero of=$targetDrive count=512

    # partition scheme:
    # 1. swap
    # 2. boot
    # 3. root

    ##fdisk
    echo "==> Partitioning..."
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
    mkswap $targetDrive"1"
    mkfs.vfat $targetDrive"2"

    if $encryptedDevice #how to push password?
    then
    cryptsetup luksFormat -v $targetDrive"3"
    cryptsetup open $targetDrive"3" targetLuks
    mkfs.ext4 /dev/mapper/targetLuks
    else
    mkfs.ext4 $targetDrive"3"
    fi

    ##get disk's uuid
    echo "==> Getting UUIDs..."
    UUIDS=($(blkid $targetDrive"1" $targetDrive"2" $targetDrive"3" -o value -s UUID)) #created array of swap/boot/root UUIDs

    if $encryptedDevice
    then
    UUIDS[3]=UUIDS[2]
    UUIDS[2]=`blkid /dev/mapper/targetLuks -o value -s UUID`
    fi #now we have swap/boot/root/luks UUIDs

    ##mount disks
    echo "==> Mounting..."
    [ $encryptedDevice ] && mount /dev/mapper/targetLuks /mnt || mount $targetDrive"3" /mnt

    mkdir /mnt/boot
    mount $targetDrive"2" /mnt/boot

}