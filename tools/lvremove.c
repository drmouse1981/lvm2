/*
 * Copyright (C) 2001  Sistina Software
 *
 * LVM is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 *
 * LVM is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with LVM; see the file COPYING.  If not, write to
 * the Free Software Foundation, 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 */

#include "tools.h"

static int lvremove_single(struct cmd_context *cmd, struct logical_volume *lv,
			   void *handle)
{
	struct volume_group *vg;
	struct lvinfo info;

	vg = lv->vg;

	if (!(vg->status & LVM_WRITE)) {
		log_error("Volume group \"%s\" is read-only", vg->name);
		return ECMD_FAILED;
	}

	if (lv_is_origin(lv)) {
		log_error("Can't remove logical volume \"%s\" under snapshot",
			  lv->name);
		return ECMD_FAILED;
	}

	if (lv->status & LOCKED) {
		log_error("Can't remove locked LV %s", lv->name);
		return ECMD_FAILED;
	}

	/* FIXME Ensure not referred to by another existing LVs */

	if (lv_info(lv, &info)) {
		if (info.open_count) {
			log_error("Can't remove open logical volume \"%s\"",
				  lv->name);
			return ECMD_FAILED;
		}

		if (info.exists && !arg_count(cmd, force_ARG)) {
			if (yes_no_prompt("Do you really want to remove active "
					  "logical volume \"%s\"? [y/n]: ",
					  lv->name) == 'n') {
				log_print("Logical volume \"%s\" not removed",
					  lv->name);
				return 0;
			}
		}
	}

	if (!archive(vg))
		return ECMD_FAILED;

	if (!lock_vol(cmd, lv->lvid.s, LCK_LV_DEACTIVATE)) {
		log_error("Unable to deactivate logical volume \"%s\"",
			  lv->name);
		return ECMD_FAILED;
	}

	if (lv_is_cow(lv)) {
		log_verbose("Removing snapshot %s", lv->name);
		if (!vg_remove_snapshot(lv->vg, lv)) {
			stack;
			return ECMD_FAILED;
		}
	}

	log_verbose("Releasing logical volume \"%s\"", lv->name);
	if (!lv_remove(vg, lv)) {
		log_error("Error releasing logical volume \"%s\"", lv->name);
		return ECMD_FAILED;
	}

	/* store it on disks */
	if (!vg_write(vg))
		return ECMD_FAILED;

	backup(vg);

	if (!vg_commit(vg))
		return ECMD_FAILED;

	log_print("Logical volume \"%s\" successfully removed", lv->name);
	return 0;
}

int lvremove(struct cmd_context *cmd, int argc, char **argv)
{
	if (!argc) {
		log_error("Please enter one or more logical volume paths");
		return EINVALID_CMD_LINE;
	}

	return process_each_lv(cmd, argc, argv, LCK_VG_WRITE, NULL,
			       &lvremove_single);
}
