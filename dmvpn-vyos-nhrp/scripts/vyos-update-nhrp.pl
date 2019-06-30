#!/usr/bin/perl
#
# Module: vyos-update-nhrp.pl
#
# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# This code was originally developed by Vyos maintainers.
# All Rights Reserved.
#
# Author: Kim Hagen
# Date: August 2014
# Description: Script to configure nhrp
#
# **** End License ****
#

use Getopt::Long;
use POSIX;
use File::Basename;
use File::Compare;
use NetAddr::IP;

use lib "/opt/vyatta/share/perl5/";
use Vyatta::Config;
use Vyatta::Interface;

use strict;
use warnings;
my ($checkref, $set_nhrp, $set_ipsec, $get_esp_gr_names, $get_ike_gr_names, $set_iptables, $del_iptables, $tun);
my $conffile = '/etc/opennhrp/opennhrp.conf';
my $ipsecfile = '/etc/opennhrp/opennhrp.ipsec';

sub usage {
	print <<EOF;
Usage:
	$0 --set_nhrp --set_ipsec --get_esp_gr_names --get_ike_gr_names
EOF
	exit 1;
}

sub checkref {
	my $config_nhrp_tun = new Vyatta::Config;
   
	$config_nhrp_tun->setLevel("protocols nhrp tunnel");
	my @nhrp_tunnels = $config_nhrp_tun->listNodes();

	if (grep {$_ eq $tun} @nhrp_tunnels) {
		print ("WARNING: Can't delete tunnel $tun, it is in use by NHRP config.\n");
		exit 1;
	}
}

sub get_esp_groups {
	my $group_names = "";
	my $esp_groups = new Vyatta::Config;

	$esp_groups->setLevel("vpn ipsec esp-group");

	my @esp_groups = $esp_groups->listNodes();

	foreach my $group(@esp_groups) {
		$group_names = $group_names . " " . $group;
	}
	return $group_names;
}

sub get_ike_groups {
	my $group_names = "";
	my $ike_groups = new Vyatta::Config;

	$ike_groups->setLevel("vpn ipsec ike-group");

	my @ike_groups = $ike_groups->listNodes();

	foreach my $group(@ike_groups) {
		$group_names = $group_names . " " . $group;
	}
	return $group_names;
}

sub configure_nhrp_tunnels {
	my $cmd;
	my $config_tun = new Vyatta::Config;
	my $config_nhrp_tun = new Vyatta::Config;

	$config_tun->setLevel("interfaces tunnel");
	$config_nhrp_tun->setLevel("protocols nhrp tunnel");

	my @tunnels = $config_tun->listNodes();
	my @nhrp_tunnels = $config_nhrp_tun->listNodes();
	my $notun = 0;

	open (my $fh,">$conffile") or die("Can't open $conffile: $!\n");
	print $fh "";
	close $fh;

	if (@nhrp_tunnels) {
		foreach my $nhrp_tunnel(@nhrp_tunnels) {
			if (grep {$_ eq $nhrp_tunnel} @tunnels) {
				if ($config_tun->returnValue("$nhrp_tunnel encapsulation") eq "gre" && ! $config_tun->exists("$nhrp_tunnel remote-ip")) {
					my @conf_file = tunnel_config($nhrp_tunnel);
					open (my $fh,">>$conffile");
					foreach (@conf_file) {
		       				print $fh "$_";
	       				}
					close $fh;
					$notun = 1;
				}
				else {
					print ("$nhrp_tunnel is not 'mGRE' tunnel'\n");
					exit 1;
				}
			}
			else {
				print ("Tunnel $nhrp_tunnel does not exist.\n");
				exit 1;
			}
		}
	}
	if ("$notun" eq "1" ) {
		$cmd = "/etc/init.d/opennhrp.init restart";
		system ($cmd);
	}
	else {
		$cmd = "/etc/init.d/opennhrp.init stop";
		system ($cmd);
	}
}

sub configure_nhrp_ipsec {
	my $cmd;
	my $config_nhrp_tun = new Vyatta::Config;
	my $config_ipsec = new Vyatta::Config;

	$config_nhrp_tun->setLevel("protocols nhrp tunnel");
	$config_ipsec->setLevel("vpn ipsec profile");

	my @nhrp_tunnels = $config_nhrp_tun->listNodes();
	my @ipsec_profiles = $config_ipsec->listNodes();
	my $isipsec = 0;
	
	open(my $fh,">$ipsecfile") or die("Can't open $ipsecfile: $!\n");
	print $fh "";
	close $fh;

	if (@ipsec_profiles) {
		foreach my $ipsec_profile(@ipsec_profiles) {
			my $config_ipsec_profile_tun = new Vyatta::Config;

			$config_ipsec_profile_tun->setLevel("vpn ipsec profile $ipsec_profile bind tunnel");

			my @ipsec_profile_tunnels = $config_ipsec_profile_tun->listNodes();

			foreach my $ipsec_profile_tunnel(@ipsec_profile_tunnels) {
				if (grep {$_ eq $ipsec_profile_tunnel} @nhrp_tunnels) {
					my @conf_file = ipsec_config($ipsec_profile, $ipsec_profile_tunnel);
					open (my $fh,">>$ipsecfile");
					foreach (@conf_file) {
						print $fh "$_";
					}
					close $fh;
					$isipsec = 1;
				}
			}
		}
	}
	if ("$isipsec" eq "1" ) {
		$cmd = "/etc/init.d/opennhrp.init restart";
		system ($cmd);
	}
}

sub tunnel_config {
	my $tunnel_Config = new Vyatta::Config;
	my $tunnel_ID = $_[0];

	$tunnel_Config->setLevel("protocols nhrp tunnel");

	my @conf_file = ();
	my $type = "#hub";

	push(@conf_file, "interface $tunnel_ID $type\n");
	if ( $tunnel_Config->exists("$tunnel_ID map")) {
		$type = "#spoke";
		my @maps = $tunnel_Config->listNodes("$tunnel_ID map");
		shift(@conf_file);
		unshift(@conf_file, "interface $tunnel_ID $type\n");
		foreach my $map (@maps) {
			push(@conf_file, " map", " $map");
			push(@conf_file, " ", $tunnel_Config->returnValue("$tunnel_ID map $map nbma-address"));

			if ($tunnel_Config->exists("$tunnel_ID map $map register")) {
				push(@conf_file, " register");
			}
			if ($tunnel_Config->exists("$tunnel_ID map $map cisco")) {
				push(@conf_file, " cisco");
			}
			push(@conf_file, "\n");
		}
	}
	if ( $tunnel_Config->exists("$tunnel_ID dynamic-map")) {
		$type = "#spoke";
		my @dynmaps = $tunnel_Config->listNodes("$tunnel_ID dynamic-map");
		shift(@conf_file);
		unshift(@conf_file, "interface $tunnel_ID $type\n");
		foreach my $dynmap (@dynmaps) {
			push(@conf_file, " dynamic-map", " $dynmap");
			push(@conf_file, " ", $tunnel_Config->returnValue("$tunnel_ID dynamic-map $dynmap nbma-domain-name"));
			push(@conf_file, "\n");
		}
	}
	if ( $tunnel_Config->exists("$tunnel_ID shortcut-target")) {
		my @starget = $tunnel_Config->listNodes("$tunnel_ID shortcut-target");
		my $starget = $starget[0];
		push(@conf_file, " shortcut-target", " $starget");
		push(@conf_file, " ", $tunnel_Config->returnValue("$tunnel_ID shortcut-target $starget holding-time"));
		shift(@conf_file);
		unshift(@conf_file, "interface $tunnel_ID $type\n");
		push(@conf_file, "\n");
	}
	if ($tunnel_Config->returnValue("$tunnel_ID cisco-authentication") ne "") {
		push(@conf_file, " cisco-authentication ", $tunnel_Config->returnValue("$tunnel_ID cisco-authentication") , "\n"); 
	}
	if ( $tunnel_Config->exists("$tunnel_ID holding-time") && ($tunnel_Config->returnValue("$tunnel_ID holding-time") ne "")) {
		push(@conf_file, " holding-time", " ", $tunnel_Config->returnValue("$tunnel_ID holding-time") , "\n");
	}
	if ($tunnel_Config->exists("$tunnel_ID shortcut")) {
		push(@conf_file, " shortcut\n");
	}
	if ($tunnel_Config->exists("$tunnel_ID non-caching")) {
		push(@conf_file, " non-caching\n");
	}
	if ($tunnel_Config->exists("$tunnel_ID multicast")) {
		push(@conf_file, " multicast ", $tunnel_Config->returnValue("$tunnel_ID multicast") ,"\n");
	}	
	if ($tunnel_Config->exists("$tunnel_ID redirect")) {
		push(@conf_file, " redirect\n");
	}
	if ($tunnel_Config->exists("$tunnel_ID shortcut-destination")) {
		push(@conf_file, " shortcut-destination\n");
	}
	push(@conf_file, "\n");

	return @conf_file;
}

