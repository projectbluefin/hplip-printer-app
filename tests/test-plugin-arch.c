// SPDX-License-Identifier: Apache-2.0
//
// Unit tests for hplip_stage_plugin_libs() in hplip-plugin-arch.c.
//
// The architecture matching lives in the Printer Application's plugin install
// path, where the vendor archive's "<component>-<ARCH>.so" libraries are
// symlinked to "<component>.so" for the build architecture. This test builds
// the real module against a temp directory of fake vendor libraries and
// checks that the right libraries are staged for each release architecture
// (x86_64 for the amd64 release, arm64 for the arm64 release) and that
// mismatched-arch libraries are rejected - the behaviour issue #14 asks to
// verify. It needs only libc, so it builds without PAPPL or libcurl.
//
// Usage: compiled into a single binary by tests/run-plugin-arch-tests.sh.

#include "hplip-plugin-arch.h"

#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static int checks = 0;
static int failures = 0;

static void
check(const char *what, int condition)
{
  checks ++;
  if (condition)
    printf("ok: %s\n", what);
  else
  {
    failures ++;
    printf("FAIL: %s\n", what);
  }
}

// Create a file with some bytes in it, so the "vendor library" is a real file
// that a symlink can point at.
static void
make_vendor_file(const char *dir, const char *name)
{
  char path[4096];
  FILE *f;

  snprintf(path, sizeof(path), "%s/%s", dir, name);
  f = fopen(path, "wb");
  if (f == NULL)
  {
    fprintf(stderr, "cannot create %s\n", path);
    exit(2);
  }
  fputs("vendor plugin object\n", f);
  fclose(f);
}

// Check that "<plugin_tmp>/<name>" is a symlink whose target is exactly
// "<target>", the vendor file hplip_stage_plugin_libs() should link it to.
static void
expect_link(const char *plugin_tmp, const char *name, const char *target)
{
  char link[1024];
  char got[1024];
  char what[1024];
  ssize_t n;

  snprintf(link, sizeof(link), "%s/%s", plugin_tmp, name);
  n = readlink(link, got, sizeof(got) - 1);
  if (n >= 0)
    got[n] = '\0';
  snprintf(what, sizeof(what), "%s -> %s", name, target);
  check(what, n >= 0 && strcmp(got, target) == 0);
}

// Check that nothing named "<plugin_tmp>/<name>" was created.
static void
expect_absent(const char *plugin_tmp, const char *name)
{
  char link[1024];
  char what[1024];
  struct stat st;

  snprintf(link, sizeof(link), "%s/%s", plugin_tmp, name);
  snprintf(what, sizeof(what), "%s is not staged", name);
  check(what, lstat(link, &st) != 0);
}

// Count every symlink in plugin_tmp, so an unexpected one (a mismatched-arch
// library) is caught even when no check names it.
static int
count_links(const char *plugin_tmp)
{
  DIR *d;
  struct dirent *entry;
  int links = 0;

  d = opendir(plugin_tmp);
  if (d == NULL)
    return -1;
  while ((entry = readdir(d)) != NULL)
  {
    char path[4096];
    struct stat st;

    snprintf(path, sizeof(path), "%s/%s", plugin_tmp, entry->d_name);
    if (lstat(path, &st) == 0 && S_ISLNK(st.st_mode))
      links ++;
  }
  closedir(d);
  return links;
}

// Create "<plugin_dir>/plugin_tmp" under /tmp for one test case.
static void
make_plugin_dir(char *plugin_dir, size_t dirsize, char *plugin_tmp,
                size_t tmpsize, const char *label)
{
  snprintf(plugin_dir, dirsize, "/tmp/hplip-arch-%s-XXXXXX", label);
  if (mkdtemp(plugin_dir) == NULL) { perror("mkdtemp"); exit(2); }
  snprintf(plugin_tmp, tmpsize, "%s/plugin_tmp", plugin_dir);
  if (mkdir(plugin_tmp, 0755) != 0) { perror("mkdir"); exit(2); }
}

