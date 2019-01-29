RELEASE='xenial'
IS_EXIT=false
INSTALL_NYX=true
CHECK_IPV6=true
ENABLE_AUTO_UPDATE=true

echo -e "\e[36m" #cyan
cat << "EOF"

 _____            ___     _
|_   _|__ _ _ ___| _ \___| |__ _ _  _   __ ___
  | |/ _ \ '_|___|   / -_) / _` | || |_/ _/ _ \
  |_|\___/_|     |_|_\___|_\__,_|\_, (_)__\___/
                                 |__/

EOF

echo -e "\e[39m" #default
echo "              [Relay Setup]"
echo "This script will ask for your sudo password."
echo "----------------------------------------------------------------------"

echo "Updating package list..."
sudo apt-get -o=Dpkg::Use-Pty=0 -o=Acquire::ForceIPv4=true update > /dev/null

echo "Installing necessary packages..."
sudo apt-get -qqy -o=Dpkg::Use-Pty=0 -o=Acquire::ForceIPv4=true install apt-transport-https psmisc dirmngr ntpdate > /dev/null

echo "Updating NTP..."
sudo ntpdate pool.ntp.org > /dev/null

echo "Adding Torproject apt-get repository..."
sudo touch /etc/apt/sources.list.d/tor.list
echo "deb https://deb.torproject.org/torproject.org $RELEASE main" | sudo tee /etc/apt/sources.list.d/tor.list > /dev/null
echo "deb-src https://deb.torproject.org/torproject.org $RELEASE main" | sudo tee --append /etc/apt/sources.list.d/tor.list > /dev/null

echo "Adding Torproject GPG key..."
# gpg --keyserver keys.gnupg.net --recv A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 > /dev/null
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89
# gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | sudo apt-key add - > /dev/null

echo "Updating package list..."
sudo apt-get -o=Dpkg::Use-Pty=0 -o=Acquire::ForceIPv4=true update > /dev/null

if $INSTALL_NYX
then
  echo "Installing NYX..."
  #sudo apt-get -y install tor-arm > /dev/null
  sudo apt-get -qqy -o=Dpkg::Use-Pty=0 -o=Acquire::ForceIPv4=true install python-setuptools > /dev/null
  sudo easy_install pip
  sudo pip install nyx
fi

echo "Installing Tor..."
sudo apt-get -qqy -o=Dpkg::Use-Pty=0 -o=Acquire::ForceIPv4=true install tor deb.torproject.org-keyring > /dev/null
sudo apt-get -qqy -o=Dpkg::Use-Pty=0 -o=Acquire::ForceIPv4=true install tor tor-geoipdb torsocks deb.torproject.org-keyring
sudo chown -R debian-tor:debian-tor /var/log/tor

echo "Configuring UFW..."
sudo ufw allow 443
sudo ufw allow 80
sudo ufw reload

echo "Setting Tor config..."
cat << 'EOF' | sudo tee /etc/tor/torrc > /dev/null
SocksPort 0
RunAsDaemon 1
ORPort 443
ORPort [INSERT_IPV6_ADDRESS]:443
Nickname AKtorFirefly
ContactInfo akcryptoguy [akcryptoguy|gmail|com]
Log notice file /var/log/tor/notices.log
DirPort 80
ExitPolicy reject6 *:*, reject *:*
RelayBandwidthRate 5 MBits
RelayBandwidthBurst 10 MBits
AccountingStart month 1 00:00
AccountingMax 1000 GB
ControlPort 9051
CookieAuthentication 1
MaxMemInQueues 256MB
DisableDebuggerAttachment 0
NodeFamily 7CB76558E894800A00F5B602B37D8E4F121F5958,ADA083D5BFA2CB071AB7FA976307200BD1B111B8

EOF

echo "Setting Tor config..."
mkdir /root/.nyx
touch /root/.nyx/config
cat << 'EOF2' | sudo tee /root/.nyx/config > /dev/null
# nyx config can go here (https://nyx.torproject.org/nyxrc.sample)
max_log_size 1000

