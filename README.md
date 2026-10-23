# geode-relay

**geode** is a standalone [Nostr](https://github.com/nostr-protocol/nips) relay for the JVM, built
on [Quartz](https://github.com/vitorpamplona/quartz)'s relay-server code (Ktor CIO). It started
inside [Amethyst](https://github.com/vitorpamplona/amethyst) as `:geode` and shipped from there up
to 1.19.0; this repo continues the same version line.

What's here:

- [`geode/`](geode/README.md): the relay. Install it, configure it and run it from that README.
  It is shipped as:
  - a Docker image on GHCR (`ghcr.io/vitorpamplona/geode`)
  - bundles with a bundled JRE for macOS, Linux and Windows
  - `.deb`/`.rpm` packages with a systemd unit
  - a Homebrew formula
  - a library on Maven Central, `com.vitorpamplona.geode:geode`, with its test fixtures
- [`relayBench/`](relayBench/README.md): the head-to-head relay benchmark. It boots geode, strfry
  and any other relay binary, replays one deterministic corpus, and measures
  ingest/query/NIP-77 sync (`./relayBench/run.sh`). It is never published.

## Build

JDK 21. Then:

```bash
./gradlew :geode:run --args="--port 7447"   # run the relay
./gradlew :geode:test :relayBench:test      # the test suites
./gradlew :geode:geodeImage                 # portable bundle under geode/build/geode-image/
./gradlew spotlessApply                     # format
./gradlew installGitHook                    # pre-commit (spotless) + pre-push (tests) hooks
```

To build against a local Quartz checkout instead of the published artifact:
`./gradlew -PquartzDir=../quartz :geode:test`.

## Using geode as a library

```kotlin
repositories {
    mavenCentral()
    // 4koma, the TOML parser behind geode's config file, is published only on JitPack.
    maven("https://jitpack.io") { content { includeGroupAndSubgroups("cc.ekblad") } }
}

dependencies {
    implementation("com.vitorpamplona.geode:geode:<version>")
    // In-process relay for tests: RelayClientTest, collectUntilEose, synthetic events.
    testImplementation(testFixtures("com.vitorpamplona.geode:geode:<version>"))
}
```

## Publishing

Bump `VERSION_NAME` in `gradle.properties` and push a matching `v<version>` tag.
`.github/workflows/create-release.yml` runs the tests, then publishes to Maven Central, opens the
GitHub release, attaches the bundles and packages, and pushes the GHCR image.
`bump-homebrew-geode-formula.yml` then syncs `geode/packaging/homebrew/geode-relay.rb`.

These repository secrets need to be set:

| Secret | Used for |
|---|---|
| `SONATYPE_USERNAME`, `SONATYPE_PASSWORD` | Maven Central portal token |
| `SIGNING_PRIVATE_KEY`, `SIGNING_PASSWORD` | GPG key that signs the Maven publication |
| `MAC_CERTIFICATE_P12`, `MAC_CERTIFICATE_PASSWORD`, `MAC_SIGN_IDENTITY` | Developer ID codesigning of the macOS bundle (optional: without them it ships unsigned) |
| `MAC_NOTARY_APPLE_ID`, `MAC_NOTARY_PASSWORD`, `MAC_NOTARY_TEAM_ID` | Notarization of the macOS bundle (optional) |

GHCR uses the workflow's own `GITHUB_TOKEN`.

## License

MIT, see [LICENSE](LICENSE).
