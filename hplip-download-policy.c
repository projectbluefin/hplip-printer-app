//
// Bounds for the HTTP transfers which fetch HP's proprietary plugin.
//
// Licensed under Apache License v2.0.  See the file "LICENSE" for more
// information.
//

#include "hplip-download-policy.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

//
// 'hplip_download_policy_env_long()' - Read a positive whole-number
//                                      override from the environment.
//
// Returns 'fallback' if the variable is unset, empty, not a whole
// number, or outside [minimum, maximum], and sets '*rejected' in those
// of the failing cases which were caused by a value the operator did
// supply.
//

static long					// O - Accepted or fallback value
hplip_download_policy_env_long(
    const char *name,				// I - Environment variable name
    long       fallback,			// I - Value to use if unusable
    long       minimum,				// I - Smallest accepted value
    long       maximum,				// I - Largest accepted value
    int        *rejected)			// O - Set on an unusable value
{
  const char	*value;				// Value of the variable
  char		*end = NULL;			// End of the parsed number
  long		parsed;				// Parsed value


  if ((value = getenv(name)) == NULL)
    return (fallback);

  // An empty value is treated as "not configured" rather than as an
  // error, so that an unset variable and an empty one behave alike.
  if (!value[0])
    return (fallback);

  errno  = 0;
  parsed = strtol(value, &end, 10);

  if (errno != 0 || end == value || *end != '\0' ||
      parsed < minimum || parsed > maximum)
  {
    (*rejected) ++;
    return (fallback);
  }

  return (parsed);
}


//
// 'hplip_download_policy_defaults()' - Set the built-in bounds.
//

void
hplip_download_policy_defaults(
    hplip_download_policy_t *policy)		// I - Policy to set
{
  if (!policy)
    return;

  policy->connect_timeout = HPLIP_DOWNLOAD_CONNECT_TIMEOUT_DEFAULT;
  policy->total_timeout   = HPLIP_DOWNLOAD_TOTAL_TIMEOUT_DEFAULT;
  policy->stall_limit     = HPLIP_DOWNLOAD_STALL_LIMIT_DEFAULT;
  policy->stall_time      = HPLIP_DOWNLOAD_STALL_TIME_DEFAULT;
  policy->rejected        = 0;
}


//
// 'hplip_download_policy_from_env()' - Apply the environment overrides
//                                      on top of the built-in bounds.
//
// Every bound is independent: an unusable value for one of them does
// not affect the others, and the default is kept for that one.
//

void
hplip_download_policy_from_env(
    hplip_download_policy_t *policy)		// I - Policy to update
{
  if (!policy)
    return;

  policy->connect_timeout =
    hplip_download_policy_env_long(HPLIP_DOWNLOAD_CONNECT_TIMEOUT_ENV,
				   HPLIP_DOWNLOAD_CONNECT_TIMEOUT_DEFAULT,
				   1L, HPLIP_DOWNLOAD_CONNECT_TIMEOUT_MAX,
				   &policy->rejected);
  policy->total_timeout =
    hplip_download_policy_env_long(HPLIP_DOWNLOAD_TOTAL_TIMEOUT_ENV,
				   HPLIP_DOWNLOAD_TOTAL_TIMEOUT_DEFAULT,
				   1L, HPLIP_DOWNLOAD_TOTAL_TIMEOUT_MAX,
				   &policy->rejected);
  policy->stall_limit =
    hplip_download_policy_env_long(HPLIP_DOWNLOAD_STALL_LIMIT_ENV,
				   HPLIP_DOWNLOAD_STALL_LIMIT_DEFAULT,
				   1L, HPLIP_DOWNLOAD_STALL_LIMIT_MAX,
				   &policy->rejected);
  policy->stall_time =
    hplip_download_policy_env_long(HPLIP_DOWNLOAD_STALL_TIME_ENV,
				   HPLIP_DOWNLOAD_STALL_TIME_DEFAULT,
				   1L, HPLIP_DOWNLOAD_STALL_TIME_MAX,
				   &policy->rejected);
}


//
// 'hplip_download_policy_apply()' - Apply the bounds to a libcurl handle.
//

