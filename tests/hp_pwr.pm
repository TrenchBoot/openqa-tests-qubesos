# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2023 3mdeb Sp. z o.o.
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
use File::Path qw( remove_tree );
use testapi;
use serial_terminal;
use Data::Dumper;
use totp qw(generate_totp);

sub run {
    my ($self) = @_;

    handle_poweron();
    handle_luks_pass();
    wait_for_startup();

}