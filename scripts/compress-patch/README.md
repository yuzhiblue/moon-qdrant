# bikallem/compress@0.3.4 patch sources

Fixed copies of the five compress sources that still used the `try?`
syntax, which moonc >= 0.10.20 removed. CI copies these over the
downloaded dependency cache (after the legacy `moon.mod.json` manifests
have been migrated), so builds on current toolchains succeed.

Apply point: the "migrate legacy dependency manifests" step in
`.github/workflows/check.yml` and `.github/workflows/integration.yml`.

Once upstream (bikallem/compress) ships a manifest-migrated, syntax-clean
release and `oboard/mio` picks it up, delete this directory and the copy
step in both workflows.
