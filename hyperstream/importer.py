"""Recoverable FLAC -> MP3 publication. Requires ffmpeg and ffprobe on PATH.

The prototype owns root/inbox, root/state and root/library. State and library
must support hard links on the same filesystem for atomic, exclusive publication.
"""

from __future__ import annotations

from contextlib import contextmanager
from hashlib import sha256
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import subprocess
from typing import Iterator


class ImportFailure(RuntimeError):
    pass


def digest(path: Path) -> str:
    result = sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def within(path: Path, root: Path) -> Path:
    resolved = path.resolve()
    if resolved == root or not resolved.is_relative_to(root):
        raise ImportFailure(f"Path is outside the managed directory: {path}")
    return resolved


def component(value: str) -> str:
    value = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", value).strip(" .")[:60]
    value = value.rstrip(" .") or "Unknown"
    if re.fullmatch(r"CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9]", value.split(".")[0], re.I):
        value = "_" + value
    return value


def run(command: list[str]) -> str:
    try:
        return subprocess.run(
            command, check=True, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=1800,
        ).stdout
    except subprocess.CalledProcessError as exc:
        raise ImportFailure(exc.stderr[-2000:] or "Audio command failed") from exc
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ImportFailure(str(exc)) from exc


def probe(path: Path) -> dict:
    return json.loads(run([
        "ffprobe", "-v", "error", "-show_format", "-show_streams",
        "-of", "json", str(path),
    ]))


def audio(info: dict) -> dict:
    for stream in info.get("streams", []):
        if stream.get("codec_type") == "audio":
            return stream
    raise ImportFailure("No audio stream found")


def duration(info: dict) -> float:
    value = float(info.get("format", {}).get("duration", 0))
    if not math.isfinite(value) or value <= 0:
        raise ImportFailure("Invalid audio duration")
    return value


def tags(info: dict) -> dict:
    return {key.lower(): str(value) for key, value in info.get("format", {}).get("tags", {}).items()}


def covers(info: dict) -> int:
    return sum(bool(s.get("disposition", {}).get("attached_pic")) for s in info.get("streams", []))


