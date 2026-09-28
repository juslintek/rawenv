# Repository guidance

Follow [`RULES.md`](RULES.md) for shared engineering, safety, Git, and review rules. It is the committed source of truth; machine-specific files may supplement it but must not replace the shared rules.

Read the relevant source and nearby documentation before changing it. Run checks for the affected component and report the commands and results. Do not claim a deployment or runtime check unless it ran.

For GUI work, read the relevant platform guide under `docs/arch/` and inspect the matching screen in `design/prototype/` before implementation. Verify the changed interface visually on the affected platform.

## Verification

- CLI: `zig build` and `zig build test`.
- CI runs the full CLI tests on macOS and Linux; Windows CI only compiles the CLI.
- Shared GUI schema: `npx ajv-cli@5 validate --spec=draft2020 -s shared/schema.json -d shared/mock-data.json`.
- macOS GUI: build the CLI with `zig build`, then run `cd gui/macos && swift build && swift test`.
- Linux GUI: `docker build -f gui/linux/Dockerfile.test -t rawenv-linux-test .` then `docker run --rm rawenv-linux-test`.
- Windows GUI: `cd gui/windows && dotnet build Rawenv.Tests/Rawenv.Tests.csproj` and `dotnet test Rawenv.Tests/Rawenv.Tests.csproj --logger trx`.
- For docs-only changes, `git diff --check` is sufficient.

## Publishing

Do not publish or deploy unless explicitly requested. The documented Cloudflare Pages command publishes `docs/public` directly:

```sh
npx wrangler pages deploy docs/public --project-name rawenv --branch main
```

Tagged `v*` releases publish CLI artifacts through `.github/workflows/release.yml`; do not create or push a release tag unless explicitly requested.
