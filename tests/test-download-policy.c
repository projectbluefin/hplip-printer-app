/*
 * Unit tests for the bounds applied to HP plugin downloads.
 *
 * Built by tests/run-download-policy-tests.sh against
 * tests/stub-curl/curl/curl.h, so it needs neither libcurl nor PAPPL.
 *
 * The stub's curl_easy_setopt() records the option and reads the value
 * back as a long.  libcurl expects a long for every option this module
 * sets, so a value passed as anything else would be read back wrong
 * here as well as being wrong in production.
 */

#include <curl/curl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "hplip-download-policy.h"

/* Recorded curl_easy_setopt() calls */

#define MAX_RECORDED 32

static struct
{
  CURLoption	option;
  long		value;
} recorded[MAX_RECORDED];
static int n_recorded = 0;
static int n_overflow = 0;

CURLcode
curl_easy_setopt(CURL *handle, CURLoption option, ...)
{
  va_list	ap;
  long		value;

  (void)handle;

  va_start(ap, option);
  value = va_arg(ap, long);
  va_end(ap);

  if (n_recorded < MAX_RECORDED)
  {
    recorded[n_recorded].option = option;
    recorded[n_recorded].value  = value;
    n_recorded ++;
  }
  else
    n_overflow ++;

  return (CURLE_OK);
}

const char *
curl_easy_strerror(CURLcode code)
{
  switch (code)
  {
    case CURLE_OK:
      return ("No error");
    case CURLE_COULDNT_RESOLVE_PROXY:
      return ("Could not resolve proxy");
    case CURLE_COULDNT_RESOLVE_HOST:
      return ("Could not resolve host");
    case CURLE_COULDNT_CONNECT:
      return ("Could not connect to server");
    case CURLE_PARTIAL_FILE:
      return ("Transferred a partial file");
    case CURLE_HTTP_RETURNED_ERROR:
      return ("HTTP response code said error");
    case CURLE_WRITE_ERROR:
      return ("Failed writing received data to disk/application");
    case CURLE_OPERATION_TIMEDOUT:
      return ("Timeout was reached");
    case CURLE_SSL_CONNECT_ERROR:
      return ("SSL connect error");
    case CURLE_GOT_NOTHING:
      return ("Server returned nothing (no headers, no data)");
    default:
      return ("Unknown error");
  }
}

/* Test helpers */

static int checks = 0;
static int failures = 0;

static void
check(int ok, const char *what)
{
  checks ++;
  if (!ok)
  {
    failures ++;
    fprintf(stderr, "FAIL: %s\n", what);
  }
}

static void
check_long(long got, long want, const char *what)
{
  checks ++;
  if (got != want)
  {
    failures ++;
    fprintf(stderr, "FAIL: %s: got %ld, want %ld\n", what, got, want);
  }
}

static void
check_str(const char *got, const char *want, const char *what)
{
  checks ++;
  if (strcmp(got, want))
  {
    failures ++;
    fprintf(stderr, "FAIL: %s:\n  got  \"%s\"\n  want \"%s\"\n", what, got,
	    want);
  }
}

static void
check_contains(const char *haystack, const char *needle, const char *what)
{
  checks ++;
  if (!strstr(haystack, needle))
  {
    failures ++;
    fprintf(stderr, "FAIL: %s: \"%s\" does not contain \"%s\"\n", what,
	    haystack, needle);
  }
}

static void
check_lacks(const char *haystack, const char *needle, const char *what)
{
  checks ++;
  if (strcasestr(haystack, needle))
  {
    failures ++;
    fprintf(stderr, "FAIL: %s: \"%s\" contains \"%s\"\n", what, haystack,
	    needle);
  }
}

static void
reset_recorded(void)
{
  n_recorded = 0;
  n_overflow = 0;
}

static int
recorded_value(CURLoption option, long *value)
{
  int	i;

  for (i = 0; i < n_recorded; i ++)
  {
    if (recorded[i].option == option)
    {
      *value = recorded[i].value;
      return (1);
    }
  }

  return (0);
}

