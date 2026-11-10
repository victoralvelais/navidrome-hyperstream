"""Documented Mornye hook boundary; runtime/plugin compatibility is not yet proven."""

import os

from .importer import Importer


def on_track(result, metadata):
    """Queue a completed acquisition; a separate worker performs the import.

    Configure Mornye to download unconverted FLAC into HYPERSTREAM_ROOT/inbox.
    Failed downloads must not enter the conversion queue.
    """
    if not result.success:
        return None
    root = os.environ.get("HYPERSTREAM_ROOT")
    if not root:
        raise ValueError("HYPERSTREAM_ROOT must name the dedicated prototype directory")
    if not metadata.id or not result.file_path:
        raise ValueError("Mornye completion is missing the recording ID or file path")
    provider = getattr(result, "provider", "unknown") or "unknown"
    return Importer(root).enqueue(result.file_path, f"mornye:{provider}:{metadata.id}")["id"]
