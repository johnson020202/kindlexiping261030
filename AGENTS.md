# Project instructions

This repository is the Kindle lockscreen project **kindlexiping261030**.

- Read `README.md`, `docs/内容与来源.md`, and `docs/越狱与安装.md` before changing content or device code.
- Never generate, paraphrase, or stitch名著 quotations. New excerpts must be exact spans from a cited source, with source URL and SHA-256.
- Keep 100 works × 50 excerpts and global uniqueness unless the user explicitly changes the scope.
- Primary display font is Smiley Sans. Before adding content, run `make test`; every character must be covered by the font.
- Never claim Kindle lock screen, touch navigation, jailbreak compatibility, or GitHub publication is verified unless the corresponding test/device action was actually performed and recorded.
- Do not modify system partitions, boot hooks, or unrelated files under `/Volumes/Kindle`. Back up `RUNME.sh` before replacing it.
- `source-cache/`, `build/`, credentials, Kindle logs, and personal data must not be committed.
- Release rule: bump `VERSION` by semantic versioning, update `CHANGELOG.md`, run `make test`, commit, tag `v<version>`, push, and publish a GitHub Release with the package and checksums.
- One-click AI entry: `AI.command` / `./ai.sh`.
