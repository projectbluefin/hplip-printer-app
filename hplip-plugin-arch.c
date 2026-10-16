// SPDX-License-Identifier: Apache-2.0
//
// Stage the proprietary HPLIP plugin's dynamic-link libraries for the build
// architecture. Extracted from hplip_install_plugin() in hplip-printer-app.c
// so the architecture matching can be unit-tested without PAPPL, libcurl, a
// plugin download, or a container image. See hplip-plugin-arch.h.

#include "hplip-plugin-arch.h"

#include <dirent.h>
#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int
hplip_stage_plugin_libs(const char *plugin_dir, const char *arch)
{
  char path[1024];
  DIR *d;
  struct dirent *entry;
  char *p;
  int len, matches = 0;

  // plugin_dir is the directory which holds the staged "plugin_tmp" folder,
  // exactly as hplip_install_plugin() passes it.
  len = snprintf(path, sizeof(path), "%s/plugin_tmp", plugin_dir);
  if (len < 0)
    return -1;
  if ((size_t)len >= sizeof(path))
  {
    errno = ENAMETOOLONG;
    return -1;
  }

  d = opendir(path);
  if (d == NULL)
    return -1;

  // Build "<plugin_dir>/plugin_tmp/" so each symlink is created inside the
  // staging folder, next to the library it names.
  if ((size_t)len + 1 >= sizeof(path))
  {
    closedir(d);
    errno = ENAMETOOLONG;
    return -1;
  }
  path[len] = '/';
  len ++;

  while ((entry = readdir(d)) != NULL)
  {
    if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, ".."))
      continue;

    // Match "<component>-<arch>.so": the architecture label has to be a
    // whole tag, bounded by a "-" before it and ".so" after it, so a
    // component name which merely contains the letters is never staged.
    if ((p = strstr(entry->d_name, arch)) != NULL &&
	p > entry->d_name && *(p - 1) == '-' &&
	strncmp(p + strlen(arch), ".so", 3) == 0)
    {
      // The link name is the vendor name minus "-<arch>"; refuse it rather
      // than write past the end of path when the two do not fit together.
      if ((size_t)len + strlen(entry->d_name) - strlen(arch) - 1 >=
          sizeof(path))
      {
        closedir(d);
        errno = ENAMETOOLONG;
        return -1;
      }

      // "<component>-<arch>.so" -> "<component>.so"
      memmove(path + len, entry->d_name, (p - entry->d_name) - 1);
      memmove(path + len + (p - entry->d_name) - 1, p + strlen(arch),
	      strlen(p + strlen(arch)) + 1);
      if (symlink(entry->d_name, path) != 0)
      {
        // Keep symlink()'s errno for the caller's log, not closedir()'s.
        int saved_errno = errno;

        closedir(d);
        errno = saved_errno;
        return -1;
      }
      matches ++;
    }
  }

  closedir(d);
  return matches;
}
