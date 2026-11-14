# Direct SMB remote-folder test

The November 13 user decision is to connect **inside Hyperstream using SMB**,
the protocol used by iOS Files. No Files picker/share sheet, companion, new upload
service, additional Docker deployment, or Navidrome plugin is required.

## Device test

1. Use an empty `Hyperstream Test` folder inside an existing writable share,
   separate from the production music library and Syncthing mirror.
2. Open **Home > Remote folder**. Enter a name, an address such as
   `smb://computer/share/Hyperstream Test`, and the file-sharing username/password.
   `COMPUTER\username` and UNC addresses work too. These credentials are separate
   from Navidrome. The destination folder must already exist.
3. Choose **Test and save**. This directly connects with encrypted SMB3 and tests
   writing, renaming, and deleting a tiny unique probe. The destination and login
   are saved in platform secure storage only after a successful test.
4. Choose **Send to remote folder** from a song menu in Albums, Songs, Search,
   Favorites, playlists, or Now Playing. Keep Hyperstream open until completion.
   It downloads the original file from Navidrome and sends it without conversion.
5. Verify playable audio on the computer. Send again: the original must remain
   unchanged and a numbered copy should appear. Test cancellation during download
   and upload, network interruption, and destination persistence across relaunch.
6. Away from home, enable Tailscale and use the Windows host's Tailscale IP/DNS
   address. The Navidrome TSDProxy hostname does not automatically forward SMB.
   Existing host/tailnet access rules and iOS local-network permission still apply.

Never include passwords in reports, commands, or source. The app does not alter
shares, firewall rules, folder permissions, Tailscale, or the Navidrome deployment.

## Boundaries

- One device-level saved destination, separate from the active Navidrome login.
  Reachability is checked on demand. No startup transfers or background probes.
- SMB3 encryption and signing are required; no unencrypted or SMB1 fallback.
  Native socket work runs in worker isolates, away from the UI isolate.
- Unique `.hyperstream-<random>.part` uploads are flushed and size-checked before
  a non-replacing server-side rename. Collisions yield numbered copies. A lost
  final acknowledgement is reported as uncertain and never retried automatically.
- Cancellation joins pending writes before cleanup. Backgrounding cancels unfinished
  work; final publication can finish once started. No automatic relaunch recovery.
- Remote cleanup is best effort: an outage/process kill can leave a unique partial
  or probe file. No recursive or blanket remote cleanup is performed.
- This is a file-copy test, not library ingestion: no scanning, conversion, source
  deletion, production imports, or claim of Navidrome indexing. It does not establish
  strict upload-only ACLs or isolate the SMB service from its Windows host.

## Validation and dependencies

Tests cover address validation, protected-storage failure, probe cleanup, collisions,
partial writes, cancellation, lost rename acknowledgements, and the configuration UI.
The Windows release runner additionally creates an encrypted temporary SMB share
and synthetic account, compares bytes through the actual native library, checks
collisions/bad credentials, then removes the test share/account. The script refuses
to run outside GitHub Actions. Physical iPhone/LiveContainer acceptance remains a
device test; successful packaging alone does not establish it.

Native notices and source references appear under **Remote folder > Open-source
licenses**. The pinned dependency and its build-tool compatibility adjustment are
documented in `apps/client/packages/dart_smb2/UPSTREAM.md`.

## Next architecture

The user's newer preference supersedes older mandatory-companion/server-only
proposals: investigate app-side acquisition/conversion, optional phone storage, and
optional publication through an existing remote folder. Providers and destinations
remain separate capabilities. Those features and scanner reconciliation remain
future work, not functionality established by this test.
