# edgeos-dmvpn
OpenNHRP/DMVPN implementation on UBNT Edge Router Lite
Tested on MIPS EdgeOS v2.0.4

# Disclaimer
I am neither associated with Ubiquiti Networks nor the VyOS project.

# Build
To manually build this package on an x86 architecture machine, you'll need a MIPS VM. A Qemu VM on Linux seems to work well. I would highly suggest reading through all these instructions once before jumping into them or you'll likely need to backtrack a couple times.

I've adapted the commands below from here: https://community.ui.com/questions/Cross-Compiling-Tool-Chain/3793ff67-1080-45ac-8747-498c80b4d423

While it may be possible to run a Qemu MIPS VM directly on your machine, I used an Ubuntu 18 live iso in VMware so as not to muck up my normal Linux machine. This also makes these instructions portable across host OSes if you simply put the Qemu VM in a parent Linux VM. If using Ubuntu 18 live (furthermore referenced as "host system"), I'd suggest giving it at least 8G of RAM to allow space for the MIPS VM to be installed (I believe 6G is the minimum required here).

***If running nested VM's, don't forget to run your hypervisor as root to allow network traffic through***
     
Here are the commands to get the host system setup with KVM for the MIPS VM:
```bash
passwd				# Necessary for SSH
sudo su
add-apt-repository universe
apt update
apt install openssh-server    	# This is just easier than working directly in the virtualization software
systemctl start sshd		# SSH in after this point
```

After getting your host system set up, follow the instructions below to get the Qemu MIPS VM setup.
Get MIPS-ported Debian installed on a qemu system: https://markuta.com/how-to-build-a-mips-qemu-image-on-debian/
Get the right images for your current EdgeOS kernel (Stretch (9.0) as of writing is located here: http://ftp.debian.org/debian/dists/stretch/main/installer-mips/current/images/malta/netboot/). ***You will need a 4G HDD instead of 2G.***

To actually run Qemu I use a slightly different command than the above site references, but before running it I setup networking on the host system.
                                                                                                        
To setup networking follow the "Connect your emulated machine to a real network" part of https://www.aurel32.net/info/debian_mips_qemu.php
Run ```systemctl restart networking``` after installing bridge-utils and thing should work fine with the below command:
           
```
sudo qemu-system-mips -M malta -kernel vmlinux-4.9.0-9-4kc-malta -hda hda.img -append "root=/dev/sda1 console=ttyS0 nokaslr" -initrd initrd.img-4.9.0-9-4kc-malta -nographic -m 512 -net nic -net tap
```

In the Qemu VM, run:
```
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
systemctl restart sshd
```

Log into the Qemu VM over SSH and run:
```
apt update && apt install -y git make
git clone https://github.com/sc0ttes/edgeos-dmvpn.git
cd edgeos-dmvpn
make build
```

The build will likely take a very long time (hours). I'd suggest letting it run overnight. After it's done, you should have a nice zipped up edgeos-dmvpn.tar.gz that can be dropped on any MIPS EdgeOS router. The install instructions from that point are located in the zipped file as a file called TARGET-INSTALL.

# Helpful commands
Ctrl-A X			# Close Qemu from within the terminal  
ps -ef | grep open	 	# Check that the OpenNHRP process is running  
systemctl status opennhrp	# Check the status  
opennhrpctl show		# See the OpenNHRP connections  
opennhrpctl interface show	# Show relevant OpenNHRP interfaces  

