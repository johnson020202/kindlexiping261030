# AI bootstrap

You are continuing the repository `kindlexiping261030`.

1. Read `README.md`, `AGENTS.md`, `docs/内容与来源.md`, and `docs/越狱与安装.md`.
2. Inspect the working tree and current `VERSION`; do not discard uncommitted user work.
3. For content changes, use `tools/build_content.py`; excerpts must be exact source spans, never model-written quotations. Run `make test`.
4. For visual changes, run `make preview` and inspect `preview.png`; for a release, regenerate all images with `make images`.
5. For Kindle changes, keep the runtime outside system partitions, preserve the original `RUNME.sh`, and keep `栖息 · 关闭并恢复` functional.
6. Report verified desktop, package, device, and GitHub results separately. If a device action requires a human, say exactly which action is pending.
7. When publishing, increment `VERSION`, update `CHANGELOG.md`, run tests, commit, create tag `v<version>`, push, and attach the Kindle ZIP and SHA-256 file to the GitHub Release.
