#! /bin/sh
set -uew

function arch_customization {
    # Disable clearing of boot messages
    mkdir -p /etc/systemd/system/getty@tty1.service.d/
    echo -e "[Service]\nTTYVTDisallocate=no" > /etc/systemd/system/getty@tty1.service.d/noclear.conf
    echo "/usr/local/lib" >> /etc/ld.conf.d/local.conf
    
    # Install fonts http://linuxfonts.narod.ru/
    cp /root/files/fonts.conf /etc/fonts/conf.d/99-my-fonts.conf
    cd /usr/share
    7z e /root/files/fonts.7z
    cd /root
    
    # Enable suspend and xscreen lock on lid close
    # https://blog.omgmog.net/post/making-suspend-on-lid-close-work-with-arch-linux-on-the-hp-chromebook-11/
    cp /root/files/handler.sh /etc/acpi/handler.sh
    systemctl enable acpid
    
    # Install custom touchpad, keyboard, evdev
    cp /root/files/xorg.conf.d/* /etc/X11/xorg.conf.d
    
    systemctl enable lightdm
    
    # Set default brightness on power up and script to change it
    cp /root/files/brightness.conf /etc/tmpfiles.d/brightness.conf
    cp /root/files/chbr /usr/local/bin/chbr
    
    # Configure pulseaudio
    echo "load-module module-alsa-sink device=sysdefault" >> /etc/pulse/default.pa
    
    # Enable rsyslog
    systemctl enable rsyslog.service
    systemctl start rsyslog.service
    
    # Change MAC at every connection
    cp /root/files/mac_change /etc/wicd/scripts/preconnect/
    
    # Fix wicd-curses 
    # https://github.com/voidlinux/void-packages/commit/220de599ad3ecba14423289209a3e4e031037edf
    cp /root/files/netentry_curses.py /usr/share/wicd/curses/
    
    # Enable eduroam for wicd http://chakraos.org/wiki/index.php?title=Wicd#Making_eduroam_work_with_wicd
    cp /root/files/ttls-80211 /etc/wicd/encryption/templates/
    cd /etc/wicd/encryption/templates
    echo ttls-80211 >> active
    cd /root
    mkdir -p etc/ca-certificates/custom/
    cp /root/files/AddTrustExternalCARoot.crt /etc/ca-certificates/custom/
    
    # Chromium defaults
    cp /root/files/chromium_default /etc/chromium/default
}

function arch_config {
    locale-gen
    # echo "LANG=en_US.UTF-8" >> /etc/locale.conf
    localectl set-locale LANG=en_US.UTF-8
    # ln -s /usr/share/zoneinfo/Europe/Madrid /etc/localtime
    timedatectl set-timezone Europe/Madrid
    hostnamectl set-hostname $MYHOSTNAME
}

function add_user {
    useradd -m -G users -s /bin/bash silver
    passwd silver
    visudo # uncomment the wheel group
    usermod -a -G wheel silver
}

function install_packages {
    pacman -S xorg-server xorg-xinit xorg-server-utils mesa xf86-video-fbdev xf86-input-synaptics xf86-armsoc-chromium unzip dbus
    # Choose mesa-libgl when asked
    pacman -S lightdm lightdm-gtk3-greeter gnome-icon-theme
    pacman -S xfce4 sudo firefox midori gnome-keyring wget vim ttf-dejavu ttf-ubuntu-font-family htop strace lsof i3 xscreensaver git conky dmenu profont dina-font tamsyn-font alsa-utils ntp pm-utils p7zip xarchiver unrar zip python-pip tmux mpv mc make tmux iputils rtorrent youtube-dl macchanger tree acpid pulseaudio pulseaudio-alsa mupdf clang file gvim mosh nmap rxvt-unicode thunar 
    pacman -S adduser rsyslog
}

function user_config {
    # Volume keys DONE -> See .i3/config

    # Touchpad palm rest detection (disable touchpad while typing)
    # syndaemon -i 0.5 -d -t -K # Add this to i3 config
    # Touchpad: don't move cursor when tapping (very noticable at double tapping)
    # ??? Couldn't figure out how to do this

    # In i3, xfce4-term doesn't have borders
    # for_win class bla bla borders normal

    # Disable F1 and F10 in xfce4-terminal
    # edit .config/xfce4...
    
    # Install wicd saved networks
    sudp cp /root/private/wireless-settings.conf /etc/wicd/
}

#########

# Configure and connect wifi:
wifi-menu mlan0
# Save on boot
# sudo netctl enable mlan0-wifi


#########

# Enable eduroam http://chakraos.org/wiki/index.php?title=Wicd#Making_eduroam_work_with_wicd
# http://www.rediris.es/scs/cacrt/AddTrustExternalCARoot.crt

# Set chromium cache in /tmp (edit /etc/chromium...)

#########

MYHOSTNAME="fox"
arch_config
pacman -Syu
install_packages
add_user
arch_customization
user_config