/* A fresh, empty environment for each test which reads one */

static void
clear_env(void)
{
  unsetenv(HPLIP_DOWNLOAD_CONNECT_TIMEOUT_ENV);
  unsetenv(HPLIP_DOWNLOAD_TOTAL_TIMEOUT_ENV);
  unsetenv(HPLIP_DOWNLOAD_STALL_LIMIT_ENV);
  unsetenv(HPLIP_DOWNLOAD_STALL_TIME_ENV);
}

/* Tests */

static void
test_defaults(void)
{
  hplip_download_policy_t policy;

  clear_env();
  memset(&policy, 0x5a, sizeof(policy));
  hplip_download_policy_defaults(&policy);

  check_long(policy.connect_timeout, HPLIP_DOWNLOAD_CONNECT_TIMEOUT_DEFAULT,
	     "default connect timeout");
  check_long(policy.total_timeout, HPLIP_DOWNLOAD_TOTAL_TIMEOUT_DEFAULT,
	     "default total timeout");
  check_long(policy.stall_limit, HPLIP_DOWNLOAD_STALL_LIMIT_DEFAULT,
	     "default stall limit");
  check_long(policy.stall_time, HPLIP_DOWNLOAD_STALL_TIME_DEFAULT,
	     "default stall time");
  check_long(policy.rejected, 0, "no override rejected by default");

  /* The point of the exercise: every bound is finite and non-zero, so
     no combination of them can leave a transfer running forever. */
  check(policy.connect_timeout > 0, "default connect timeout is positive");
  check(policy.total_timeout > 0, "default total timeout is positive");
  check(policy.stall_limit > 0, "default stall limit is positive");
  check(policy.stall_time > 0, "default stall time is positive");
  check(policy.total_timeout >= policy.connect_timeout,
	 "total timeout is not shorter than the connect timeout");
}

static void
test_env_overrides(void)
{
  hplip_download_policy_t policy;

  clear_env();
  setenv(HPLIP_DOWNLOAD_CONNECT_TIMEOUT_ENV, "7", 1);
  setenv(HPLIP_DOWNLOAD_TOTAL_TIMEOUT_ENV, "11", 1);
  setenv(HPLIP_DOWNLOAD_STALL_LIMIT_ENV, "13", 1);
  setenv(HPLIP_DOWNLOAD_STALL_TIME_ENV, "17", 1);

  hplip_download_policy_defaults(&policy);
  hplip_download_policy_from_env(&policy);

  check_long(policy.connect_timeout, 7, "overridden connect timeout");
  check_long(policy.total_timeout, 11, "overridden total timeout");
  check_long(policy.stall_limit, 13, "overridden stall limit");
  check_long(policy.stall_time, 17, "overridden stall time");
  check_long(policy.rejected, 0, "valid overrides are not rejected");

  clear_env();
}

/* Every unusable value must leave the built-in bound in place rather
   than disable it: a zero or negative bound would mean "no bound". */
