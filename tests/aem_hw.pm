# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2024 3mdeb Sp. z o.o.
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

use base "installedtest";
use strict;
use testapi;
use serial_terminal;
use Data::Dumper;

# AEM is installed without SRK password for simplicity.
#
# How it runs
# -----------
#
# If TEST_AEM_HW equals "setup":
#     Install the system and shut it down. Separate test suite for clarity.
# If TEST_AEM_HW equals "first-run":
#     Check that AEM sealed secret successfully.
# If TEST_AEM_HW equals "second-run":
#     Check that AEM unsealed secret successfully and dump TPM event log.
#
# This is done to work around Xen having issues with rebooting the
# machine (passing it "reboot=" didn't help).
#
# Variables for TEST_AEM_HW=setup stage
# -------------------------------------
#
# PACKAGES_BASE_URL - where to look for AEM-related packages.
# AEM_VER           - version of "anti-evil-maid" package
# GRUB_VER          - version of "grub2-*" packages
# XEN_VER           - version of "xen-*" packages

# values of these are likely to match on different hardware, but
# they are generally machine-specific, so don't assume anything
my $boot_disk;
my $boot_part;
if (check_var('MACHINE', 'optiplex')) {
    $boot_disk = '/dev/sda';
    $boot_part = '/dev/sda1';
} else {
    die "Don't know disk and partition names for '@{[ get_var('MACHINE') ]}' machine!";
}

sub run {
    my ($self) = @_;

    if (check_var('TEST_AEM_HW', 'setup')) {
        get_var('PACKAGES_BASE_URL') or die "PACKAGES_BASE_URL not set!";
        get_var('AEM_VER') or die "AEM_VER not set!";
        get_var('GRUB_VER') or die "GRUB_VER not set!";
        get_var('XEN_VER') or die "XEN_VER not set!";

        clear_tpm();

        # using this to support re-installing AEM
        wait_serial 'Welcome to GRUB!';
        send_key 'end';
        send_key 'up';
        send_key 'ret';

        handle_luks_pass();
        wait_for_startup();

        # too much logging is causing `xl dmesg` to start dropping lines from the
        # top, which results in anti-evil-maid-dump-evt-log failing to find event
        # log
        assert_script_run "sed -i -e 's/ guest_loglvl=all//' /etc/default/grub";

        setup_acm();
        send_packages();
        install_packages();
        setup_aem();
    } elsif (check_var('TEST_AEM_HW', 'first-run')) {
        # first reboot:
        #  - tries to unseal the secret, but fails (this isn't asserted)
        #  - seals the secret successfully
        assert_screen ["bootloader", "luks-prompt"], timeout => 180;
        handle_luks_pass();
        assert_screen "aem-secret.txt-sealed", timeout => 60;
        wait_for_startup();
    } elsif (check_var('TEST_AEM_HW', 'second-run')) {
        # second reboot:
        #  - unseals the secret successfully
        #  - seals the secret successfully
        handle_aem_startup();
        handle_luks_pass();
        assert_screen "aem-secret.txt-sealed", timeout => 60;
        wait_for_startup();

        # collect event log dump
        assert_script_run('anti-evil-maid-dump-evt-log');
    }

    # help it finish gracefully
    assert_script_run('sync');
    assert_script_run('poweroff');
    sleep 10;
}

sub clear_tpm {
    # this is for SeaBIOS

    # enter boot menu
    wait_serial 'Press ESC for boot menu.';
    send_key 'esc';

    # enter TPM menu
    wait_serial 'Select boot device:';
    send_key 't';

    my $owned = wait_serial qr/Ownership has( not)? been taken/, 5;
    if (!defined $owned) {
        die "Failed to check TPM ownership status in TPM menu of SeaBIOS.";
    } elsif ($owned =~ 'Ownership has not been taken') {
        # exit TPM menu
        send_key 'esc';
    } else {
        # reset the TPM, to allow taking ownership
        wait_serial 'c. Clear ownership';
        send_key 'c';
        wait_serial 'e. Enable the TPM';
        send_key 'e';
        wait_serial 'a. Activate the TPM';
        send_key 'a';
    }

    # at this point the machine reboots
}

sub run_cmd {
    print "Executing: `@_`\n";
    my $code = system(@_);
    print "Exit code: $code\n";
    return $code;
}

sub run_scp_to_sut {
    my @cmd = ('sshpass', '-puserpass', 'scp', '-q', '-oStrictHostKeyChecking=no', '-oUserKnownHostsFile=/dev/null');
    push @cmd, @_;
    push @cmd, "root\@@{[ get_var('QUBES_OS_HOST_IP') ]}:";
    return run_cmd(@cmd);
}

