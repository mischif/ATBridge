```
 ______  ______  ____                   __                    
/\  _  \/\__  _\/\  _`\          __    /\ \                   
\ \ \L\ \/_/\ \/\ \ \L\ \  _ __ /\_\   \_\ \     __      __   
 \ \  __ \ \ \ \ \ \  _ <'/\`'__\/\ \  /'_` \  /'_ `\  /'__`\ 
  \ \ \/\ \ \ \ \ \ \ \L\ \ \ \/ \ \ \/\ \L\ \/\ \L\ \/\  __/ 
   \ \_\ \_\ \ \_\ \ \____/\ \_\  \ \_\ \___,_\ \____ \ \____\
    \/_/\/_/  \/_/  \/___/  \/_/   \/_/\/__,_ /\/___L\ \/____/
                                                 /\____/      
                                                 \_/__/       
```

AudioTronBridge - Raspberry Pi-based SMB proxy for ancient electronics

Overview
=========

The Turtle Beach AudioTron is a decent enough music player - I can't tell if it was released before the FLAC format but I still wish it supported FLAC files - but it can only connect to network shares using SMBv1, making it machinam non grata on any modern network.

So how do you use a perfectly-functional device like this without its ancient firmware degrading your network? You use a proxy like ATBridge.

Architecture
============

```
                                     ____________
                                     |          |
((Local Network))-------[WiFi]-------| ATBridge |-------[Ethernet]-------((AudioTron))
                                     |__________|
```

WiFi:
* Connected to your local network
* Connects to existing shares using modern protocols/security

Ethernet:
* Connected to your AudioTron
* Proxies exising shares using SMBv1 for AudioTron
* Allows AudioTron to be placed anywhere with power/WiFi

Config Files
============

You will need to create and include two config files for ATBridge to function correctly:
* A file named `wireless.conf` that contains the credentials for your WiFi network; it uses the [wpa_supplicant](https://steveedson.co.uk/tools/wpa/) format.
* A file named `smb.creds` that contains the connection information for each share to proxy to the AudioTron; each line has the following format:

`(hostname or IP address)\(share name)\username\password\workgroup`

You can look at `smb.creds.examples` as a template:
* The first line connects to a share named `share1` at 10.20.30.40 using the username `user1`, password `password1` and workgroup `MEDIA`
* The second line connects to a share named `share2` at a host named `mediaserver` using the username `user2`, password `password2` and the default workgroup `WORKGROUP`
* The third line connects to a share named `openshare` at a host named `mediaserver` using no username/password and the default workgroup.

Build Steps
===========

While every attempt was made to automate the ATBridge build process, there is an unfortunate amount of necessary prep work.

* These steps assume you will be using VirtualBox as your hypervisor; substituting another hypervisor is allowed, but not tested.
* These steps assume you downloaded the project zip; cloning the project makes no meaningful difference.
* These steps assume you have a folder on your host at \~/atbridge where this project is stored.

1. Copy your `wireless.conf` and `smb.creds` files to \~/atbridge
2. Set up a new VM guest (Other Linux, 64-bit) with a 2G hard drive and at least 2G RAM
3. Create a shared folder named atbridge mapping to \~/atbridge on your host
4. [Download a copy](https://alpinelinux.org/downloads/) of the virtual build of Alpine
5. Insert the Alpine ISO into your guest and boot
6. Run `setup-alpine` and make a sys install to disk (root password doesn't matter as this VM is meant to be disposable)
7. Power down the guest, remove the Alpine ISO and reboot
8. Enable access to community repos: `sed -i '3s/^#//' /etc/apk/repositories`
9. Create the shared folder mount: `mkdir /media/atbridge`
10. Install the guest tools to enable shared folders: `apk update && apk add virtualbox-guest-additions`
11. Reboot and mount the shared folder: `mount -t vboxsf atbridge /media/atbridge`
12. Extract the project: `unzip /media/atbridge/ATBridge-master.zip -d /media/atbridge`
13. Begin building your atbridge image `/media/atbridge/atbridge-master/atbridge.sh`
14. Choose your desired architecture; after about 15 minutes `atbridge-${TARGET_ARCH}.tar.gz` should exist in the shared folder
15. Extract the tarball onto a MicroSD card

User Notes
==========
* An AudioTron connected through ATBridge will no longer be directly reachable; you can use the IP address of the ATBridge to interact with the AudioTron's web interface
* ATBridge was mainly designed for use with local music; reaching Internet radio stations may still work but hasn't been tested
* The root user on the ATBridge has no password; this doesn't matter much as there is no SSH server enabled, but if you are concerned about physical interference you may wish to rectify this (don't forget to [commit your changes](https://wiki.alpinelinux.org/wiki/Alpine_local_backup#Committing_changes))
* The AudioTron does not support MP3s with ID3v2.4 tags; future improvements to ATBridge include a FUSE module that converts tags to ID3v2.3 automatically, as well as converting FLAC files to WAV.
