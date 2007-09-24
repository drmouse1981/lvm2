#!/bin/sh
# Copyright (C) 2007 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing to use,
# modify, copy, or redistribute it subject to the terms and conditions
# of the GNU General Public License v.2.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation,
# Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

test_description='Check extents percentage arguments'
privileges_required_=1

. ./test-lib.sh

cleanup_()
{
  test -n "$vg" && {
    vgchange -an "$vg"
    lvremove -ff "$vg"
    vgremove -f "$vg"
  } > "$test_dir_/cleanup.log"
  test -n "$d1" && losetup -d "$d1"
  test -n "$d2" && losetup -d "$d2"
  rm -f "$f1" "$f2"
}

test_expect_success \
  'set up temp files, loopback devices, PVs, and a VG' \
  'f1=$(pwd)/1 && d1=$(loop_setup_ "$f1") &&
   f2=$(pwd)/2 && d2=$(loop_setup_ "$f2") &&
   pvcreate $d1 $d2      &&
   vg=$(this_test_)-test-vg-$$  &&
   vgcreate $vg $d1 $d2 &&
   lv=$(this_test_)-test-lv-$$ &&
   lvcreate -L 64M -n $lv $vg'

test_expect_success \
  'lvextend rejects both size and extents without PVs' \
  'lvextend -l 10 -L 64M $vg/$lv 2>err; test $? = 3 &&
   grep "^  Please specify either size or extents but not both.\$" err'

test_expect_success \
  'lvextend rejects both size and extents with PVs' \
  'lvextend -l 10 -L 64M $vg/$lv $d1 2>err; test $? = 3 &&
   grep "^  Please specify either size or extents but not both.\$" err'

test_expect_success \
  'lvextend accepts no size or extents but one PV - bz154691' \
  'lvextend $vg/$lv $d1 >out; test $? = 0 &&
  grep "^  Logical volume $lv successfully resized\$" out &&
  check_pv_size_ $d1 "0"'

test_expect_success \
  'Reset LV to original size' \
  'lvremove -f $vg/$lv; test $? = 0 &&
   lvcreate -L 64M -n $lv $vg; test $? = 0'

test_expect_success \
  'lvextend accepts no size but extents 100%PVS and two PVs - bz154691' \
  'lvextend -l +100%PVS $vg/$lv $d1 $d2 >out; test $? = 0 &&
  grep "^  Logical volume $lv successfully resized\$" out &&
  check_pv_size_ $d1 "0" &&
  check_pv_size_ $d2 "0"'

# Exercise the range overlap code.  Allocate every 2 extents.
#
#      Physical Extents
#           1         2
#012345678901234567890123
#
#aaXXaaXXaaXXaaXXaaXXaaXX - (a)llocated
#rrrXXXrrrXXXrrrXXXrrrXXX - (r)ange on cmdline
#ooXXXXXXoXXXooXXXXXXoXXX - (o)verlap of range and allocated
#
# Key: a - allocated
#      F - free
#      r - part of a range on the cmdline
#      N - not on cmdline
#
# Create the LV with 12 extents, allocated every other 2 extents.
# Then extend it, with a range of PVs on the cmdline of every other 3 extents.
# Total number of extents should be 12 + overlap = 12 + 6 = 18.
# Thus, total size for the LV should be 18 * 4M = 72M
#
test_expect_success \
  'Reset LV to 12 extents, allocate every other 2 extents' \
  'create_pvs=`for i in $(seq 0 4 20); do echo -n "\$d1:$i-$(($i + 1)) "; done` &&
   lvremove -f $vg/$lv; test $? = 0 &&
   lvcreate -l 12 -n $lv $vg $create_pvs; test $? = 0'

test_expect_success \
  'lvextend with partially allocated PVs and extents 100%PVS with PE ranges' \
  'extend_pvs=`for i in $(seq 0 6 18); do echo -n "\$d1:$i-$(($i + 2)) "; done` &&
  lvextend -l +100%PVS $vg/$lv $extend_pvs >out; test $? = 0 &&
  grep "^  Logical volume $lv successfully resized\$" out &&
  check_lv_size_ $vg/$lv "72.00M"'


test_done
# Local Variables:
# indent-tabs-mode: nil
# End:
