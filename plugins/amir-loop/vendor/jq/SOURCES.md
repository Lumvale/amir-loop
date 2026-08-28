# Vendored jq binaries

Release tag: `jq-1.8.1` (https://github.com/jqlang/jq/releases/tag/jq-1.8.1)

Each binary was downloaded from the release asset URL below and verified against
the SHA-256 values **published by upstream** in that same release's
`sha256sum.txt` (https://github.com/jqlang/jq/releases/download/jq-1.8.1/sha256sum.txt).
These hashes are copied verbatim from that upstream file - they were not computed
locally from the download and then rubber-stamped, which would prove nothing
about the content, only that the bytes matched themselves.

| File | Download URL | Upstream-published SHA-256 |
|---|---|---|
| jq-linux-amd64 | https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-linux-amd64 | `020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d` |
| jq-macos-arm64 | https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-macos-arm64 | `a9fe3ea2f86dfc72f6728417521ec9067b343277152b114f4e98d8cb0e263603` |
| jq-macos-amd64 | https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-macos-amd64 | `e80dbe0d2a2597e3c11c404f03337b981d74b4a8504b70586c354b7697a7c27f` |
| jq-windows-amd64.exe | https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-windows-amd64.exe | `23cb60a1354eed6bcc8d9b9735e8c7b388cd1fdcb75726b93bc299ef22dd9334` |

Verification performed at vendoring time: each downloaded file's locally computed
`sha256sum` was compared byte-for-byte against the corresponding line copied from
upstream's own `sha256sum.txt` for this tag, before the binaries were committed.
All four matched. If a future re-vendor of a different version finds any mismatch,
the download must be discarded and NOT committed.
