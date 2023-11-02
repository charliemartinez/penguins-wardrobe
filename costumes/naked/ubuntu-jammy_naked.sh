#!/bin/bash
clear
echo "ubuntu-jammy_naked"
echo ""

if [[ $EUID -ne 0 ]]; then
   printf "%s need to run with root privileges. \nPlease, prefix it with sudo\n", "$0"
   exit 1
fi

COSTUME="naked"
MY_USERNAME=$(logname)
MY_USERHOME="/home/${MY_USERNAME}"

# wait to start
printf "wardrobe: Prepare your costume: %s?\n", "${COSTUME}"
echo "Press enter to continue or CTRL-C to abort"
read -r

# unpdate
apt-get update

# install costume
apt-get install -y \
    locales \
    nano 

# /etc/hostname
../../scripts/hostname.sh "${COSTUME}"

# reboot
reboot