EOF2

if $IS_EXIT
then
  echo "Downloading Exit Notice to /etc/tor/tor-exit-notice.html..."
  echo -e "\e[1mPlease edit this file and replace FIXME_YOUR_EMAIL_ADDRESS with your e-mail address!"
  echo -e "\e[1mAlso note that this is the US version. If you are not in the US please edit the file and remove the US-Only sections!\e[0m"
  sudo wget -q -O /etc/tor/tor-exit-notice.html "https://raw.githubusercontent.com/flxn/tor-relay-configurator/master/misc/tor-exit-notice.html"
fi

echo "Blocking torrent traffic..."
cat << 'EOF3' | sudo tee /etc/tor/blocktorrent.sh > /dev/null
for j in `for a in $(wget -qO- http://www.trackon.org/api/all | awk -F/ ' { print $3 }' ); do dig +short a $a; done |grep -v [a-z]|sort|uniq`; do iptables -I OUTPUT -d $j -j DROP; done

EOF3

chmod 0700 /etc/tor/blocktorrent.sh
for j in `for a in $(wget -qO- http://www.trackon.org/api/all | awk -F/ ' { print $3 }' ); do dig +short a $a; done |grep -v [a-z]|sort|uniq`; do iptables -I OUTPUT -d $j -j DROP; done
(crontab -l ; echo "0 * * * * /etc/tor/blocktorrent.sh ") | crontab -

if $CHECK_IPV6
then
  IPV6_ADDRESS=`/usr/bin/wget -q -O - http://ipv6.icanhazip.com/ | /usr/bin/tail`
  # this gets you a list of all IPv6 addresses
  # ip -o -6 addr list eth0 | awk '{print $4}' | cut -d/ -f1
  # IPV6_ADDRESS=$(ip -6 addr | grep inet6 | grep "scope global" | awk '{print $2}' | cut -d'/' -f1)
  if [ -z "$IPV6_ADDRESS" ]
  then
    sudo /etc/init.d/tor stop
    echo -e "\e[31mCould not automatically find your IPv6 address"
    sudo sed -i -e '/INSERT_IPV6_ADDRESS/d' /etc/tor/torrc
    sudo sed -i -e 's/IPv6Exit 1/IPv6Exit 0/' /etc/tor/torrc
    echo -e "\e[31mIPv6 support has been disabled\e[39m"
    echo "If you want to enable it manually find out your IPv6 address and add this line to your /etc/tor/torrc"
    echo "ORPort [YOUR_IPV6_ADDRESS]:YOUR_ORPORT (example: \"ORPort [2001:123:4567:89ab::1]:9001\")"
    echo "Then run \"sudo /etc/init.d/tor restart\" to restart Tor"
  else
    sudo sed -i "s/INSERT_IPV6_ADDRESS/$IPV6_ADDRESS/" /etc/tor/torrc
    echo -e "\e[32mIPv6 Support enabled ($IPV6_ADDRESS)\e[39m"
  fi
fi

sleep 5
echo "Reloading Tor config..."
sudo /etc/init.d/tor restart

echo -e "\e[32mSetup finished\e[39m"
echo "----------------------------------------------------------------------"
echo "Tor will now check if your ports are reachable. This may take up to 20 minutes."
echo "Check /var/log/tor/notices.log for an entry like:"
echo "\"Self-testing indicates your ORPort is reachable from the outside. Excellent.\""
echo "----------------------------------------------------------------------"
sleep 5
nyx
clear
IPV4=`/usr/bin/wget -q -O - http://ipv4.icanhazip.com/ | /usr/bin/tail`
echo -e "The is your tor relay's private fingerprint for IP ($IPV4):"
cat /var/lib/tor/fingerprint
echo -e "\nThis is your tor relay's private key to backup"
cat /var/lib/tor/keys/secret_id_key
echo -e "\n"
