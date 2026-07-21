import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
  kotlin("jvm") version "2.4.0"
  id("org.jetbrains.kotlin.plugin.compose") version "2.4.0"
  id("org.jetbrains.compose") version "1.8.2"
}

repositories {
  mavenCentral()
  google()
  maven("https://maven.pkg.jetbrains.space/public/p/compose/dev")
}

kotlin { jvmToolchain(17) }

dependencies {
  implementation(compose.desktop.currentOs)
  implementation("org.json:json:20240303")
}

compose.desktop {
  application {
    mainClass = "MainKt"
    nativeDistributions {
      targetFormats(TargetFormat.Dmg, TargetFormat.Deb, TargetFormat.Msi)
      packageName = "rext-renderer"
      packageVersion = "1.0.0"
    }
  }
}
