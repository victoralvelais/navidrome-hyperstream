import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from hyperstream.importer import Importer, ImportFailure, audio, covers, digest, probe, tags
from hyperstream.mornye_hook import on_track


class ImportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
            raise RuntimeError("Integration tests require ffmpeg and ffprobe")
        cls.fixtures = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.fixtures.cleanup)
        cls.fixture = Path(cls.fixtures.name) / "source.flac"
        tone = Path(cls.fixtures.name) / "tone.flac"
        cover = Path(cls.fixtures.name) / "cover.png"
        subprocess.run([
            "ffmpeg", "-nostdin", "-v", "error", "-f", "lavfi",
            "-i", "sine=frequency=440:duration=2:sample_rate=44100",
            "-c:a", "flac", str(tone),
        ], check=True, capture_output=True)
        subprocess.run([
            "ffmpeg", "-nostdin", "-v", "error", "-f", "lavfi",
            "-i", "color=c=blue:s=32x32", "-frames:v", "1", str(cover),
        ], check=True, capture_output=True)
        subprocess.run([
            "ffmpeg", "-nostdin", "-v", "error", "-i", str(tone), "-i", str(cover),
            "-map", "0:a", "-map", "1:v", "-c", "copy", "-disposition:v", "attached_pic",
            "-metadata", "title=Prototype Tone", "-metadata", "artist=Hyperstream",
            "-metadata", "album=Import Test", "-metadata", "album_artist=Hyperstream",
            "-metadata", "track=2/10", "-metadata", "disc=1/2",
            "-metadata", "date=2026", str(cls.fixture),
        ], check=True, capture_output=True)

    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.importer = Importer(self.workspace.name)
        self.source = self.importer.inbox / "input.flac"
        shutil.copyfile(self.fixture, self.source)

    def enqueue(self):
        return self.importer.enqueue(self.source, "fixture:recording-1")

    def test_real_conversion_preserves_tags_art_and_removes_flac(self):
        job = self.enqueue()
        self.assertEqual(self.importer.process(job["id"])["status"], "published")
        target = self.importer.library / job["target"]
        info = probe(target)
        self.assertEqual(audio(info)["codec_name"], "mp3")
        self.assertEqual(int(audio(info)["bit_rate"]), 320000)
        self.assertEqual(tags(info)["title"], "Prototype Tone")
        self.assertEqual(tags(info)["track"], "2/10")
        self.assertEqual(covers(info), 1)
        self.assertFalse(self.source.exists())
        self.assertEqual(list(self.importer.state.glob("*.mp3")), [])

    def test_duplicate_event_after_cleanup_is_idempotent(self):
        job = self.enqueue()
        self.importer.process(job["id"])
        restarted = Importer(self.workspace.name)
        self.assertEqual(restarted.enqueue(self.source, "fixture:recording-1")["id"], job["id"])
        self.assertEqual(restarted.process(job["id"])["status"], "published")
        self.assertEqual(len(list(restarted.library.rglob("*.mp3"))), 1)

    def test_conversion_failure_preserves_source(self):
        job = self.enqueue()
        original = digest(self.source)
        with patch("hyperstream.importer.run", side_effect=ImportFailure("conversion failure")):
            with self.assertRaises(ImportFailure):
                self.importer.process(job["id"])
        self.assertEqual(digest(self.source), original)
        self.assertEqual(self.importer.get(job["id"])["status"], "failed")
        self.assertEqual(list(self.importer.library.rglob("*.mp3")), [])

    def test_destination_collision_never_overwrites(self):
        job = self.enqueue()
        target = self.importer.library / job["target"]
        target.parent.mkdir(parents=True)
        target.write_bytes(b"existing user file")
        with self.assertRaisesRegex(ImportFailure, "Destination conflict"):
            self.importer.process(job["id"])
        self.assertEqual(target.read_bytes(), b"existing user file")
        self.assertTrue(self.source.exists())

    def test_resume_after_publication_before_journal_update(self):
        job = self.enqueue()
        actual_link = os.link

        def interrupted_link(source, target):
            actual_link(source, target)
            raise OSError("simulated process interruption after link")

        with patch("hyperstream.importer.os.link", side_effect=interrupted_link):
            with self.assertRaisesRegex(ImportFailure, "Atomic publication failed"):
                self.importer.process(job["id"])
        self.assertTrue(self.source.exists())
        restarted = Importer(self.workspace.name)
        self.assertEqual(restarted.process(job["id"])["status"], "published")
        self.assertEqual(len(list(restarted.library.rglob("*.mp3"))), 1)
        self.assertFalse(self.source.exists())

    def test_cleanup_failure_retries_without_reencoding(self):
        job = self.enqueue()
        actual_unlink = Path.unlink

        def blocked_unlink(path, *args, **kwargs):
            if path == self.source:
                raise PermissionError("source is temporarily locked")
            return actual_unlink(path, *args, **kwargs)

        with patch.object(Path, "unlink", blocked_unlink):
            with self.assertRaisesRegex(ImportFailure, "temporarily locked"):
                self.importer.process(job["id"])
        self.assertEqual(self.importer.get(job["id"])["status"], "cleanup_pending")
        self.assertTrue(self.source.exists())
        with patch("hyperstream.importer.run", side_effect=AssertionError("must not reencode")):
            self.assertEqual(self.importer.process(job["id"])["status"], "published")

    def test_changed_source_is_not_deleted(self):
        job = self.enqueue()
        self.source.write_bytes(b"different file")
        with self.assertRaises(ImportFailure):
            self.importer.process(job["id"])
        self.assertEqual(self.source.read_bytes(), b"different file")

    def test_atomic_publication_failure_retains_source(self):
        job = self.enqueue()
        with patch("hyperstream.importer.os.link", side_effect=OSError("cross-device link")):
            with self.assertRaisesRegex(ImportFailure, "Atomic publication failed"):
                self.importer.process(job["id"])
        self.assertTrue(self.source.exists())
        self.assertEqual(list(self.importer.library.rglob("*.mp3")), [])

    def test_rejects_sources_outside_inbox(self):
        with self.assertRaises(ImportFailure):
            self.importer.enqueue(self.fixture, "outside")
        self.assertTrue(self.fixture.exists())

    def test_mornye_hook_queues_only_successful_completions(self):
        metadata = SimpleNamespace(id="recording-1")
        result = SimpleNamespace(success=False, file_path=str(self.source), provider="fixture")
        with patch.dict(os.environ, {"HYPERSTREAM_ROOT": self.workspace.name}):
            self.assertIsNone(on_track(result, metadata))
            self.assertEqual(self.importer.jobs(), [])
            result.success = True
            job_id = on_track(result, metadata)
            self.assertEqual(self.importer.get(job_id)["status"], "queued")
            self.assertEqual(on_track(result, metadata), job_id)


if __name__ == "__main__":
    unittest.main()
