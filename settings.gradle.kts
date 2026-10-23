pluginManagement {
    repositories {
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        mavenLocal()
        google()
        mavenCentral()
        // 4koma (the TOML parser behind geode's config file) and its konbini parser are only on JitPack.
        // Consumers of the Maven Central artifact need the same repository.
        maven {
            url = uri("https://jitpack.io")
            content { includeGroupAndSubgroups("cc.ekblad") }
        }
    }
}

rootProject.name = "geode-relay"

// The relay, published to Maven Central as com.vitorpamplona.geode:geode (plus its test
// fixtures) and shipped as bundles, .deb/.rpm and a GHCR image.
include(":geode")

// Head-to-head relay benchmark (geode vs strfry vs anything). Never published.
include(":relayBench")

// quartz lives in its own repo (vitorpamplona/quartz) and comes from Maven Central. To change
// it alongside geode, point Gradle at a local checkout and it builds that checkout instead of
// the published artifact:
//   ./gradlew -PquartzDir=../quartz :geode:test
providers.gradleProperty("quartzDir").orNull?.let { dir ->
    includeBuild(dir) {
        dependencySubstitution {
            substitute(module("com.vitorpamplona.quartz:quartz")).using(project(":quartz"))
        }
    }
}
