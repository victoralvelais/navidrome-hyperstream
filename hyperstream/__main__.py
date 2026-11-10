import argparse
import json
import sys

from .importer import Importer, ImportFailure


def main() -> int:
    parser = argparse.ArgumentParser(description="Hyperstream server import prototype")
    parser.add_argument("--root", default=".sandbox", help="Dedicated directory containing inbox, state, and library")
    commands = parser.add_subparsers(dest="command", required=True)
    enqueue = commands.add_parser("enqueue", help="Record a completed FLAC acquisition")
    enqueue.add_argument("source")
    enqueue.add_argument("--key", required=True, help="Stable event key for deduplication")
    process = commands.add_parser("process", help="Process pending jobs once")
    process.add_argument("--retry-failed", action="store_true")
    commands.add_parser("status", help="Show the persistent import journal")
    args = parser.parse_args()
    try:
        importer = Importer(args.root)
        if args.command == "enqueue":
            print(json.dumps(importer.enqueue(args.source, args.key), indent=2))
        elif args.command == "status":
            print(json.dumps(importer.jobs(), indent=2))
        else:
            failures = 0
            for job in importer.jobs():
                if job["status"] == "published" or (job["status"] == "failed" and not args.retry_failed):
                    continue
                try:
                    importer.process(job["id"])
                except ImportFailure:
                    failures += 1
                print(json.dumps(importer.get(job["id"]), indent=2))
            return int(failures > 0)
    except (ImportFailure, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