static void
test_env_rejects_unusable_values(void)
{
  static const char *bad[] =
  {
    "0", "-1", "-99999", "abc", "12x", "x12", "", " ", "1.5", "+-3",
    "99999999999999999999999", "0x10"
  };
  size_t	i;
  hplip_download_policy_t policy;

  for (i = 0; i < sizeof(bad) / sizeof(bad[0]); i ++)
  {
    clear_env();
    setenv(HPLIP_DOWNLOAD_CONNECT_TIMEOUT_ENV, bad[i], 1);
    setenv(HPLIP_DOWNLOAD_TOTAL_TIMEOUT_ENV, bad[i], 1);
    setenv(HPLIP_DOWNLOAD_STALL_LIMIT_ENV, bad[i], 1);
    setenv(HPLIP_DOWNLOAD_STALL_TIME_ENV, bad[i], 1);

    hplip_download_policy_defaults(&policy);
    hplip_download_policy_from_env(&policy);

    check_long(policy.connect_timeout, HPLIP_DOWNLOAD_CONNECT_TIMEOUT_DEFAULT,
	       "unusable connect timeout kept the default");
    check_long(policy.total_timeout, HPLIP_DOWNLOAD_TOTAL_TIMEOUT_DEFAULT,
	       "unusable total timeout kept the default");
    check_long(policy.stall_limit, HPLIP_DOWNLOAD_STALL_LIMIT_DEFAULT,
	       "unusable stall limit kept the default");
    check_long(policy.stall_time, HPLIP_DOWNLOAD_STALL_TIME_DEFAULT,
	       "unusable stall time kept the default");

    /* An empty or unset variable is "not configured", not an error;
       everything else here was supplied and thrown away. */
    if (bad[i][0])
      check_long(policy.rejected, 4, "four unusable overrides were counted");
    else
      check_long(policy.rejected, 0, "an empty override is not an error");
  }

  /* An override above the accepted maximum is refused as well, since a
     bound which never expires is the same as no bound. */
  clear_env();
  {
    char huge[64];

    snprintf(huge, sizeof(huge), "%ld", HPLIP_DOWNLOAD_CONNECT_TIMEOUT_MAX + 1);
    setenv(HPLIP_DOWNLOAD_CONNECT_TIMEOUT_ENV, huge, 1);
    setenv(HPLIP_DOWNLOAD_TOTAL_TIMEOUT_ENV,
	   "99999999999999999999999", 1);

    hplip_download_policy_defaults(&policy);
    hplip_download_policy_from_env(&policy);

    check_long(policy.connect_timeout, HPLIP_DOWNLOAD_CONNECT_TIMEOUT_DEFAULT,
	       "above-maximum connect timeout kept the default");
    check_long(policy.total_timeout, HPLIP_DOWNLOAD_TOTAL_TIMEOUT_DEFAULT,
	       "unparsable total timeout kept the default");
    check_long(policy.rejected, 2, "two above-range overrides were counted");
  }

  clear_env();
}

/* One unusable value must not disturb the other three. */
static void
test_env_overrides_are_independent(void)
{
  hplip_download_policy_t policy;

  clear_env();
  setenv(HPLIP_DOWNLOAD_CONNECT_TIMEOUT_ENV, "not-a-number", 1);
  setenv(HPLIP_DOWNLOAD_STALL_TIME_ENV, "5", 1);

  hplip_download_policy_defaults(&policy);
  hplip_download_policy_from_env(&policy);

  check_long(policy.connect_timeout, HPLIP_DOWNLOAD_CONNECT_TIMEOUT_DEFAULT,
	     "unusable connect timeout falls back alone");
  check_long(policy.stall_time, 5, "the valid override still applies");
  check_long(policy.total_timeout, HPLIP_DOWNLOAD_TOTAL_TIMEOUT_DEFAULT,
	     "untouched total timeout keeps the default");
  check_long(policy.stall_limit, HPLIP_DOWNLOAD_STALL_LIMIT_DEFAULT,
	     "untouched stall limit keeps the default");
  check_long(policy.rejected, 1, "one unusable override was counted");

  clear_env();
}

static void
test_apply_sets_every_bound(void)
{
  hplip_download_policy_t policy;
  CURL *curl = (CURL *)(size_t)1;	/* Any non-NULL handle will do */
  long value = -1;

  reset_recorded();

  hplip_download_policy_defaults(&policy);
  policy.connect_timeout = 3;
  policy.total_timeout   = 5;
  policy.stall_limit     = 7;
  policy.stall_time      = 9;

  hplip_download_policy_apply(curl, &policy);

  check_long(n_overflow, 0, "no option call was dropped");
  check_long(n_recorded, 6, "exactly the expected options were set");

  /* A stalled endpoint is only bounded if all four are on the handle. */
  check(recorded_value(CURLOPT_CONNECTTIMEOUT, &value),
	"CURLOPT_CONNECTTIMEOUT is set");
  check_long(value, 3, "CURLOPT_CONNECTTIMEOUT value");
  check(recorded_value(CURLOPT_TIMEOUT, &value),
	"CURLOPT_TIMEOUT is set");
  check_long(value, 5, "CURLOPT_TIMEOUT value");
  check(recorded_value(CURLOPT_LOW_SPEED_LIMIT, &value),
	"CURLOPT_LOW_SPEED_LIMIT is set");
  check_long(value, 7, "CURLOPT_LOW_SPEED_LIMIT value");
  check(recorded_value(CURLOPT_LOW_SPEED_TIME, &value),
	"CURLOPT_LOW_SPEED_TIME is set");
  check_long(value, 9, "CURLOPT_LOW_SPEED_TIME value");

  /* libcurl only honours the timeouts above without signals when it is
     told not to use them, and the web interface is threaded. */
  check(recorded_value(CURLOPT_NOSIGNAL, &value), "CURLOPT_NOSIGNAL is set");
  check_long(value, 1, "CURLOPT_NOSIGNAL value");

  check(recorded_value(CURLOPT_NOPROGRESS, &value),
	"CURLOPT_NOPROGRESS is set");
  check_long(value, 1, "CURLOPT_NOPROGRESS value");
}

