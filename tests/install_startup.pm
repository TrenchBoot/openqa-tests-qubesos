# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2018 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use base 'basetest';
use strict;
use testapi;
use bootloader_setup;
use serial_terminal qw(select_root_console);
use utils qw(assert_fuzzy_serial assert_serial);

sub run {
    pre_bootmenu_setup();

    if (check_var('BACKEND', 'qemu')) {
        if (check_var('UEFI', '1')) {
            if (check_var('UEFI_DIRECT', '1')) {
                # grub2-efi can't load xen.efi on OVMF...
                # default direct xen.efi boot is also broken on OVMF - see below
                tianocore_select_bootloader();
                send_key_until_needlematch('tianocore-menu-efi-shell', 'up', 5, 5);
                send_key 'ret';
                send_key 'esc';
                type_string "fs0:\n";
                # in direct UEFI boot we enable /mapbs workaround, which crashes dom0
                # under OVMF - choose different boot option than default (qubes-verbose)
                type_string "EFI\\BOOT\\BOOTX64.efi qubes\n";
            } else {
                assert_screen 'bootloader', 30;
                if (check_var('KERNEL_VERSION', 'latest')) {
                    # verbose
                    send_key 'down';
                    # rescue
                    send_key 'down';
                    # kernel latest
                    send_key 'down';
                } else {
                    send_key 'up';
                }
                # press enter to boot right away
                send_key 'ret';
            }
        } else {
            # wait for bootloader to appear
            assert_screen 'bootloader', 30;

            # skip media verification
            if (check_var('KERNEL_VERSION', 'latest')) {
                if (check_var('VERSION', '4.1')) {
                    # isolinux menu
                    # troubleshooting
                    send_key 'down';
                    send_key 'ret';
                    assert_screen 'bootloader-troubleshooting';
                    # kernel latest
                    send_key 'down';
                } else {
                    # grub menu
                    # verbose
                    send_key 'down';
                    # rescue
                    send_key 'down';
                    # kernel latest
                    send_key 'down';
                }
            } else {
                send_key 'up';
            }

            # press enter to boot right away
            send_key 'ret';
        }
    } elsif (check_var('HEADS', '1')) {
        heads_boot_usb;
    } elsif (check_var('MACHINE', 'optiplex')) {
        # http://<openqa-ip>:8080/iso/     -- mounted ISO image
        # http://<openqa-ip>:8080/ipxe     -- iPXE script
        # http://<openqa-ip>:8080/ipxe.pxe -- full-featured iPXE binary in PXE format
        # http://<openqa-ip>:8080/ks.cfg   -- KickStart configuration file

        my $openqa_url = get_var('QUBES_OS_OPENQA_URL');

        setup_ipxe_prompt();

        # download and give control to a full-featured iPXE binary in PXE format
        type_string "chain $openqa_url/ipxe.pxe\n";

        setup_ipxe_prompt();

        # start QubesOS by processing instructions from iPXE script file
        type_string "chain $openqa_url/ipxe\n";
    } elsif (check_var('MACHINE', 'supermicro')) {
        # http://<openqa-ip>:8080/iso/     -- mounted ISO image
        # http://<openqa-ip>:8080/ipxe     -- iPXE script
        # http://<openqa-ip>:8080/ks.cfg   -- KickStart configuration file
        #
        # grub-mixed.img image connected to PiKVM.  TODO: automate via API.

        my $menu_title = 'Please select boot device:';
        # spaces are intentional to no pick up UEFI entry (could also use regexp for wait_serial)
        my $entry_text = 'PiKVM CD-ROM Drive 0601    ';

        my $menu = undef;
        for my $i (0 .. 45) {
            send_key 'f11';
            $menu = wait_serial($entry_text, 1);
            if (defined $menu) {
                last;
            }
        }

        if (!defined $menu) {
            die "Failed to find menu containing CSM PiKVM entry";
        }

        # splitting by bars instead of newlines because there are no newlines
        # in the menu drawn via escape sequences
        my @menu_parts = split '\|', $menu;

        my $menu_top = 0;
        while ($menu_parts[$menu_top] !~ $menu_title) {
            ++$menu_top;
        }

        my $pikvm_entry = $menu_top + 1;
        while ($menu_parts[$pikvm_entry] !~ $entry_text) {
            ++$pikvm_entry;
        }

        # it's `+ 4` and `+= 2` because each menu line contains 2 bars
        for (my $i = $menu_top + 4; $i < $pikvm_entry; $i += 2) {
            send_key 'down';
        }
        send_key 'ret';

        # GRUB2 should be booting from iPXE automatically.
    } elsif (check_var('MACHINE', 'supermicro')) { # EFI version, saved for later, never gets executed
        # http://<openqa-ip>:8080/iso/     -- mounted ISO image
        # http://<openqa-ip>:8080/ipxe     -- iPXE script
        # http://<openqa-ip>:8080/ks.cfg   -- KickStart configuration file

        my $openqa_url = get_var('QUBES_OS_OPENQA_URL');

        for my $i (0 .. 45) {
            send_key 'f11';
            if (wait_serial('select boot device', 1)) {
                last;
            }
        }
        send_key 'down';
        send_key 'ret';

        assert_serial "Shell>", 30;
        type_string "fs0:\n";
        wait_serial "FS0:", 30;
        type_string "efi\\boot\\ipxe.efi dhcp && chain $openqa_url/ipxe\n";
    } elsif (!check_var('QUBES_OS_KS_URL', '')) {
        my $ks_url = get_var('QUBES_OS_KS_URL');

        # wait for bootloader to appear
        assert_screen 'bootloader', 30;

        # skip media verification and edit boot parameters
        # select boot entry without media verification
        send_key 'up';
        # start editing it
        send_key 'e';
        # go to the line with kernel parameters
        send_key 'down';
        send_key 'down';
        send_key 'down';
        send_key 'end';
        # append them
        type_string " inst.sshd inst.ks=$ks_url";
        # boot
        send_key 'f10';
    }

    # wait for the installer welcome screen to appear
    assert_screen 'installer', 360;

    if (match_has_tag('installer-inactive')) {
        mouse_set(10, 10);
        mouse_click();
        mouse_hide();
    }

    if (check_var("BACKEND", "qemu")) {
        # get console on hvc1 too
        select_console('install-shell');
        type_string("systemctl start anaconda-shell\@hvc1\n");
        select_console('installation', await_console=>0);
    }

    if (check_var("MACHINE", "hw7")) {
        select_root_console();
        # broken RTC? battery dead?
        script_run("date -s @" . time());
        script_run("hwclock -w");
        select_console('installation', await_console=>0);
    }
}

sub setup_ipxe_prompt {
    # send Ctrl-B proactively
    send_key 'ctrl-b';
    send_key 'ctrl-b';
    send_key 'ctrl-b';
    send_key 'ctrl-b';
    send_key 'ctrl-b';

    assert_serial "Press Ctrl-B", 30;

    # enter iPXE command-line
    send_key 'ctrl-b';
    send_key 'ctrl-b';
    send_key 'ctrl-b';
    send_key 'ctrl-b';
    send_key 'ctrl-b';

    assert_fuzzy_serial "iPXE>", 10;
    type_string "dhcp\n";
    assert_fuzzy_serial "iPXE>";
}

sub test_flags {
    # 'fatal'          - abort whole test suite if this fails (and set overall state 'failed')
    # 'ignore_failure' - if this module fails, it will not affect the overall result at all
    # 'milestone'      - after this test succeeds, update 'lastgood'
    # 'norollback'     - don't roll back to 'lastgood' snapshot if this fails
    return { fatal => 1 };
}

sub post_fail_hook {

    # hide plymouth if any
    send_key "esc";
    save_screenshot;

};

1;

# vim: set sw=4 et:

