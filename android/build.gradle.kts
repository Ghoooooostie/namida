// Android 根构建配置：统一仓库、构建目录和插件使用的本机工具链版本。
import com.android.build.api.dsl.LibraryExtension

val namidaNdkVersion = "28.2.13676358"

allprojects {
    repositories {
        google()
        mavenCentral()
        maven("https://jitpack.io")
        maven {
          url = project(":app").file("repo").toURI()
        }
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

    pluginManager.withPlugin("com.android.library") {
        extensions.configure<LibraryExtension> {
            ndkVersion = namidaNdkVersion
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
