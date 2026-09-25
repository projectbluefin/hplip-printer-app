/*
 * A stand-in for libcurl's public header, used only to compile and run
 * tests/test-download-policy.c without the PAPPL build dependencies.
 *
 * It declares exactly the part of libcurl which hplip-download-policy.c
 * uses, with the same names and argument types as the real header, so
 * that the module under test compiles here unchanged and a call which
 * passes the wrong type is caught by the test's varargs reader.
 *
 * The numeric values below are the real libcurl ones for libcurl 7.29
 * and later; they are documentation rather than a requirement, since
 * both sides of a test build see this header.
 */

#ifndef HPLIP_TEST_STUB_CURL_H
#define HPLIP_TEST_STUB_CURL_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void CURL;

typedef enum
{
  CURLE_OK = 0,
  CURLE_UNSUPPORTED_PROTOCOL,	/* 1 */
  CURLE_FAILED_INIT,		/* 2 */
  CURLE_URL_MALFORMAT,		/* 3 */
  CURLE_COULDNT_RESOLVE_PROXY,	/* 5 */
  CURLE_COULDNT_RESOLVE_HOST,	/* 6 */
  CURLE_COULDNT_CONNECT,	/* 7 */
  CURLE_PARTIAL_FILE = 18,
  CURLE_HTTP_RETURNED_ERROR = 22,
  CURLE_WRITE_ERROR = 23,
  CURLE_OPERATION_TIMEDOUT = 28,
  CURLE_SSL_CONNECT_ERROR = 35,
  CURLE_GOT_NOTHING = 52
} CURLcode;

typedef enum
{
  CURLOPT_WRITEDATA = 10000,
  CURLOPT_URL = 10002,
  CURLOPT_TIMEOUT = 13,
  CURLOPT_LOW_SPEED_LIMIT = 19,
  CURLOPT_LOW_SPEED_TIME = 20,
  CURLOPT_NOPROGRESS = 43,
  CURLOPT_FOLLOWLOCATION = 52,
  CURLOPT_MAXREDIRS = 68,
  CURLOPT_CONNECTTIMEOUT = 78,
  CURLOPT_NOSIGNAL = 99,
  CURLOPT_WRITEFUNCTION = 20011
} CURLoption;

extern CURLcode curl_easy_setopt(CURL *handle, CURLoption option, ...);
extern const char *curl_easy_strerror(CURLcode code);

#ifdef __cplusplus
}
#endif

#endif /* HPLIP_TEST_STUB_CURL_H */
