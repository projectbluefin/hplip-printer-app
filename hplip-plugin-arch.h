// SPDX-License-Identifier: Apache-2.0
#ifndef HPLIP_PLUGIN_ARCH_H
#define HPLIP_PLUGIN_ARCH_H

// Stage the proprietary HPLIP plugin's dynamic-link libraries for the build
// architecture. HP's vendor archive tags each library
// "<component>-<ARCH>.so[.version]" where ARCH is one of "x86_32",
// "x86_64", "arm32", "arm64" - the same labels the Printer Application uses
// for its ARCH macro, not the OCI/Debian "amd64"/"arm64" triplets. This
// symlinks each library of the requested architecture to "<component>.so"
// inside the staged plugin_tmp directory, so the running application dlopens
// the right bits regardless of how the vendor bundle named its own arch tag.
//
// Returns the number of libraries staged, or -1 on a real error (a
// directory which cannot be opened, a symlink which cannot be created, or a
// link path longer than the 1024-byte limit, with errno ENAMETOOLONG).
// A return of 0 is not an error: it means the vendor bundle simply has no
// files for the requested architecture, which the caller turns into a loud
// refusal rather than a silently broken plugin.
int hplip_stage_plugin_libs(const char *plugin_dir, const char *arch);

#endif // HPLIP_PLUGIN_ARCH_H