class Importer:
    def __init__(self, root: str | Path):
        self.root = Path(root).resolve()
        if self.root == Path(self.root.anchor):
            raise ImportFailure("Use a dedicated directory, not a filesystem root")
        self.root.mkdir(parents=True, exist_ok=True)
        self.inbox = self.root / "inbox"
        self.state = self.root / "state"
        self.library = self.root / "library"
        for directory in (self.inbox, self.state, self.library):
            if directory.is_symlink() or directory.resolve().parent != self.root:
                raise ImportFailure("Managed directories must not redirect outside the root")
            directory.mkdir(exist_ok=True)
        self.db_path = self.state / "imports.sqlite3"
        with self.db() as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("""CREATE TABLE IF NOT EXISTS imports (
                id TEXT PRIMARY KEY, event_key TEXT NOT NULL UNIQUE,
                source TEXT NOT NULL, source_hash TEXT NOT NULL,
                target TEXT NOT NULL, status TEXT NOT NULL,
                output_hash TEXT, error TEXT
            )""")

    @contextmanager
    def db(self) -> Iterator[sqlite3.Connection]:
        connection = sqlite3.connect(self.db_path, timeout=30)
        connection.row_factory = sqlite3.Row
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def jobs(self) -> list[dict]:
        with self.db() as db:
            return [dict(row) for row in db.execute("SELECT * FROM imports ORDER BY rowid")]

    def get(self, job_id: str) -> dict:
        with self.db() as db:
            row = db.execute("SELECT * FROM imports WHERE id=?", (job_id,)).fetchone()
        if row is None:
            raise ImportFailure("Unknown import job")
        return dict(row)

    def update(self, job_id: str, status: str, *, error: str | None = None, output_hash: str | None = None) -> None:
        with self.db() as db:
            db.execute(
                "UPDATE imports SET status=?, error=?, output_hash=COALESCE(?, output_hash) WHERE id=?",
                (status, error, output_hash, job_id),
            )

    def enqueue(self, source: str | Path, event_key: str) -> dict:
        if not event_key.strip():
            raise ImportFailure("A stable acquisition event key is required")
        job_id = sha256(event_key.encode()).hexdigest()
        with self.db() as db:
            existing = db.execute("SELECT * FROM imports WHERE id=?", (job_id,)).fetchone()
        if existing:
            return dict(existing)
        source = within(Path(source), self.inbox)
        if not source.is_file() or source.suffix.lower() != ".flac":
            raise ImportFailure("This prototype accepts completed FLAC files in inbox only")
        info = probe(source)
        if audio(info).get("codec_name") != "flac":
            raise ImportFailure("The input is not FLAC audio")
        duration(info)
        metadata = tags(info)
        artist = metadata.get("album_artist") or metadata.get("albumartist") or metadata.get("artist") or "Unknown Artist"
        album = metadata.get("album") or "Unknown Album"
        title = metadata.get("title") or source.stem
        target = Path(component(artist)) / component(album) / f"{component(title)}-{job_id[:12]}.mp3"
        with self.db() as db:
            db.execute(
                "INSERT OR IGNORE INTO imports (id,event_key,source,source_hash,target,status) VALUES (?,?,?,?,?,?)",
                (job_id, event_key, str(source.relative_to(self.inbox)), digest(source), target.as_posix(), "queued"),
            )
        return self.get(job_id)

    @contextmanager
    def worker_lock(self) -> Iterator[None]:
        # OS locks are released on process death; a stale lock file is harmless.
        with (self.state / "worker.lock").open("a+b") as lock:
            lock.seek(0, os.SEEK_END)
            if lock.tell() == 0:
                lock.write(b"0")
                lock.flush()
            lock.seek(0)
            try:
                if os.name == "nt":
                    import msvcrt
                    msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError as exc:
                raise ImportFailure("Another import worker is running") from exc
            try:
                yield
            finally:
                lock.seek(0)
                if os.name == "nt":
                    msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
                else:
                    fcntl.flock(lock.fileno(), fcntl.LOCK_UN)

    def process(self, job_id: str) -> dict:
        with self.worker_lock():
            job = self.get(job_id)
            if job["status"] == "published":
                return job
            try:
                self._process(job)
            except (ImportFailure, OSError, ValueError, KeyError) as exc:
                current = self.get(job_id)
                status = "cleanup_pending" if current["status"] == "cleanup_pending" else "failed"
                self.update(job_id, status, error=str(exc))
                raise ImportFailure(str(exc)) from exc
            return self.get(job_id)

    def _process(self, job: dict) -> None:
        job_id = job["id"]
        source = within(self.inbox / job["source"], self.inbox)
        target = within(self.library / job["target"], self.library)
        converted = within(self.state / f"{job_id}.mp3", self.state)

        # A prior process may have published before recording its final state.
        if job["output_hash"] and target.exists():
            if digest(target) != job["output_hash"]:
                raise ImportFailure("Destination conflict; existing library file was left untouched")
            self.update(job_id, "cleanup_pending")
            self._cleanup(job, source, converted)
            return

        if not source.is_file() or digest(source) != job["source_hash"]:
            raise ImportFailure("Staged source is missing or changed; retained files were left untouched")
        original = probe(source)
        reuse = converted.exists() and job["output_hash"] and digest(converted) == job["output_hash"]
        if not reuse:
            self.update(job_id, "converting")
            sample_rate = int(audio(original)["sample_rate"])
            if sample_rate not in (32000, 44100, 48000):
                sample_rate = 48000 if sample_rate % 48000 == 0 else 44100
            run([
                "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                "-i", str(source), "-map", "0:a:0", "-map", "0:v?",
                "-map_metadata", "0", "-c:a", "libmp3lame", "-b:a", "320k",
                "-ar", str(sample_rate), "-c:v", "copy", "-disposition:v", "attached_pic",
                "-id3v2_version", "3", str(converted),
            ])
        self.validate(original, converted)
        if digest(source) != job["source_hash"]:
            raise ImportFailure("Source changed during conversion; source was retained")
        output_hash = digest(converted)
        with converted.open("r+b") as stream:
            os.fsync(stream.fileno())
        self.update(job_id, "publishing", output_hash=output_hash)
        target.parent.mkdir(parents=True, exist_ok=True)
        within(target, self.library)
        try:
            os.link(converted, target)
        except FileExistsError:
            if digest(target) != output_hash:
                raise ImportFailure("Destination conflict; existing library file was left untouched")
        except OSError as exc:
            raise ImportFailure(
                "Atomic publication failed. State and library must support hard links on the same filesystem; source retained."
            ) from exc
        if digest(target) != output_hash:
            raise ImportFailure("Published file verification failed; source retained")
        self.update(job_id, "cleanup_pending")
        self._cleanup(job, source, converted)

    def _cleanup(self, job: dict, source: Path, converted: Path) -> None:
        if source.exists():
            if digest(source) != job["source_hash"]:
                raise ImportFailure("Source changed before cleanup; it was left untouched")
            source.unlink()
        converted.unlink(missing_ok=True)
        self.update(job["id"], "published")

    @staticmethod
    def validate(original: dict, converted: Path) -> None:
        result = probe(converted)
        stream = audio(result)
        if stream.get("codec_name") != "mp3" or int(stream.get("bit_rate", 0)) != 320000:
            raise ImportFailure("Output must be MP3 at 320 kbps")
        if abs(duration(original) - duration(result)) > 0.25:
            raise ImportFailure("Converted duration differs from source")
        before, after = tags(original), tags(result)
        aliases = {"albumartist": "album_artist", "tracknumber": "track", "discnumber": "disc"}
        for key in ("title", "artist", "album", "album_artist", "albumartist", "track", "tracknumber", "disc", "discnumber", "date"):
            if key in before and before[key] != after.get(aliases.get(key, key)):
                raise ImportFailure(f"Conversion did not preserve the {key} tag")
        if covers(original) != covers(result):
            raise ImportFailure("Conversion did not preserve embedded artwork")
        run(["ffmpeg", "-nostdin", "-v", "error", "-xerror", "-i", str(converted), "-map", "0:a:0", "-f", "null", "-"])