static void
test_apply_is_null_safe(void)
{
  hplip_download_policy_t policy;

  reset_recorded();
  hplip_download_policy_defaults(&policy);

  hplip_download_policy_apply(NULL, &policy);
  check_long(n_recorded, 0, "a NULL handle sets nothing");

  hplip_download_policy_apply((CURL *)(size_t)1, NULL);
  check_long(n_recorded, 0, "a NULL policy sets nothing");
}

static void
test_message_names_the_connect_timeout(void)
{
  hplip_download_policy_t policy;
  char buf[512];

  hplip_download_policy_defaults(&policy);

  /* Never got a connection: the connect bound is what expired. */
  hplip_download_policy_message(CURLE_OPERATION_TIMEDOUT, &policy, 0, 30.0,
				buf, sizeof(buf));
  check(buf[0] != '\0', "a timed-out transfer gets a message");
  check_contains(buf, "did not accept the connection", "connect timeout wording");
  check_contains(buf, "30 seconds", "connect timeout mentions its bound");
  check(!strstr(buf, "bytes per second"),
	"connect timeout is not described as a stall");
}

static void
test_message_names_the_total_timeout(void)
{
  hplip_download_policy_t policy;
  char buf[512];

  hplip_download_policy_defaults(&policy);

  /* Connected, and the attempt lasted as long as the total bound. */
  hplip_download_policy_message(CURLE_OPERATION_TIMEDOUT, &policy, 1, 900.0,
				buf, sizeof(buf));
  check(buf[0] != '\0', "a total timeout gets a message");
  check_contains(buf, "did not finish within", "total timeout wording");
  check_contains(buf, "900 seconds", "total timeout mentions its bound");

  /* Just past the bound, which is where an actual expiry lands. */
  hplip_download_policy_message(CURLE_OPERATION_TIMEDOUT, &policy, 1, 900.4,
				buf, sizeof(buf));
  check_contains(buf, "did not finish within", "total timeout wording at the bound");
}

static void
test_message_names_the_stall_bound(void)
{
  hplip_download_policy_t policy;
  char buf[512];

  hplip_download_policy_defaults(&policy);

  /* Connected, alive, but too slow: this is the stall bound. */
  hplip_download_policy_message(CURLE_OPERATION_TIMEDOUT, &policy, 1, 60.0,
				buf, sizeof(buf));
  check(buf[0] != '\0', "a stalled transfer gets a message");
  check_contains(buf, "stopped making progress", "stall wording");
  check_contains(buf, "1024 bytes per second", "stall limit is named");
  check_contains(buf, "60 seconds", "stall time is named");
  check(!strstr(buf, "did not finish within"),
	"a stall is not described as a total timeout");
}