sub setup_acm {
    my $url = 'https://cdrdv2.intel.com/v1/dl/getContent/630744';
    my $zip_root = '630744_003';
    my $zip_fname = "$zip_root.zip";

    my $bin_fname;
    if (check_var('MACHINE', 'optiplex')) {
        $bin_fname = 'SNB_IVB_SINIT_20190708_PW.bin';
    } else {
        die "Don't know which ACM to use for '@{[ get_var('MACHINE') ]}' machine!";
    }

    if (run_cmd('wget', '-O', $zip_fname, $url) != 0) {
        die "Failed to download '$url'";
    }

    if (run_scp_to_sut($zip_fname) != 0) {
        die "Failed to send ACM to DUT";
    }

    assert_script_run("unzip -o '$zip_fname'");
    assert_script_run("cp --update '$zip_root/$bin_fname' /boot");
}

sub send_packages {
    my $base_url = get_var('PACKAGES_BASE_URL');
    my $aem_ver = get_var('AEM_VER');
    my $grub_ver = get_var('GRUB_VER');
    my $xen_ver = get_var('XEN_VER');
    my @packages = (
        "anti-evil-maid-$aem_ver.fc37.x86_64.rpm",
        "grub2-common-$grub_ver.fc37.noarch.rpm",
        "grub2-pc-$grub_ver.fc37.x86_64.rpm",
        "grub2-pc-modules-$grub_ver.fc37.noarch.rpm",
        "grub2-tools-$grub_ver.fc37.x86_64.rpm",
        "grub2-tools-extra-$grub_ver.fc37.x86_64.rpm",
        "grub2-tools-minimal-$grub_ver.fc37.x86_64.rpm",
        "python3-xen-$xen_ver.fc37.x86_64.rpm",
        "xen-$xen_ver.fc37.x86_64.rpm",
        "xen-hypervisor-$xen_ver.fc37.x86_64.rpm",
        "xen-libs-$xen_ver.fc37.x86_64.rpm",
        "xen-licenses-$xen_ver.fc37.x86_64.rpm",
        "xen-runtime-$xen_ver.fc37.x86_64.rpm",
    );

    my @files;
    for my $i (0 .. $#packages) {
        my $package = $packages[$i];
        my $url = "$base_url/$package";
        if (run_cmd('wget', '-O', $package, $url) != 0) {
            die "Failed to download '$url'";
        }
        push @files, $package;
    }

    if (run_scp_to_sut(@files) != 0) {
        die "Failed to send packages to DUT";
    }

    unlink @files or die "Failed to delete some of downloaded files: $!";
}

sub install_packages {
    my @extra_deps = (
        'oathtool',
        'openssl',
        'qrencode',
        'tpm-extra',
        'trousers-changer',
        'tpm-tools',
    );
    my @to_install = (
        './python3-xen-*.rpm',
        './xen-*.rpm',
        './xen-hypervisor-*.rpm',
        './xen-libs-*.rpm',
        './xen-licenses-*.rpm',
        './xen-runtime-*.rpm',
        './grub2-tools-extra-*.rpm',
    );
    my @to_reinstall = (
        './grub2-common-*.rpm',
        './grub2-pc-*.rpm',
        './grub2-pc-modules-*.rpm',
        './grub2-tools-*.rpm',
        './grub2-tools-minimal-*.rpm',
    );

    assert_script_run("qubes-dom0-update --enablerepo=qubes-dom0-current-testing -y @extra_deps");
    assert_script_run("dnf install -y @to_install");
    assert_script_run("dnf reinstall -y @to_reinstall");
}

sub setup_aem {
    # cleanup in case AEM was previously initialized (useful for debugging this test)
    assert_script_run('rm -rf /var/lib/anti-evil-maid/aem');

    assert_script_run("grub2-install $boot_disk");
    assert_script_run('dnf install -y ./anti-evil-maid-*.rpm');
    assert_script_run('anti-evil-maid-tpm-setup -z');
    assert_script_run("anti-evil-maid-install $boot_part");

    assert_script_run('echo "really big secret" > /var/lib/anti-evil-maid/aem/secret.txt');
}

sub handle_luks_pass {
    assert_screen "luks-prompt", timeout => 180;
    type_string "lukspass\n";
}

sub wait_for_startup {
    assert_screen "login-prompt-user-selected", timeout => 90;
    select_root_console();
}

sub handle_aem_startup {
    assert_screen "aem-good-secret", timeout => 180;
    send_key "ret";
}

sub test_flags {
    # without anything - rollback to 'lastgood' snapshot if failed
    # 'fatal' - whole test suite is in danger if this fails
    # 'milestone' - after this test succeeds, update 'lastgood'
    # 'important' - if this fails, set the overall state to 'fail'
    return { important => 1 };
}

sub post_run_hook {
    my $self = shift;
}

sub post_fail_hook {
    my $self = shift;
    # don't bother collecting various logs
}

1;

# vim: set sw=4 et:
