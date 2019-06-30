#!/usr/bin/perl

# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2010 Vyatta, Inc.
# All Rights Reserved.
#
# Author: Bob Gilligan
# Date: Jully, 2010
# Description: Script to update the grub config file after full upgrade.
#
# **** End License ****

use strict;
use warnings;
use Getopt::Long;
use File::Temp qw/ :mktemp /;

my $UNION_BOOT_DIR = `/opt/vyatta/sbin/vyos-persistpath` . '/boot';
my $UNION_GRUB_CFG_DIR = "$UNION_BOOT_DIR/grub";
my $DISK_BOOT_DIR = '/boot';
my $DISK_GRUB_CFG_DIR= '/boot/grub';
my $OLD_IMG_VER_STR = 'Old-non-image-installation';

# Returns the version string of the currently running system.
# The logic is roughly like this:
# 
# First, figure out whether system is image-booted or standard booted.
# Next, locate the grub config file.
# Next, edit all entries for running image to use the vmlinuz and
# initrd.img symlinks instead of specific kernel and initrd files.
# Next, change the vmlinuz and initrd.img symlinks to point to the
# correct kernel and initrd.img files.
#
sub curVer {
    my $vers = `awk '{print \$1}' /proc/cmdline`;

    # In an image-booted system, the image name is the directory name
    # directory under "/boot" in the pathname of the kernel we booted.
    $vers =~ s/BOOT_IMAGE=\/boot\///;
    $vers =~ s/\/?vmlinuz.*\n$//;

    # In a non-image system, the kernel resides directly under "/boot".
    # No second-level directory means that $vers will be null.
    if ($vers eq "") {
        $vers = $OLD_IMG_VER_STR;
    }
    return $vers;
}

my $boot_dir;
my $grub_cfg_dir;
my $grub_cfg_file;
my $tmp_grub_cfg_file;
my $on_disk_kernel_dir;
my $local_kernel_dir;
my $running_image_name;
my $debug_flag = 0;

GetOptions(
    "debug"     => \$debug_flag,
    );


sub log_msg {
    my $message = shift;

    print "DEBUG: $message" if $debug_flag;
}


# Main

if (-e $UNION_BOOT_DIR) {
    $boot_dir = $UNION_BOOT_DIR;
    $grub_cfg_dir = $UNION_GRUB_CFG_DIR;

    $running_image_name = curVer();
    if ($running_image_name eq $OLD_IMG_VER_STR) {
	print "Can't find image name for union booted system.\n";
	exit 1;
    }
    $on_disk_kernel_dir = "/boot/$running_image_name";
    $local_kernel_dir = "$boot_dir/$running_image_name";
    if (! -e $local_kernel_dir) {
	print "Can't find kernel directory: $local_kernel_dir\n";
	exit 1;
    }
    log_msg("System is image booted.\n");
} elsif (-e $DISK_BOOT_DIR) {
    $boot_dir = $DISK_BOOT_DIR;
    $grub_cfg_dir = $DISK_GRUB_CFG_DIR;
    $on_disk_kernel_dir = $boot_dir;
    $local_kernel_dir = $boot_dir;
    $running_image_name = "";
    log_msg("System is disk booted.\n");
} else {
    print "Can't locate boot directory!\n";
    exit 1;
}

$grub_cfg_file = "$grub_cfg_dir/grub.cfg";

if (! -e $grub_cfg_file) {
    print "can't locate grub config file: $grub_cfg_file\n";
    exit 1;
}

if (-e "$local_kernel_dir/linux" && ! -l "$local_kernel_dir/linux") {
    print "Linux binary is not a symlink:  $local_kernel_dir/linux\n";
    exit 1;
}

if (-e "$local_kernel_dir/initrd.img" && ! -l "$local_kernel_dir/initrd.img") {
    print "initrd file is not a symlink:  $local_kernel_dir/initrd.img\n";
    exit 1;
}

# Back up the original grub config file
system("cp $grub_cfg_file $grub_cfg_dir/orig_grub.cfg");
if ($? >> 8) {
    print "Couldn't back up original grub config file.\n";
    exit 1;
}

# Make temp copy to work on
$tmp_grub_cfg_file = $grub_cfg_file . ".tmp";

system("cp $grub_cfg_file $tmp_grub_cfg_file");
if ($? >> 8) {
    print "Couldn't back up temp copy of grub config file.\n";
    exit 1;
}