static void
test_message_distinguishes_the_three_timeouts(void)
{
  hplip_download_policy_t policy;
  char connect_msg[512], total_msg[512], stall_msg[512];

  hplip_download_policy_defaults(&policy);

  hplip_download_policy_message(CURLE_OPERATION_TIMEDOUT, &policy, 0, 30.0,
				connect_msg, sizeof(connect_msg));
  hplip_download_policy_message(CURLE_OPERATION_TIMEDOUT, &policy, 1, 900.0,
				total_msg, sizeof(total_msg));
  hplip_download_policy_message(CURLE_OPERATION_TIMEDOUT, &policy, 1, 60.0,
				stall_msg, sizeof(stall_msg));

  check(strcmp(connect_msg, total_msg) != 0, "connect and total differ");
  check(strcmp(connect_msg, stall_msg) != 0, "connect and stall differ");
  check(strcmp(total_msg, stall_msg) != 0, "total and stall differ");
}

static void
test_message_covers_the_common_failures(void)
{
  static const struct
  {
    CURLcode	code;
    const char	*needle;
  } cases[] =
  {
    { CURLE_COULDNT_RESOLVE_HOST, "server name could not be resolved" },
    { CURLE_COULDNT_RESOLVE_PROXY, "proxy name could not be resolved" },
    { CURLE_COULDNT_CONNECT, "no connection to the server" },
    { CURLE_SSL_CONNECT_ERROR, "secure connection" },
    { CURLE_PARTIAL_FILE, "whole file had arrived" },
    { CURLE_HTTP_RETURNED_ERROR, "refused to serve" },
    { CURLE_WRITE_ERROR, "could not be written to disk" }
  };
  size_t	i;
  char		buf[512];
  hplip_download_policy_t policy;

  hplip_download_policy_defaults(&policy);

  for (i = 0; i < sizeof(cases) / sizeof(cases[0]); i ++)
  {
    memset(buf, 0x5a, sizeof(buf));
    hplip_download_policy_message(cases[i].code, &policy, 1, 1.0, buf,
				  sizeof(buf));
    check(buf[0] != '\0', "a failure gets a non-empty message");
    check_contains(buf, cases[i].needle, "failure wording");
  }

  /* Anything not listed falls back to libcurl's own wording, which is
     still a sentence and still better than a bare number. */
  memset(buf, 0x5a, sizeof(buf));
  hplip_download_policy_message(CURLE_GOT_NOTHING, &policy, 1, 1.0, buf,
				sizeof(buf));
  check_str(buf, "Server returned nothing (no headers, no data)",
	    "unlisted failure uses libcurl's wording");
}

static void
test_message_is_null_and_size_safe(void)
{
  hplip_download_policy_t policy;
  char buf[8];
  size_t i;

  hplip_download_policy_defaults(&policy);

  /* A NULL buffer or a zero size must not be written to. */
  hplip_download_policy_message(CURLE_OPERATION_TIMEDOUT, &policy, 0, 1.0,
				NULL, 100);
  hplip_download_policy_message(CURLE_OPERATION_TIMEDOUT, &policy, 0, 1.0,
				buf, 0);

  /* A buffer too small for the sentence must be terminated and not
     overrun, for every size from 1 upwards. */
  for (i = 1; i <= sizeof(buf); i ++)
  {
    memset(buf, 0x5a, sizeof(buf));
    hplip_download_policy_message(CURLE_OPERATION_TIMEDOUT, &policy, 0, 1.0,
				  buf, i);
    check(buf[i - 1] == '\0', "the message is terminated inside the buffer");
  }

  /* A truncated sentence is marked as truncated rather than left
     dangling mid-word. */
  memset(buf, 0x5a, sizeof(buf));
  hplip_download_policy_message(CURLE_OPERATION_TIMEDOUT, &policy, 0, 1.0,
				buf, 8);
  check_str(buf, "the ...", "a truncated message ends with an ellipsis");

  check_str(curl_easy_strerror(CURLE_OK), "No error", "stub sanity: CURLE_OK");
}

static void
test_message_accepts_a_null_policy(void)
{
  char buf[512];

  hplip_download_policy_message(CURLE_OPERATION_TIMEDOUT, NULL, 0, 1.0,
				buf, sizeof(buf));
  check(buf[0] != '\0', "a NULL policy still produces a message");

  hplip_download_policy_message(CURLE_COULDNT_CONNECT, NULL, 1, 1.0,
				buf, sizeof(buf));
  check(buf[0] != '\0', "a NULL policy still describes a plain failure");
}

