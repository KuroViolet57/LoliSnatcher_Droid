import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

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
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// package_info_plus 10.2.2 dropped `main.java.srcDirs += 'src/main/kotlin'`.
// On this AGP 8.11 / Kotlin 2.2 tree, assembleRelease then runs
// compileReleaseKotlin with an empty source list, so PackageInfoPlugin
// never lands in the jar. Pin the source dir at task execution.
subprojects {
    if (name != "package_info_plus") {
        return@subprojects
    }
    tasks.withType<KotlinCompile>().configureEach {
        doFirst {
            val kotlinDir = project.file("src/main/kotlin")
            if (kotlinDir.isDirectory) {
                setSource(project.fileTree(kotlinDir))
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