// amd64 release: the vendor archive tags libraries with the "x86_64" label.
static void
test_x86_64(void)
{
  char plugin_dir[256];
  char plugin_tmp[512];
  int rc;

  make_plugin_dir(plugin_dir, sizeof(plugin_dir), plugin_tmp,
                  sizeof(plugin_tmp), "x86_64");

  make_vendor_file(plugin_tmp, "hpcups-x86_64.so");
  make_vendor_file(plugin_tmp, "hp-scan-x86_64.so");
  make_vendor_file(plugin_tmp, "hp-versioned-x86_64.so.3.22.10");
  make_vendor_file(plugin_tmp, "hpcups-arm64.so");
  make_vendor_file(plugin_tmp, "hp-scan-arm32.so");
  make_vendor_file(plugin_tmp, "hp-x86_32.so");
  make_vendor_file(plugin_tmp, "hp-only-arm64.so");
  make_vendor_file(plugin_tmp, "hpcups-x86_64.txt");
  // The arch label must be a whole "-<arch>" tag, not a substring.
  make_vendor_file(plugin_tmp, "hpscanx86_64.so");

  rc = hplip_stage_plugin_libs(plugin_dir, "x86_64");
  check("x86_64 release stages exactly its three libraries", rc == 3);
  check("x86_64 release leaves exactly three symlinks",
        count_links(plugin_tmp) == 3);

  expect_link(plugin_tmp, "hpcups.so", "hpcups-x86_64.so");
  expect_link(plugin_tmp, "hp-scan.so", "hp-scan-x86_64.so");
  // The version suffix after ".so" is kept on the link name.
  expect_link(plugin_tmp, "hp-versioned.so.3.22.10",
              "hp-versioned-x86_64.so.3.22.10");

  // A component which exists only as an arm64 library must not be staged
  // for the x86_64 release.
  expect_absent(plugin_tmp, "hp-only.so");
  expect_absent(plugin_tmp, "hp.so");
}

// arm64 release: the vendor archive tags libraries with the "arm64" label.
static void
test_arm64(void)
{
  char plugin_dir[256];
  char plugin_tmp[512];
  int rc;

  make_plugin_dir(plugin_dir, sizeof(plugin_dir), plugin_tmp,
                  sizeof(plugin_tmp), "arm64");

  make_vendor_file(plugin_tmp, "hpcups-arm64.so");
  make_vendor_file(plugin_tmp, "hp-scan-x86_64.so");
  make_vendor_file(plugin_tmp, "hp-arm32.so");

  rc = hplip_stage_plugin_libs(plugin_dir, "arm64");
  check("arm64 release stages exactly its one library", rc == 1);
  check("arm64 release leaves exactly one symlink",
        count_links(plugin_tmp) == 1);

  expect_link(plugin_tmp, "hpcups.so", "hpcups-arm64.so");
  expect_absent(plugin_tmp, "hp-scan.so");
  expect_absent(plugin_tmp, "hp.so");
}

// A vendor bundle which lacks this architecture entirely (the ARM-only-partial
// case) must report zero matches, not stage anything and not error.
static void
test_no_match(void)
{
  char plugin_dir[256];
  char plugin_tmp[512];

  make_plugin_dir(plugin_dir, sizeof(plugin_dir), plugin_tmp,
                  sizeof(plugin_tmp), "none");

  make_vendor_file(plugin_tmp, "hpcups-arm64.so");

  check("no x86_64 libraries yields a match count of 0",
        hplip_stage_plugin_libs(plugin_dir, "x86_64") == 0);
  check("nothing is staged when nothing matches",
        count_links(plugin_tmp) == 0);
  expect_absent(plugin_tmp, "hpcups.so");
}

// A plugin_dir long enough that "<plugin_dir>/plugin_tmp/<link name>" no
// longer fits the staging path buffer must be refused with ENAMETOOLONG, not
// written past the end of that buffer.
static void
test_long_plugin_dir(void)
{
  char plugin_dir[4096];
  char plugin_tmp[4200];
  int rc;

  snprintf(plugin_dir, sizeof(plugin_dir), "/tmp/hplip-arch-long-XXXXXX");
  if (mkdtemp(plugin_dir) == NULL) { perror("mkdtemp"); exit(2); }

  // Nest directories (each name well under NAME_MAX) until plugin_dir is
  // 1000 bytes long: "/plugin_tmp/" still fits, the vendor name does not.
  while (strlen(plugin_dir) < 1000)
  {
    size_t used = strlen(plugin_dir), add = 1000 - used;

    if (add > 101)
      add = 101;
    plugin_dir[used] = '/';
    memset(plugin_dir + used + 1, 'a', add - 1);
    plugin_dir[used + add] = '\0';
    if (mkdir(plugin_dir, 0755) != 0) { perror("mkdir"); exit(2); }
  }

  snprintf(plugin_tmp, sizeof(plugin_tmp), "%s/plugin_tmp", plugin_dir);
  if (mkdir(plugin_tmp, 0755) != 0) { perror("mkdir"); exit(2); }
  make_vendor_file(plugin_tmp, "hpcups-component-with-a-long-name-x86_64.so");

  errno = 0;
  rc = hplip_stage_plugin_libs(plugin_dir, "x86_64");
  check("an over-long link path is refused with -1", rc == -1);
  check("an over-long link path reports ENAMETOOLONG",
        errno == ENAMETOOLONG);
  check("nothing is staged for an over-long link path",
        count_links(plugin_tmp) == 0);
}

int
main(void)
{
  test_x86_64();
  test_arm64();
  test_no_match();
  test_long_plugin_dir();

  printf("\n%d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
