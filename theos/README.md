# How to use

1. Get [theos](https://github.com/theos/theos) installed
2. cd theos
3. make package
4. scp deb file under packages to device and `dpkg -i` to install the deb file
5. restart the target app

Modify atlantis.plist, add bundle ID to any app you like to work with

Modify Tweak.xm change HostName if you have multiple ProxyMan running on the same network