my $sedcmd="sed -i 's+linux $on_disk_kernel_dir\/vmlinuz-[^ ]* +linux $on_disk_kernel_dir\/vmlinuz +' $tmp_grub_cfg_file";

log_msg("Executing: $sedcmd \n");

system($sedcmd);
if ($? >> 8) {
    print "Couldn't edit linux entry in grub config file: $tmp_grub_cfg_file";
    exit 1;
}


$sedcmd="sed -i 's+initrd $on_disk_kernel_dir\/initrd.img-[^ ]*\$+initrd $on_disk_kernel_dir\/initrd.img +' $tmp_grub_cfg_file";

log_msg("Executing: $sedcmd \n");

system($sedcmd);
if ($? >> 8) {
    print "Couldn't edit initrd entry in grub config file: $tmp_grub_cfg_file";
    exit 1;
}

my $kern_vers=`ls $local_kernel_dir/vmlinuz-*`;

my @kern_vers_list = split(' ', $kern_vers);

if ($#kern_vers_list < 0) {
    print "No kernel binary files found in grub boot dir: $local_kernel_dir\n";
    exit 1;
}

log_msg("kern_vers_list before subst is: @kern_vers_list\n");

foreach (@kern_vers_list) {
    s/$local_kernel_dir\/vmlinuz-//;
}

log_msg("kern_vers_list after subst is: @kern_vers_list\n");

#
# Sort in reverse lexacographic order (highest version number first), and 
# then sort all images that match the type of kerenl we are 
# running (virt or non-virt) ahead of those that do not.

@kern_vers_list = sort(@kern_vers_list);

log_msg("kern_vers_list after sort is: @kern_vers_list\n");

my @p1;
my @p2;

my $running_kern = `uname -r`;

my $index;
for ($index = $#kern_vers_list; $index >= 0; $index--) {
    my $kv = $kern_vers_list[$index];
    if ($running_kern =~ /virt/) {
	if ($kv =~ /virt/) {
	    push @p1, $kv;
	} else {
	    push @p2, $kv;
	}
    } else { 
	if ($kv !~ /virt/)  {
	    push @p1, $kv;
	} else {
	    push @p2, $kv;
	}
    }
}

log_msg("p1 is: @p1\n");
log_msg("p2 is: @p2\n");

@kern_vers_list = @p1;
push(@kern_vers_list, @p2);

log_msg("kern_vers_list after subst and sort is: @kern_vers_list\n");


# Search sorted list to find first version that has both a kernel and
# an initrd file, then make the symlinks point to those files.
foreach my $vers (@kern_vers_list) {
    if (-e "$local_kernel_dir/vmlinuz-$vers" && 
	-e "$local_kernel_dir/initrd.img-$vers") {
	log_msg("Using version $vers\n");

	# Up to this point, this script has done nothing destructive.  Any
	# failures in which the script exited will leave grub directory and
	# config file un-modified.  Failures after this point could leave
	# grub directory or config file in an inconsistent state, leaving
	# the system un-bootable.

	system("rm -f $local_kernel_dir/vmlinuz");
	if ($? >> 8) {
	    print "Couldn't remove kernel symlink: $local_kernel_dir/vmlinuz-$vers\n";
	    # If symlink actually wasn't removed, grub dir will remain
	    # in previous state.
	    exit 1;
	}

	system("ln -s vmlinuz-$vers $local_kernel_dir/vmlinuz");
	if ($? >> 8) {
	    print "Couldn't symlink kernel binary: $local_kernel_dir/vmlinuz-$vers\n";
	    exit 1;
	}
	
	system("rm -f $local_kernel_dir/initrd.img");
	if ($? >> 8) {
	    print "Couldn't remove initrd symlink: $local_kernel_dir/initrd-$vers\n";
	    exit 1;
	}

	system("ln -s initrd.img-$vers $local_kernel_dir/initrd.img");
	if ($? >> 8) {
	    print "Couldn't symlink initrd file: $local_kernel_dir/initrd.img-$vers\n";
	    exit 1;
	}

	# As final step, move our edited grub config file back into position
	system("mv $tmp_grub_cfg_file $grub_cfg_file");
	if ($? >> 8) {
	    print "Couldn't move edited grub config file into position: $grub_cfg_file\n";
	    exit 1;
	}

	system("rm -f $tmp_grub_cfg_file");

	# Success!
	print "Done.\n";
	exit 0;
    }
}

print "Couldn't find matching vmlinuz and initrd.img files!\n";
exit 1;
