import java.text.SimpleDateFormat
import java.util.Date

plugins {
    java
    id("com.gradleup.shadow") version "8.3.5"
}

val pluginVersion = "1.0.1"

group = "dev.th0rgal.mcpanel"
version = pluginVersion

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(21))
    }
}

tasks.withType<JavaCompile>().configureEach {
    options.encoding = "UTF-8"
    options.release.set(21)
}

repositories {
    mavenCentral()
    maven { url = uri("https://repo.papermc.io/repository/maven-public/") }
    maven { url = uri("https://hub.spigotmc.org/nexus/content/repositories/snapshots/") }
    maven { url = uri("https://oss.sonatype.org/content/repositories/snapshots") }
    maven { url = uri("https://nexus.velocitypowered.com/repository/maven-public/") }
}

dependencies {
    // Paper API (includes Spigot/Bukkit)
    compileOnly("io.papermc.paper:paper-api:1.21.1-R0.1-SNAPSHOT")

    // Velocity API
    compileOnly("com.velocitypowered:velocity-api:3.3.0-SNAPSHOT")
    annotationProcessor("com.velocitypowered:velocity-api:3.3.0-SNAPSHOT")

    // Gson for JSON
    implementation("com.google.code.gson:gson:2.10.1")

    compileOnly("org.jetbrains:annotations:24.1.0")
}

tasks.processResources {
    expand(mapOf("version" to pluginVersion))
}

// Paper/Bukkit JAR - excludes Velocity metadata and classes
val shadowJarBukkit by tasks.registering(com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar::class) {
    archiveClassifier.set("bukkit")
    archiveFileName.set("MCPanelBridge-${pluginVersion}-Bukkit.jar")

    from(sourceSets.main.get().output)
    configurations = listOf(project.configurations.runtimeClasspath.get())

    // Exclude Velocity-specific files and classes
    exclude("velocity-plugin.json")
    exclude("dev/th0rgal/mcpanel/bridge/velocity/**")

    relocate("com.google.gson", "dev.th0rgal.mcpanel.bridge.shaded.gson")

    minimize {
        exclude(dependency("com.google.code.gson:gson:.*"))
    }

    manifest {
        attributes(
            "Built-By" to System.getProperty("user.name"),
            "Version" to pluginVersion,
            "Build-Timestamp" to SimpleDateFormat("yyyy-MM-dd' 'HH:mm:ss.SSSZ").format(Date()),
            "Created-By" to "Gradle ${gradle.gradleVersion}",
            "Build-Jdk" to "${System.getProperty("java.version")} (${System.getProperty("java.vendor")} ${System.getProperty("java.vm.version")})",
            "Platform" to "Bukkit/Paper"
        )
    }
}

// Velocity JAR - excludes Bukkit metadata and classes
val shadowJarVelocity by tasks.registering(com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar::class) {
    archiveClassifier.set("velocity")
    archiveFileName.set("MCPanelBridge-${pluginVersion}-Velocity.jar")

    from(sourceSets.main.get().output)
    configurations = listOf(project.configurations.runtimeClasspath.get())

    // Exclude Bukkit-specific files and classes
    exclude("plugin.yml")
    exclude("dev/th0rgal/mcpanel/bridge/bukkit/**")

    relocate("com.google.gson", "dev.th0rgal.mcpanel.bridge.shaded.gson")

    minimize {
        exclude(dependency("com.google.code.gson:gson:.*"))
    }

    manifest {
        attributes(
            "Built-By" to System.getProperty("user.name"),
            "Version" to pluginVersion,
            "Build-Timestamp" to SimpleDateFormat("yyyy-MM-dd' 'HH:mm:ss.SSSZ").format(Date()),
            "Created-By" to "Gradle ${gradle.gradleVersion}",
            "Build-Jdk" to "${System.getProperty("java.version")} (${System.getProperty("java.vendor")} ${System.getProperty("java.vm.version")})",
            "Platform" to "Velocity"
        )
    }
}

tasks.named("build") {
    dependsOn(shadowJarBukkit, shadowJarVelocity)
}

tasks.named("jar") {
    enabled = false
}

// Disable the default shadowJar task
tasks.named<com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar>("shadowJar") {
    enabled = false
}
