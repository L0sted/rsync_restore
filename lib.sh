partition() {
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
    swapSize=$(free -m | grep "Mem" | awk '{print $2}')
    read -p "Enter extra amount of swap (empty == 512):" swapExtra
    if [ -z "$swapExtra" ] && swapExtra=512
    let "swapSize += swapExtra" #add 512 mbs to swap for 
    swapSize=$swapSize"M"
    return $TRUE
}
