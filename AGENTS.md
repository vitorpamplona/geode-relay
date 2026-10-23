# geode-relay

geode is a standalone JVM Nostr relay (Ktor CIO) built on Quartz's relay-server code. It is
published as a library (`com.vitorpamplona.geode:geode` on Maven Central, plus its
`java-test-fixtures` variant) and shipped to relay operators as jlink bundles, `.deb`/`.rpm`, a GHCR
image and a Homebrew formula. It started inside [Amethyst](https://github.com/vitorpamplona/amethyst)
as `:geode`, which is still its main library consumer: `amy serve` embeds the relay, and Amethyst's
and amy's tests boot it in-process through the test fixtures.

## Layout

- `geode/`: the relay. `src/main` has the engine (`RelayEngine`, `InProcessRelays`), the Ktor server (`KtorRelay`), the
  TOML config, policies, mirroring, the NIP-86 admin API and the CLI (`MainKt`). `src/testFixtures`
  holds `RelayClientTest`, `collectUntilEose`, the `preload`/publish helpers and synthetic events.
  `src/test` also holds the Quartz client tests that need a real socket relay (`KtorRelay`), under
  `com.vitorpamplona.quartz.*`; they moved here when Quartz left Amethyst.
  `packaging/` has the systemd unit, the macOS entitlements and the reference Homebrew formula.
  `Dockerfile` builds the GHCR image from the repo root.
- `relayBench/`: the head-to-head benchmark (geode vs strfry vs any relay binary). Never published.
  Run it with `./relayBench/run.sh`.
- `geode/plans/`, `relayBench/plans/`: design notes, named `YYYY-MM-DD-<slug>.md`.
- `scripts/`: release helpers (`asset-name.sh` names the assets; there are also deb and macOS signing fixes).
- `tools/agent-hooks/`: the agent pre-push gate (spotless).

## Rules

- **Protocol logic belongs in Quartz.** The relay-server engine pieces (event store, filters, NIP
  implementations) live in [vitorpamplona/quartz](https://github.com/vitorpamplona/quartz). geode
  assembles them into a server with config, policies and operations. To change both together, build
  against a local checkout: `./gradlew -PquartzDir=../quartz :geode:test`.
- **The public API is what Amethyst builds against.** `RelayEngine`, `KtorRelay`, `EventStore`
  wiring and the test fixtures are consumed by Amethyst's `cli` and test code. Releases follow
  semantic versioning: a breaking change to them bumps the major version and needs a matching change
  in Amethyst (`libs.geode`, or `-PgeodeDir=../geode-relay` there while both change).
- **Dependencies:** check a new dependency's license before adding it. geode ships under MIT.
  Permissive licenses are fine. LGPL, or GPL with a linking exception, gets a warning in the PR.
  Anything stricter is a stop: raise it for the maintainer to decide.
- **jlink module list:** a new dependency may need a JDK module in `jlinkModules`
  (`geode/build.gradle.kts`). A missing one links fine and then fails at runtime with
  `NoClassDefFound`. CI boots the image and fetches NIP-11 to catch that.
- **Logging:** log through Quartz's `Log`. Use the lambda overload for interpolated messages
  (`Log.d(TAG) { "…$x" }`), and pass the throwable in a catch (`Log.w(TAG, "…", e)`).
- **Imports:** never write fully-qualified class names inline in function bodies. Import the class,
  or use `import … as Alias` for a real name collision.
- **Unicode:** never put raw invisible or bidi Unicode characters in source. Write `\uXXXX` escapes.
- **Verify, don't guess.** Reproduce a bug with a failing test before you explain it. The suites
  are `./gradlew :geode:test :relayBench:test`. CI passes `-DsyncN=100000` to keep the
  mirror-sync benchmark from exhausting the runner's heap (see `.github/workflows/build.yml`).

## Before pushing

`./gradlew spotlessApply`, then `./gradlew :geode:test :relayBench:test -DsyncN=100000`.
`./gradlew installGitHook` installs a pre-commit hook (spotless) and a pre-push hook (spotless plus
the tests). Agents also get a spotless gate on `git push` from `.claude/settings.json` /
`.codex/hooks.json`. Commits are conventional (`feat:`, `fix:`, …). Never use `--no-verify`.

## Releasing

Bump `VERSION_NAME` in `gradle.properties`, then push a matching `v<version>` tag. The release
workflow refuses a tag that doesn't match. `README.md` → Publishing lists the jobs and the secrets
they need. Releases up to 1.19.0 shipped from the Amethyst repo; this repo continues that line, so
the `.deb`/`.rpm`, Homebrew and GHCR channels keep upgrading in order.
