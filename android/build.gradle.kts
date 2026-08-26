allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    // Keep plugin builds next to their sources. Flutter plugins live in the
    // Pub cache on C: while this repo is on D:; Kotlin incremental caches then
    // crash with "this and base files have different roots".
    val projectPath = project.projectDir.canonicalFile.toPath()
    val rootPath = rootProject.projectDir.canonicalFile.toPath()
    if (projectPath.startsWith(rootPath)) {
        project.layout.buildDirectory.value(newBuildDir.dir(project.name))
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
