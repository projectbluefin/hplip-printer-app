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

// Accepted ranges for the overrides.  A non-positive connect or total
// bound would mean "wait forever", and a non-positive stall bound would
// turn the stall check off, so neither is accepted.

#define HPLIP_DOWNLOAD_CONNECT_TIMEOUT_MAX 3600L
#define HPLIP_DOWNLOAD_TOTAL_TIMEOUT_MAX   86400L
#define HPLIP_DOWNLOAD_STALL_LIMIT_MAX     1073741824L
#define HPLIP_DOWNLOAD_STALL_TIME_MAX      86400L

typedef struct hplip_download_policy_s
{
  long connect_timeout;		// Seconds allowed to establish the connection
  long total_timeout;		// Seconds allowed for the whole transfer
  long stall_limit;		// Bytes per second below which ...
  long stall_time;		// ... the transfer is aborted after this long
  int  rejected;		// Number of invalid overrides which were ignored
} hplip_download_policy_t;

//
// Functions...
//

extern void	hplip_download_policy_defaults(
		    hplip_download_policy_t *policy);

extern void	hplip_download_policy_from_env(
		    hplip_download_policy_t *policy);

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
