# Direct SMB remote-folder test

The November 13 user decision is to connect **inside Hyperstream using SMB**,
the protocol used by iOS Files. No Files picker/share sheet, companion, new upload
service, additional Docker deployment, or Navidrome plugin is required.

## Device test

1. Use an empty `Hyperstream Test` folder inside an existing writable share,
   separate from the production music library and Syncthing mirror.
2. Open **Home > Remote folder**. Enter the server name or IP address, optionally
   prefixed with `smb://`, and the file-sharing username/password.
   Both `COMPUTER\username` and `COMPUTER/username` work. Use the account password.
   Windows PINs cannot authenticate this SMB connection.
3. Choose **Check connection**. Hyperstream verifies an encrypted SMB3 session
   using the server's `IPC$` service and saves the login in platform secure storage.
   You can leave setup here and choose a destination later. **Login verified**
   records the successful check. Sessions are opened on demand for later operations.
4. Enter the **Share name** shown in the Windows folder's Sharing properties.
   Enter an existing **Subfolder**, or leave it empty to use the share
   root. For `smb://computer/Music/Hyperstream Test`, the share is `Music` and the
   folder is `Hyperstream Test`. Choose **Test and save folder** to check share
   access, folder access, and creation/rename/removal of a tiny unique probe.
   Errors identify the failing stage. A failed folder check keeps the saved login.
   Folder selection currently uses text fields. Existing saved destinations migrate
   automatically, and reconnecting to the same account retains the selected folder.
5. Choose **Send to remote folder** from a song menu in Albums, Songs, Search,
   Favorites, playlists, or Now Playing. Keep Hyperstream open until completion.
   It downloads the original file from Navidrome and sends it without conversion.
6. Verify playable audio on the computer. Send again: the original must remain
   unchanged and a numbered copy should appear. Test cancellation during download
   and upload, network interruption, and destination persistence across relaunch.
7. Away from home, enable Tailscale and use the Windows host's Tailscale IP/DNS
   address. The Navidrome TSDProxy hostname does not automatically forward SMB.
   Existing host/tailnet access rules and iOS local-network permission still apply.

Never include passwords in reports, commands, or source. The app does not alter
shares, firewall rules, folder permissions, Tailscale, or the Navidrome deployment.

## Boundaries

- One device-level saved server login with an optional destination, independent of
  the active Navidrome login. Both are stored atomically in protected storage.
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

Release **0.1.0+47**, source `ca507e1c67bd08910a43b53ad3e306bc31ba60b4`,
passed [the paired release run](https://github.com/victoralvelais/navidrome-hyperstream/actions/runs/43545192791).
Formatting, analysis, 317 Flutter tests, 12 release-tool tests, the real encrypted
Windows SMB test, and native account/playback checks passed. Both artifacts were
collected and checksum-verified under `releases/v0.1.0+47-r1/`.

Tests cover address validation, protected-storage failure, probe cleanup, collisions,
partial writes, cancellation, lost rename acknowledgements, and the configuration UI.
Connection tests also cover login-only persistence, legacy destination migration,
both domain separators, per-stage failures, changing accounts, and interrupted UI
setup. The Windows release runner additionally creates an encrypted temporary SMB share
and synthetic account, compares bytes through the actual native library, checks
collisions/bad credentials, independent IPC$ authentication, and missing shares and
folders, then removes the test share/account. The script refuses
to run outside GitHub Actions. Physical iPhone acceptance remains a
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
