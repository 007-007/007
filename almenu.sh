#!/bin/bash
echo ""
echo "SELAMAT DATANG DI INSTALLER ALL MENU VPS By YUSUF ARDIANSYAH"
echo ""
echo "Instalasi aplikasi pewarna text"
# aplikasi
sudo apt-get install ruby
sudo gem install lolcat;

echo "Instalasi file pewarna text sysrem"
# text sistem warna
cd
rm -rf .bashrc
wget https://raw.githubusercontent.com/via-valen/cantik/master/text%20warna/.bashrc
echo "Instalasi all menu PREMIUM"

# menu
cd
wget https://raw.githubusercontent.com/via-valen/cantik/master/menu/menu
mv ./menu /usr/local/bin/menu
chmod +x /usr/local/bin/menu

echo "Instalasi motd"
#motd
cd
wget "https://raw.githubusercontent.com/via-valen/cantik/master/menu/motd"
mv ./motd /etc/motd

echo "Instalasi speedtest"
#speedtest
cd
apt-get install python
wget -O speedtest.py "https://raw.githubusercontent.com/via-valen/cantik/master/menu/speedtest.py"
chmod +x speedtest.py

echo "Selesai...!!!";
