plugins {
    alias(libs.plugins.jetbrainsKotlinJvm) apply false
    alias(libs.plugins.serialization) apply false
    alias(libs.plugins.vanniktech.mavenPublish) apply false
    alias(libs.plugins.diffplugSpotless)
}

// One version for every module, from VERSION_NAME in gradle.properties. The release
// workflow overrides it from the tag (ORG_GRADLE_PROJECT_VERSION_NAME), so the jars,
// the bundles, the .deb/.rpm and NIP-11's `version` all report the tagged version.
val geodeVersion: String = providers.gradleProperty("VERSION_NAME").get()

allprojects {
    group = providers.gradleProperty("GROUP").get()
    version = geodeVersion

    apply(plugin = "com.diffplug.spotless")

    spotless {
        kotlin {
            target("src/**/*.kt")

            // Same ktlint and header as Amethyst, where this code started, so a file
            // moved between the two repos formats identically on both sides.
            ktlint("1.7.1")
            licenseHeaderFile(
                rootProject.file("spotless/copyright.kt"),
                "@file:|package|import|class|object|sealed|open|interface|abstract ",
            )
        }

        kotlinGradle {
            target("*.gradle.kts")
        }
    }
}

tasks.register<Copy>("installGitHook") {
    val dotGit = File(rootProject.rootDir, ".git")
    val hooksDir: File =
        if (dotGit.isFile) {
            // Git worktree: .git is a file with "gitdir: <path>". Git reads hooks from the main
            // repository's .git/hooks, which the worktree's gitdir names in its `commondir` file;
            // a hook copied into the worktree's own gitdir never runs.
            val gitDir = File(dotGit.readText().trim().replace("gitdir: ", ""))
            val commonDir = File(gitDir, "commondir").takeIf { it.isFile }?.let { gitDir.resolve(it.readText().trim()).normalize() } ?: gitDir
            File(commonDir, "hooks")
        } else {
            File(dotGit, "hooks")
        }
    from("git-hooks/pre-commit")
    from("git-hooks/pre-push")
    into(hooksDir)
    filePermissions { unix("rwxrwxrwx") }
}
