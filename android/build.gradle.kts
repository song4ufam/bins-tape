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
// 일부 플러그인(file_picker 등)이 compileSdk 34로 고정돼 있어서, 의존 라이브러리가
// 요구하는 36 이상으로 통일한다.
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)?.compileSdk = 36
    }
}

// on_audio_query_android는 예전 방식(AndroidManifest의 package 속성)이라 최신 AGP가
// 요구하는 namespace가 빠져 있다. 여기서 대신 채워준다. namespace는 plugin 적용 시점에
// 바로 설정해야 해서 afterEvaluate가 아니라 plugins.withId를 쓴다.
subprojects {
    plugins.withId("com.android.library") {
        if (project.name == "on_audio_query_android") {
            extensions.configure<com.android.build.api.dsl.LibraryExtension> {
                namespace = "com.lucasjosino.on_audio_query"
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
