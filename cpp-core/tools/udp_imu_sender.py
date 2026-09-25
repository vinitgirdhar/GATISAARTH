"""Stream an external-IMU CSV to the edge engine over UDP, at the recorded rate.

Bench test for the UDP input (include/engine/udp_stream.h): what a Raspberry Pi
reading a USB/serial IMU would send. The header goes first, then one datagram
per row, paced by the `t` column (x `--speed`), then "#eof".

    replay_external_imu --input udp:5005 --json out.json      # terminal 1
    python cpp-core/tools/udp_imu_sender.py drive.csv --port 5005   # terminal 2
"""
from __future__ import annotations

import argparse
import socket
import time


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=5005)
    ap.add_argument("--speed", type=float, default=1.0, help="replay speed factor (0 = as fast as possible)")
    args = ap.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    target = (args.host, args.port)
    sent = 0
    with open(args.csv, encoding="utf8") as f:
        header = None
        t_col = None
        start_wall = start_t = None
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if header is None:
                header = [c.strip().lower() for c in line.split(",")]
                t_col = header.index("t")
                sock.sendto(line.encode(), target)
                continue
            t = float(line.split(",")[t_col])
            if args.speed > 0:
                if start_wall is None:
                    start_wall, start_t = time.perf_counter(), t
                due = start_wall + (t - start_t) / args.speed
                delay = due - time.perf_counter()
                if delay > 0:
                    time.sleep(delay)
            sock.sendto(line.encode(), target)
            sent += 1
    sock.sendto(b"#eof", target)
    print(f"sent {sent} rows to {args.host}:{args.port}")


if __name__ == "__main__":
    main()
