//
// Bounds for the HTTP transfers which fetch HP's proprietary plugin.
//
// The plugin installer runs synchronously inside the web admin request
// which triggered it, so a server which accepts a connection but never
// answers must not be able to hold that request open forever.  This
// module owns the connect, total, and stall bounds applied to every
// plugin download, and turns a libcurl failure into a sentence which
// can be shown to the user.
//
// Licensed under Apache License v2.0.  See the file "LICENSE" for more
// information.
//

#ifndef HPLIP_DOWNLOAD_POLICY_H
#define HPLIP_DOWNLOAD_POLICY_H

#include <curl/curl.h>
#include <stddef.h>

//
// Default bounds for a single plugin transfer.  HP's plugin archive is
// a few tens of megabytes, so the total bound is generous enough for a
// slow but working link while still being finite.
//

#define HPLIP_DOWNLOAD_CONNECT_TIMEOUT_DEFAULT 30L   // Seconds to connect
#define HPLIP_DOWNLOAD_TOTAL_TIMEOUT_DEFAULT   900L  // Seconds for everything
#define HPLIP_DOWNLOAD_STALL_LIMIT_DEFAULT     1024L // Bytes per second ...
#define HPLIP_DOWNLOAD_STALL_TIME_DEFAULT      60L   // ... for this long
#define HPLIP_DOWNLOAD_MAX_SIZE_DEFAULT        268435456L // Bytes, 256 MiB

//
// Per-transfer size caps.  The plugin index names the size of the
// plugin archive, so that transfer is capped at the size the index
// promised (never above HPLIP_DOWNLOAD_MAX_SIZE_DEFAULT or its
// override).  The index and the detached signature have no size
// announced anywhere, but both are a few kilobytes, so they get fixed
// caps far above anything HP has ever served.  Every cap is applied
// with CURLOPT_MAXFILESIZE: libcurl refuses a Content-Length above it
// before the body starts, and (libcurl 8.4.0 and later) also aborts a
// body of unknown length once it grows past it, so a server which
// never stops sending cannot fill the temporary directory.
//

#define HPLIP_DOWNLOAD_INDEX_MAX_SIZE     1048576L // Bytes, 1 MiB
#define HPLIP_DOWNLOAD_SIGNATURE_MAX_SIZE 65536L   // Bytes, 64 KiB

//
// Environment variables which override the defaults above.  They exist
// so that an operator can tune the bounds for an unusually slow or
// unusually fast mirror, and so that the test suite can exercise the
// bounds without waiting for the defaults to expire.  A value which is
// not a positive whole number, or which is outside the accepted range,
// is ignored and counted in 'rejected'.
//

#define HPLIP_DOWNLOAD_CONNECT_TIMEOUT_ENV "HPLIP_PLUGIN_CONNECT_TIMEOUT"
#define HPLIP_DOWNLOAD_TOTAL_TIMEOUT_ENV   "HPLIP_PLUGIN_TIMEOUT"
#define HPLIP_DOWNLOAD_STALL_LIMIT_ENV     "HPLIP_PLUGIN_STALL_LIMIT"
#define HPLIP_DOWNLOAD_STALL_TIME_ENV      "HPLIP_PLUGIN_STALL_TIME"
#define HPLIP_DOWNLOAD_MAX_SIZE_ENV        "HPLIP_PLUGIN_MAX_SIZE"

// Accepted ranges for the overrides.  A non-positive connect or total
// bound would mean "wait forever", a non-positive stall bound would
// turn the stall check off, and a non-positive size cap would mean "no
// cap", so none of those is accepted.  The size cap is a long for
// CURLOPT_MAXFILESIZE, so it stays below 2 GiB on every platform.

#define HPLIP_DOWNLOAD_CONNECT_TIMEOUT_MAX 3600L
#define HPLIP_DOWNLOAD_TOTAL_TIMEOUT_MAX   86400L
#define HPLIP_DOWNLOAD_STALL_LIMIT_MAX     1073741824L
#define HPLIP_DOWNLOAD_STALL_TIME_MAX      86400L
#define HPLIP_DOWNLOAD_MAX_SIZE_MAX        2147483647L

typedef struct hplip_download_policy_s
{
  long connect_timeout;		// Seconds allowed to establish the connection
  long total_timeout;		// Seconds allowed for the whole transfer
  long stall_limit;		// Bytes per second below which ...
  long stall_time;		// ... the transfer is aborted after this long
  long max_size;		// Bytes the transfer may deliver at most
  int  rejected;		// Number of invalid overrides which were ignored
} hplip_download_policy_t;

//
// Functions...
//

extern void	hplip_download_policy_defaults(
		    hplip_download_policy_t *policy);

extern void	hplip_download_policy_from_env(
		    hplip_download_policy_t *policy);

extern void	hplip_download_policy_cap_size(
		    hplip_download_policy_t *policy,
		    long max_size);

extern void	hplip_download_policy_apply(
		    CURL *curl,
		    const hplip_download_policy_t *policy);

extern void	hplip_download_policy_message(
		    CURLcode result,
		    const hplip_download_policy_t *policy,
		    int connected,
		    double elapsed,
		    char *buf,
		    size_t bufsize);

#endif // HPLIP_DOWNLOAD_POLICY_H
