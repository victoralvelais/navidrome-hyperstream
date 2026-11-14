# Vendored SMB client

Source: https://github.com/ales-drnz/dart_smb2
Revision: `bd513bf9d25b4389c1b14dea0023b1b94b86fbc5` (0.3.0).

The runtime source and native build hook are unchanged. The package manifest
uses `code_assets ^1.2.1` and `hooks ^2.0.2`, matching Hyperstream's existing
Flutter native-assets toolchain. Upstream development-only dependencies and
screenshots are omitted. Public registry requests returned HTTP 403 during
integration; this pinned copy makes the application source reproducible.

The build hook downloads libsmb2-r11 binaries and verifies the upstream SHA-256
for each platform. It loads them dynamically; iOS and Windows builds must verify
packaging. Preserve LICENSE and NOTICE. Native notices are also bundled in the
application's open-source licenses. No SMB authentication or cryptography is
implemented by Hyperstream itself.