/*
 * The plugin page decides whether to show the license form, and whether a
 * download is under way, by looking for the words "downloaded",
 * "installing", and "removing" in the status line it is about to display.
 * A failure sentence is shown as-is in that same status line, so it must
 * never contain any of those words: a download which failed must not be
 * presented as one which succeeded.
 */
static void
test_message_cannot_be_mistaken_for_success(void)
{
  static const CURLcode codes[] =
  {
    CURLE_OK,
    CURLE_UNSUPPORTED_PROTOCOL,
    CURLE_FAILED_INIT,
    CURLE_COULDNT_RESOLVE_PROXY,
    CURLE_COULDNT_RESOLVE_HOST,
    CURLE_COULDNT_CONNECT,
    CURLE_PARTIAL_FILE,
    CURLE_HTTP_RETURNED_ERROR,
    CURLE_WRITE_ERROR,
    CURLE_OPERATION_TIMEDOUT,
    CURLE_SSL_CONNECT_ERROR,
    CURLE_GOT_NOTHING,
    (CURLcode)999
  };
  static const int connected_flags[] = { 0, 1 };
  static const double elapsed_values[] = { 0.0, 1.0, 60.0, 899.0, 900.0, 1e6 };
  static const char *forbidden[] = { "downloaded", "installing", "removing" };
  size_t i, j, k, m;
  char buf[512];
  hplip_download_policy_t policy;

  hplip_download_policy_defaults(&policy);

  for (i = 0; i < sizeof(codes) / sizeof(codes[0]); i ++)
  {
    for (j = 0; j < sizeof(connected_flags) / sizeof(connected_flags[0]); j ++)
    {
      for (k = 0; k < sizeof(elapsed_values) / sizeof(elapsed_values[0]); k ++)
      {
	hplip_download_policy_message(codes[i], &policy, connected_flags[j],
				      elapsed_values[k], buf, sizeof(buf));

	for (m = 0; m < sizeof(forbidden) / sizeof(forbidden[0]); m ++)
	  check_lacks(buf, forbidden[m],
		      "a failure sentence does not read as a success");
      }
    }
  }

  /* The same has to hold with the bounds overridden, since the sentences
     quote them. */
  clear_env();
  setenv(HPLIP_DOWNLOAD_STALL_LIMIT_ENV, "1", 1);
  setenv(HPLIP_DOWNLOAD_STALL_TIME_ENV, "1", 1);
  hplip_download_policy_defaults(&policy);
  hplip_download_policy_from_env(&policy);
  clear_env();

  hplip_download_policy_message(CURLE_OPERATION_TIMEDOUT, &policy, 1, 1.0,
				buf, sizeof(buf));
  for (m = 0; m < sizeof(forbidden) / sizeof(forbidden[0]); m ++)
    check_lacks(buf, forbidden[m],
		"a failure sentence with overridden bounds is not a success");
}

static void
test_null_policy_arguments_are_ignored(void)
{
  hplip_download_policy_defaults(NULL);
  hplip_download_policy_from_env(NULL);
  check(1, "the setters tolerate a NULL policy");
}

int
main(void)
{
  /* A wake-up for anyone who edits the module's default message
     wording: the assertions above pin the phrases the web interface
     and the log will show. */
  test_defaults();
  test_env_overrides();
  test_env_rejects_unusable_values();
  test_env_overrides_are_independent();
  test_apply_sets_every_bound();
  test_apply_is_null_safe();
  test_message_names_the_connect_timeout();
  test_message_names_the_total_timeout();
  test_message_names_the_stall_bound();
  test_message_distinguishes_the_three_timeouts();
  test_message_covers_the_common_failures();
  test_message_is_null_and_size_safe();
  test_message_accepts_a_null_policy();
  test_message_cannot_be_mistaken_for_success();
  test_null_policy_arguments_are_ignored();

  printf("%d checks, %d failures\n", checks, failures);

  return (failures ? 1 : 0);
}