sub ipsec_config {
	my $new_rule = "";
	my ($ipsec_profile, $ipsec_tun) = @_;
	my $config_prot = new Vyatta::Config;
	my $config_ipsec = new Vyatta::Config;

	$config_ipsec->setLevel("vpn ipsec profile $ipsec_profile");

	my $config_tun = new Vyatta::Config;	

	$config_tun->setLevel("interfaces tunnel $ipsec_tun");

	my @conf_file = ();
	my ($esp_group, $ike_group, @tun_ip) = undef;

	$esp_group = $config_ipsec->returnValue("esp-group");
	$ike_group = $config_ipsec->returnValue("ike-group");	
	@tun_ip = $config_tun->returnValues('address');
	
	if (@tun_ip) {
		for my $ip (@tun_ip) {
			push(@conf_file, "interface $ipsec_tun\n");
			push(@conf_file, "$ip\n");
			if ($esp_group) {
				$config_prot->setLevel("vpn ipsec esp-group $esp_group");

				my @proposals = $config_prot->listNodes("proposal");
				my $x = 0;
				foreach my $e (@proposals) {
					$x ++;
				}
				my $y = 0;
				push(@conf_file, " --esp", " ");
				foreach my $proposal (@proposals) {
					if ($y != 0 && $y <= $x ) {
						push(@conf_file, ",");
					}
					if ($config_prot->exists("proposal $proposal encryption")) {
						push(@conf_file, $config_prot->returnValue("proposal $proposal encryption"));
					}
					else {
						push(@conf_file, "aes128");
					}
					if ($config_prot->exists("proposal $proposal hash")) {
						push(@conf_file, "-", $config_prot->returnValue("proposal $proposal hash"));
					}
					else {
						push(@conf_file, "-sha1");
					}
					if ($config_prot->exists("pfs")) {
						my $pfs = $config_prot->returnValue("pfs");
						if ($pfs eq 'dh-group2') {
							push(@conf_file, "-modp1024");
						}
						elsif ($pfs eq 'dh-group5') {
							push(@conf_file, "-modp1536");
						}
						elsif ($pfs eq 'dh-group14') {
							push(@conf_file, "-modp2048");
						}
						elsif ($pfs eq 'dh-group15') {
							push(@conf_file, "-modp3072");
						}
						elsif ($pfs eq 'dh-group16') {
							push(@conf_file, "-modp4096");
						}
						elsif ($pfs eq 'dh-group17') {
							push(@conf_file, "-modp6144");
						}
						elsif ($pfs eq 'dh-group18') {
							push(@conf_file, "-modp8192");
						}
						elsif ($pfs eq 'dh-group19') {
							push(@conf_file, "-ecp256");
						}
						elsif ($pfs eq 'dh-group20') {
							push(@conf_file, "-ecp384");
						}
						elsif ($pfs eq 'dh-group21') {
							push(@conf_file, "-ecp521");
						}
						elsif ($pfs eq 'dh-group22') {
							push(@conf_file, "-modp1024s160");
						}
						elsif ($pfs eq 'dh-group23') {
							push(@conf_file, "-modp2048s224");
						}
						elsif ($pfs eq 'dh-group24') {
							push(@conf_file, "-modp2048s256");
						}
						elsif ($pfs eq 'dh-group25') {
							push(@conf_file, "-ecp192");
						}
						elsif ($pfs eq 'dh-group26') {
							push(@conf_file, "-ecp224");
						}
					}
					++$y;
				}
				push(@conf_file, "\n");
			}
		
			if ($ike_group) {
				$config_prot->setLevel("vpn ipsec ike-group $ike_group");
				my @proposals = $config_prot->listNodes("proposal");
				my $x = 0;
				foreach my $e (@proposals) {
					$x ++;
				}
				my $y = 0;
				push(@conf_file, " --ike", " ");
				foreach my $proposal (@proposals) {
					if ($y != 0 && $y <= $x ) {
						push(@conf_file, ",");
					}
					if ($config_prot->exists("proposal $proposal encryption")) {
						push(@conf_file, $config_prot->returnValue("proposal $proposal encryption"));
					}
					else {
						push(@conf_file, "aes128");
					}
					if ($config_prot->exists("proposal $proposal hash")) {
						push(@conf_file, "-", $config_prot->returnValue("proposal $proposal hash"));
					}
					else {
						push(@conf_file, "-sha1");
					}
					if ($config_prot->exists("proposal $proposal dh-group")) {
						my $pfs = $config_prot->returnValue("proposal $proposal dh-group");
						if ($pfs eq '2') {
							push(@conf_file, "-modp1024");
						}
						elsif ($pfs eq '5') {
							push(@conf_file, "-modp1536");
						}
						elsif ($pfs eq '14') {
							push(@conf_file, "-modp2048");
						}
						elsif ($pfs eq '15') {
							push(@conf_file, "-modp3072");
						}
						elsif ($pfs eq '16') {
							push(@conf_file, "-modp4096");
						}
						elsif ($pfs eq '17') {
							push(@conf_file, "-modp6144");
						}
						elsif ($pfs eq '18') {
							push(@conf_file, "-modp8192");
						}
						elsif ($pfs eq '19') {
							push(@conf_file, "-ecp256");
						}
						elsif ($pfs eq '20') {
							push(@conf_file, "-ecp384");
						}
						elsif ($pfs eq '21') {
							push(@conf_file, "-ecp521");
						}
						elsif ($pfs eq '22') {
							push(@conf_file, "-modp1024s160");
						}
						elsif ($pfs eq '23') {
							push(@conf_file, "-modp2048s224");
						}
						elsif ($pfs eq '24') {
							push(@conf_file, "-modp2048s256");
						}
						elsif ($pfs eq '25') {
							push(@conf_file, "-ecp192");
						}
						elsif ($pfs eq '26') {
							push(@conf_file, "-ecp224");
						}
					}
					++$y;
				}
				if ($config_prot->exists("dead-peer-detection action")) {
					push(@conf_file, " ");
					push(@conf_file, "--dpdaction");
					push(@conf_file, " ");
					push(@conf_file, $config_prot->returnValue("dead-peer-detection action"));
					push(@conf_file, " ");
					push(@conf_file, "--dpdtimeout");
					push(@conf_file, " ");
					push(@conf_file, $config_prot->returnValue("dead-peer-detection timeout"));
					push(@conf_file, " ");
					push(@conf_file, "--dpddelay");
					push(@conf_file, " ");
					push(@conf_file, $config_prot->returnValue("dead-peer-detection interval"));
				}
				push(@conf_file, "\n");
			}
		}
	}
	push(@conf_file, "\n");

	return @conf_file;
}

