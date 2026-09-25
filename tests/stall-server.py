#!/usr/bin/env python3
"""A local HTTP endpoint which behaves the way a stalled HP mirror would.

The printer application downloads HP's plugin index, plugin archive, and
plugin signature from the network while a web admin request waits for the
answer.  A mirror which accepts the TCP connection and then stops talking
is the case the download bounds exist for, and this server is that mirror.

Modes:

  healthy      answer normally, so a test can show that the check passes
               for a working endpoint as well as failing for a broken one
  accept-only  accept the connection, read the request, never answer
  stall-body   answer, send a few bytes, then stop sending without
               closing the connection

The port it bound to is printed as the first line of stdout, so a caller
can let the kernel choose a free one.
"""

import argparse
import socket
import sys
import threading
import time

# How long a stalled connection is held open.  Long enough that a client
# without bounds would still be waiting when the test gives up on it, and
# short enough that the process exits on its own if a test goes wrong.
HOLD_SECONDS = 60


def serve_connection(conn, mode):
    """Answer (or pointedly not answer) one request."""
    try:
        conn.settimeout(5)
        try:
            conn.recv(65536)
        except OSError:
            pass

        if mode == "accept-only":
            # The connection is up and the request has been read: from
            # the client's point of view the server is simply thinking
            # about it forever.
            time.sleep(HOLD_SECONDS)
        elif mode == "stall-body":
            # Announce a large body, deliver a token amount of it, then
            # go quiet without closing, which is what a mirror that runs
            # out of steam looks like.
            conn.sendall(
                b"HTTP/1.1 200 OK\r\n"
                b"Content-Type: application/octet-stream\r\n"
                b"Content-Length: 1048576\r\n"
                b"\r\n"
            )
            conn.sendall(b"x" * 64)
            time.sleep(HOLD_SECONDS)
        else:
            body = b"healthy\n"
            conn.sendall(
                b"HTTP/1.1 200 OK\r\n"
                b"Content-Type: text/plain\r\n"
                b"Content-Length: %d\r\n"
                b"Connection: close\r\n"
                b"\r\n" % len(body)
            )
            conn.sendall(body)
    except OSError:
        pass
    finally:
        try:
            conn.close()
        except OSError:
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mode",
        choices=("healthy", "accept-only", "stall-body"),
        default="accept-only",
    )
    parser.add_argument("--port", type=int, default=0)
    args = parser.parse_args()

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", args.port))
        listener.listen(16)

        # Tell the caller which port we got, before serving anything.
        print(listener.getsockname()[1], flush=True)

        while True:
            try:
                conn, _ = listener.accept()
            except OSError:
                break
            threading.Thread(
                target=serve_connection, args=(conn, args.mode), daemon=True
            ).start()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