void
hplip_download_policy_apply(
    CURL *curl,					// I - libcurl handle
    const hplip_download_policy_t *policy)	// I - Bounds to apply
{
  if (!curl || !policy)
    return;

  // The Printer Application serves its web interface from several
  // threads, and libcurl uses signals for its lengthier timeouts
  // unless it is told not to.  Installing those signal handlers from a
  // request thread would clobber whatever the rest of the process is
  // doing with them, so the timeouts below are only safe together with
  // CURLOPT_NOSIGNAL.
  curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);

  // Bound each phase of the transfer separately: connecting, making
  // progress at all, and finishing.
  curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, policy->connect_timeout);
  curl_easy_setopt(curl, CURLOPT_TIMEOUT, policy->total_timeout);
  curl_easy_setopt(curl, CURLOPT_LOW_SPEED_LIMIT, policy->stall_limit);
  curl_easy_setopt(curl, CURLOPT_LOW_SPEED_TIME, policy->stall_time);

  // Nobody is watching a progress bar for a download triggered from the
  // web interface; keep libcurl from calling a progress function.
  curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 1L);
}


//
// 'hplip_download_policy_message()' - Describe a failed transfer in a
//                                     sentence for the web interface.
//
// The result of a transfer which ran out of time does not say on its
// own which of the three bounds expired, so the caller passes what
// libcurl reported about the attempt: whether a connection was ever
// established, and how long the whole attempt took.
//

void
hplip_download_policy_message(
    CURLcode result,				// I - libcurl result
    const hplip_download_policy_t *policy,	// I - Bounds which were applied
    int    connected,				// I - Was a connection established?
    double elapsed,				// I - Seconds the attempt took
    char   *buf,				// I - Buffer for the message
    size_t bufsize)				// I - Size of the buffer
{
  long	connect_timeout = policy ? policy->connect_timeout : 0L,
	total_timeout   = policy ? policy->total_timeout : 0L,
	stall_limit     = policy ? policy->stall_limit : 0L,
	stall_time      = policy ? policy->stall_time : 0L;


  if (!buf || bufsize == 0)
    return;

  buf[0] = '\0';

  switch (result)
  {
    case CURLE_OPERATION_TIMEDOUT:
      if (!connected)
	snprintf(buf, bufsize,
		 "the server did not accept the connection within %ld seconds",
		 connect_timeout);
      else if (total_timeout > 0 &&
	       elapsed >= (double)total_timeout - 0.5)
	snprintf(buf, bufsize,
		 "the transfer did not finish within %ld seconds",
		 total_timeout);
      else
	snprintf(buf, bufsize,
		 "the transfer stopped making progress and was aborted (fewer than %ld bytes per second arrived for %ld seconds)",
		 stall_limit, stall_time);
      break;

    case CURLE_COULDNT_RESOLVE_HOST:
      snprintf(buf, bufsize, "the server name could not be resolved");
      break;

    case CURLE_COULDNT_RESOLVE_PROXY:
      snprintf(buf, bufsize, "the proxy name could not be resolved");
      break;

    case CURLE_COULDNT_CONNECT:
      snprintf(buf, bufsize, "no connection to the server could be established");
      break;

    case CURLE_SSL_CONNECT_ERROR:
      snprintf(buf, bufsize, "the secure connection to the server failed");
      break;

    case CURLE_PARTIAL_FILE:
      snprintf(buf, bufsize,
	       "the transfer ended before the whole file had arrived");
      break;

    case CURLE_HTTP_RETURNED_ERROR:
      snprintf(buf, bufsize, "the server refused to serve the file");
      break;

    case CURLE_WRITE_ERROR:
      // Not "the downloaded data ...": the plugin page treats the word
      // "downloaded" in a status line as "the license page comes next".
      snprintf(buf, bufsize, "the data received could not be written to disk");
      break;

    default:
      // libcurl's own wording is short and readable, and is more
      // useful than a bare number for everything not handled above.
      snprintf(buf, bufsize, "%s", curl_easy_strerror(result));
      break;
  }

  // snprintf() truncates rather than overflows, but a sentence which
  // got cut in half is worse than a plain ending.
  if (bufsize >= 4 && buf[0] && strlen(buf) == bufsize - 1)
    snprintf(buf + bufsize - 4, 4, "...");
}