sub create_nhrp_iptables {
	my $config_tun = new Vyatta::Config;
	
	$config_tun->setLevel("interfaces tunnel");
	
	if ( $config_tun->exists("$tun local-ip")) {
		my $local_ip = $config_tun->returnValue("$tun local-ip");

		system ("sudo iptables -N VYOS_NHRP_${tun}_OUT_HOOK") == 0 or die "System call failed: $!";
		system ("sudo iptables -A VYOS_NHRP_${tun}_OUT_HOOK -p gre -s ${local_ip} -d 224.0.0.0/4 -j DROP") == 0 or die "System call failed: $!";
		system ("sudo iptables -A VYOS_NHRP_${tun}_OUT_HOOK -j RETURN") == 0 or die "System call failed: $!";
		system ("sudo iptables -I OUTPUT 2 -j VYOS_NHRP_${tun}_OUT_HOOK") == 0 or die "System call failed: $!";
	}
}

sub delete_nhrp_iptables {
	system ("sudo iptables -D OUTPUT -j VYOS_NHRP_${tun}_OUT_HOOK") == 0 or die "System call failed: $!";
	system ("sudo iptables -D VYOS_NHRP_${tun}_OUT_HOOK 1") == 0 or die "System call failed: $!";
	system ("sudo iptables -D VYOS_NHRP_${tun}_OUT_HOOK 1") == 0 or die "System call failed: $!";
	system ("sudo iptables -X VYOS_NHRP_${tun}_OUT_HOOK") == 0 or die "System call failed: $!";
}

#
# main
#

GetOptions (
	"checkref"			=> \$checkref,
	"set_ipsec"			=> \$set_ipsec,
	"set_nhrp"			=> \$set_nhrp,
	"get_esp_gr_names"	=> \$get_esp_gr_names,
	"get_ike_gr_names"	=> \$get_ike_gr_names,
	"set_iptables"		=> \$set_iptables,
	"del_iptables"		=> \$del_iptables,
	"tun=s"     		=> \$tun
) or usage ();

checkref() if $checkref;
print get_esp_groups() if $get_esp_gr_names;
print get_ike_groups() if $get_ike_gr_names;
configure_nhrp_ipsec() if $set_ipsec;
configure_nhrp_tunnels() if $set_nhrp;
create_nhrp_iptables() if $set_iptables;
delete_nhrp_iptables() if $del_iptables;

# end of file
