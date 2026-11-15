# Direct SMB remote-folder test

The November 13 user decision is to connect **inside Hyperstream using SMB**,
the protocol used by iOS Files. No Files picker/share sheet, companion, new upload
service, additional Docker deployment, or Navidrome plugin is required.

## Device test

1. Use an empty `Hyperstream Test` folder inside an existing writable share,
   separate from the production music library and Syncthing mirror.
2. Open **Home > Remote folder**. Enter the server name or IP address, optionally
   prefixed with `smb://`, and the file-sharing username/password.
   A plain username works. Include a computer/domain prefix only when your server
   requires it. Both `COMPUTER\username` and `COMPUTER/username` are accepted.
   Use the account password.
   Windows PINs cannot authenticate this SMB connection.
3. Choose **Check connection**. Hyperstream verifies an encrypted SMB3 session
   using the server's `IPC$` service and saves the login in platform secure storage.
   You can leave setup here and choose a destination later. **Login verified**
   records the successful check. Sessions are opened on demand for later operations.
4. The app lists shared folders after connecting. Open a share, then navigate its
   subfolders using the list and **Up one folder**. Choose **Use this folder** at
   any level, including the share root. Selection checks creation, rename, and
   removal of a tiny unique probe before saving the destination. Browsing uses
   encrypted, signed SMB3 and reads directory entries. Files are excluded from the
   folder list. Hidden shares, including Windows administrative shares, are
   omitted from discovery. Ordinary shares are opened and their root directory
   is listed to verify browse access, using at most three simultaneous sessions.
   Shares that deny access or have disappeared are omitted. Network and login
   failures show an error so the user can retry. **Enter path manually** supports
   hidden shares and servers that restrict share enumeration. Reopening this settings page restores
   the saved login and loads the shares automatically. **Open saved folder** goes
   directly to the selected destination. Failed listing or write checks retain
   the saved login and previous destination.
5. Choose **Send to remote folder** from a song menu in Albums, Songs, Search,
   Favorites, playlists, or Now Playing. It downloads the original file from
   Navidrome and sends it without conversion. On iOS/iPadOS 26+, the app requests
   continued background processing and shows its availability in the transfer
   dialog. With a grant, lock the screen during both download and upload and
   verify the completed file. Repeat in Low Power Mode and while using another app.
   Progress and cancellation are available in the system activity.
   Older iOS versions and denied requests use a limited UIKit background grant
   when available. The dialog explains when a long transfer needs to stay open.
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
- A user-started transfer acquires its execution grant before connecting. iOS 26
  uses `BGContinuedProcessingTask` with a unique request identifier, immediate
  submission, byte progress, and system cancellation/expiration handling. A
  five-second launch-callback deadline falls back to limited background time.
  Native grants are released after completion or failure. The staging directory
  uses encrypted protection that remains readable after the device is locked.
- Screen lock and app switching preserve transfers with an execution grant.
  Cancellation joins pending writes before cleanup. System expiration or
  cancellation stops unfinished work and reports the reason. Final publication
  can finish once started. iOS resource policy can still end background execution,
  including under Low Power Mode. Force-quitting ends the process. There is no
  automatic relaunch recovery or resumable transfer journal.
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
Background tests cover screen-off during download and upload, continued and
limited grants, denied/delayed grants, system expiration, manual cancellation,
grant release, stale callbacks, progress throttling, and private staging setup.
Connection tests also cover login-only persistence, legacy destination migration,
plain usernames, both domain separators, per-stage failures, changing accounts,
share discovery, nested navigation, manual fallback, and interrupted UI setup.
The Windows release runner additionally creates an encrypted temporary SMB share
and synthetic account, compares bytes through the actual native library, checks
collisions/bad credentials, independent IPC$ authentication, and missing shares and
folders, encrypted share discovery, exclusion of a second explicitly denied
share, and directory-only nested listings, then
removes the test share/account. The script refuses
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
