#!/usr/bin/env python3
"""Patch the Android Gradle files that `flutter create` generates, for the X9 apps.

`flutter create` writes a fresh android/ folder on every CI run, so the few settings the
X9 apps need are applied here instead of being committed:

  * applicationId            e.g. in.donezo.x9.user  (the id the Play Store and Firebase use)
  * minSdk 23                required by local_auth (fingerprint / face) and flutter_secure_storage
  * core library desugaring  required by flutter_local_notifications 18
  * release signing          from android/key.properties when the CI secrets provided one
  * google-services plugin   only when android/app/google-services.json exists

Handles both the Kotlin DSL (build.gradle.kts, current Flutter) and the old Groovy files.

Usage:
  patch_gradle.py --dir <android dir> --application-id <id> --label "<app label>"
  patch_gradle.py --dir <android dir> --enable-google-services
"""
import argparse
import os
import re
import sys

DESUGAR_LIB = "com.android.tools:desugar_jdk_libs:2.1.4"
GOOGLE_SERVICES_PLUGIN = "4.4.2"


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    print(f"  patched {path}")


def app_build_file(android_dir):
    for name in ("app/build.gradle.kts", "app/build.gradle"):
        p = os.path.join(android_dir, name)
        if os.path.exists(p):
            return p, name.endswith(".kts")
    sys.exit(f"No app/build.gradle(.kts) found in {android_dir}")


def settings_file(android_dir):
    for name in ("settings.gradle.kts", "settings.gradle"):
        p = os.path.join(android_dir, name)
        if os.path.exists(p):
            return p, name.endswith(".kts")
    sys.exit(f"No settings.gradle(.kts) found in {android_dir}")


def patch_app(android_dir, application_id, label):
    path, kts = app_build_file(android_dir)
    s = read(path)

    # applicationId
    s = re.sub(r'applicationId\s*=?\s*"[^"]*"',
               f'applicationId = "{application_id}"' if kts else f'applicationId "{application_id}"',
               s, count=1)

    # minSdk: flutter's placeholder or a literal, whatever this Flutter version emitted
    s = re.sub(r'minSdk\s*=?\s*(flutter\.minSdkVersion|\d+)',
               'minSdk = 23' if kts else 'minSdk 23', s, count=1)

    # Java 17 + core library desugaring, inside compileOptions
    if "isCoreLibraryDesugaringEnabled" not in s and "coreLibraryDesugaringEnabled" not in s:
        if kts:
            block = ("compileOptions {\n"
                     "        isCoreLibraryDesugaringEnabled = true\n"
                     "        sourceCompatibility = JavaVersion.VERSION_17\n"
                     "        targetCompatibility = JavaVersion.VERSION_17\n")
        else:
            block = ("compileOptions {\n"
                     "        coreLibraryDesugaringEnabled true\n"
                     "        sourceCompatibility JavaVersion.VERSION_17\n"
                     "        targetCompatibility JavaVersion.VERSION_17\n")
        if re.search(r'compileOptions\s*\{', s):
            s = re.sub(r'compileOptions\s*\{\s*\n(\s*(?:is)?[Ss]ourceCompatibility[^\n]*\n\s*(?:is)?[Tt]argetCompatibility[^\n]*\n)?',
                       block, s, count=1)
        else:
            s = re.sub(r'(android\s*\{\s*\n)', r'\1    ' + block + '    }\n\n', s, count=1)

    # kotlin jvmTarget must match
    s = re.sub(r'jvmTarget\s*=\s*JavaVersion\.VERSION_\d+\.toString\(\)',
               'jvmTarget = JavaVersion.VERSION_17.toString()', s)
    s = re.sub(r'jvmTarget\s*=\s*"\d+"', 'jvmTarget = "17"', s)

    # dependencies { coreLibraryDesugaring ... }
    if "coreLibraryDesugaring(" not in s and "coreLibraryDesugaring " not in s:
        dep = (f'    coreLibraryDesugaring("{DESUGAR_LIB}")\n' if kts
               else f'    coreLibraryDesugaring "{DESUGAR_LIB}"\n')
        if re.search(r'^dependencies\s*\{', s, re.M):
            s = re.sub(r'^(dependencies\s*\{\s*\n)', r'\1' + dep, s, count=1, flags=re.M)
        else:
            s = s.rstrip() + "\n\ndependencies {\n" + dep + "}\n"

    # release signing from key.properties, else keep the debug key so the APK still installs
    if "key.properties" not in s:
        if kts:
            prelude = (
                'import java.util.Properties\n'
                'import java.io.FileInputStream\n\n'
                'val keystoreProperties = Properties()\n'
                'val keystorePropertiesFile = rootProject.file("key.properties")\n'
                'if (keystorePropertiesFile.exists()) {\n'
                '    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n'
                '}\n\n')
            signing = (
                '    signingConfigs {\n'
                '        create("release") {\n'
                '            if (keystorePropertiesFile.exists()) {\n'
                '                keyAlias = keystoreProperties["keyAlias"] as String\n'
                '                keyPassword = keystoreProperties["keyPassword"] as String\n'
                '                storeFile = file(keystoreProperties["storeFile"] as String)\n'
                '                storePassword = keystoreProperties["storePassword"] as String\n'
                '            }\n'
                '        }\n'
                '    }\n\n')
            release_sel = ('            signingConfig = if (keystorePropertiesFile.exists()) '
                           'signingConfigs.getByName("release") else signingConfigs.getByName("debug")\n')
        else:
            prelude = (
                'def keystoreProperties = new Properties()\n'
                'def keystorePropertiesFile = rootProject.file("key.properties")\n'
                'if (keystorePropertiesFile.exists()) {\n'
                '    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n'
                '}\n\n')
            signing = (
                '    signingConfigs {\n'
                '        release {\n'
                '            if (keystorePropertiesFile.exists()) {\n'
                '                keyAlias keystoreProperties["keyAlias"]\n'
                '                keyPassword keystoreProperties["keyPassword"]\n'
                '                storeFile file(keystoreProperties["storeFile"])\n'
                '                storePassword keystoreProperties["storePassword"]\n'
                '            }\n'
                '        }\n'
                '    }\n\n')
            release_sel = ('            signingConfig keystorePropertiesFile.exists() ? '
                           'signingConfigs.release : signingConfigs.debug\n')

        # Gradle requires plugins {} to be the first statement in the script, so the keystore
        # loading goes AFTER that block (imports may still sit at the very top in the Kotlin DSL).
        m = re.search(r'plugins\s*\{\s*\n(?:[^}]*\n)*?\}\s*\n', s)
        if m:
            if kts:
                imports, prelude = prelude.split('\n\n', 1)
                s = imports + '\n\n' + s[:m.end()] + '\n' + prelude + s[m.end():]
            else:
                s = s[:m.end()] + '\n' + prelude + s[m.end():]
        else:
            s = prelude + s
        s = re.sub(r'(android\s*\{\s*\n)', r'\1' + signing, s, count=1)
        # replace whatever signingConfig line flutter put in buildTypes { release { ... } }
        s = re.sub(r'\n\s*signingConfig\s*=?\s*signingConfigs\.(getByName\("debug"\)|debug)\s*\n',
                   '\n' + release_sel, s, count=1)

    s = disable_minify(s, kts)
    write(path, s)
    write_proguard(android_dir)


PROGUARD = '''# X9: keep the ML Kit barcode scanner (mobile_scanner) intact. R8 removes parts of it in release builds, which shows up
# in the app as "Attempt to invoke virtual method ... on a null object reference" and a camera that never starts.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class dev.steenbakker.mobile_scanner.** { *; }
-dontwarn com.google.mlkit.**
'''


def disable_minify(s, kts):
    """Release builds of the X9 apps are not shrunk by R8 (it breaks the QR scanner); also point R8 at the keep rules."""
    if "X9 no-minify" in s:
        return s
    if kts:
        add = ('            // X9 no-minify: R8 strips ML Kit classes the QR scanner needs\n'
               '            isMinifyEnabled = false\n'
               '            isShrinkResources = false\n'
               '            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")\n')
    else:
        add = ('            // X9 no-minify: R8 strips ML Kit classes the QR scanner needs\n'
               '            minifyEnabled false\n'
               '            shrinkResources false\n'
               "            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'\n")
    s2 = re.sub(r'(buildTypes\s*\{\s*\n\s*(?:getByName\("release"\)|release)\s*\{\s*\n)', lambda m: m.group(1) + add, s, count=1)
    return s2


def write_proguard(android_dir):
    p = os.path.join(android_dir, "app", "proguard-rules.pro")
    write(p, PROGUARD)


MARK = "X9 plugin compileSdk fix"

KTS_FIX = """
// --- X9 plugin compileSdk fix ---
// Some plugins (geocoding_android, ...) still compile against android-33 while their AndroidX dependencies need 34+.
// Raise every library module to at least the app module's compileSdk (never lower anything).
// Plain Kotlin function (no Action lambda): `it` is not available in Gradle's receiver lambdas.
subprojects {
    val x9Sub: Project = this
    val x9Sdk: (Any) -> Int = { e ->
        ((e.javaClass.getMethod("getCompileSdkVersion").invoke(e) as? String) ?: "")
            .removePrefix("android-").toIntOrNull() ?: 0
    }
    val x9Raise: (Project) -> Unit = { p ->
        val ext = p.extensions.findByName("android")
        if (p.name != "app" && ext != null) {
            try {
                val appExt = p.rootProject.findProject(":app")?.extensions?.findByName("android")
                val want = maxOf(35, if (appExt != null) x9Sdk(appExt) else 0)
                if (x9Sdk(ext) < want) {
                    ext.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType).invoke(ext, want)
                }
            } catch (e: Throwable) {
                println("X9 compileSdk fix skipped for " + p.name + ": " + e.message)
            }
        }
    }
    if (x9Sub.state.executed) x9Raise(x9Sub) else x9Sub.afterEvaluate { x9Raise(x9Sub) }
}
"""

GROOVY_FIX = """
// --- X9 plugin compileSdk fix ---
subprojects {
    def x9Raise = { p ->
        if (p.name != 'app' && p.extensions.findByName('android') != null) {
            try {
                def ext = p.extensions.findByName('android')
                def appExt = rootProject.findProject(':app')?.extensions?.findByName('android')
                int appSdk = appExt ? (appExt.compileSdkVersion.toString().replace('android-', '') as int) : 0
                int cur = ext.compileSdkVersion.toString().replace('android-', '') as int
                int want = Math.max(35, appSdk)
                if (cur < want) { ext.compileSdkVersion want }
            } catch (Throwable t) { println("X9 compileSdk fix skipped for ${p.name}: ${t.message}") }
        }
    }
    if (project.state.executed) { x9Raise(project) } else { project.afterEvaluate { x9Raise(project) } }
}
"""


def patch_root(android_dir):
    """Root build file: lift plugin modules that compile against an old android-NN."""
    for name, kts in (("build.gradle.kts", True), ("build.gradle", False)):
        path = os.path.join(android_dir, name)
        if os.path.exists(path):
            s = read(path)
            if MARK in s:  # replace an earlier version of the block (it is always the last thing in the file)
                s = s[:s.index("// --- " + MARK + " ---")].rstrip()
            write(path, s.rstrip() + "\n" + (KTS_FIX if kts else GROOVY_FIX))
            return
    print("  no root build.gradle(.kts); compileSdk fix skipped")


def patch_manifest_label(android_dir, label):
    """flutter create may rewrite android:label; put the X9 name back."""
    path = os.path.join(android_dir, "app/src/main/AndroidManifest.xml")
    if not os.path.exists(path):
        return
    s = read(path)
    new = re.sub(r'android:label="[^"]*"', f'android:label="{label}"', s, count=1)
    if new != s:
        write(path, new)


def enable_google_services(android_dir):
    """Apply the Firebase Gradle plugin, only when google-services.json is present."""
    spath, skts = settings_file(android_dir)
    s = read(spath)
    if "com.google.gms.google-services" not in s:
        if skts:
            line = f'    id("com.google.gms.google-services") version "{GOOGLE_SERVICES_PLUGIN}" apply false\n'
        else:
            line = f'    id "com.google.gms.google-services" version "{GOOGLE_SERVICES_PLUGIN}" apply false\n'
        m = re.search(r'plugins\s*\{\s*\n', s)
        if m:
            s = s[:m.end()] + line + s[m.end():]
            write(spath, s)
        else:
            print("  settings.gradle has no plugins block; skipping (old-style Flutter project)")

    apath, akts = app_build_file(android_dir)
    a = read(apath)
    if "com.google.gms.google-services" not in a:
        line = ('    id("com.google.gms.google-services")\n' if akts
                else '    id "com.google.gms.google-services"\n')
        # Must be applied AFTER com.android.application, so append at the end of the plugins block.
        m = re.search(r'plugins\s*\{\s*\n(?:[^}]*\n)*?\}', a)
        if m:
            close = a.rindex('}', m.start(), m.end())
            a = a[:close] + line + a[close:]
        else:
            a = a.rstrip() + ("\napply(plugin = \"com.google.gms.google-services\")\n" if akts
                              else "\napply plugin: 'com.google.gms.google-services'\n")
        write(apath, a)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True, help="the android/ directory")
    ap.add_argument("--application-id")
    ap.add_argument("--label")
    ap.add_argument("--enable-google-services", action="store_true")
    args = ap.parse_args()

    if args.enable_google_services:
        enable_google_services(args.dir)
        return
    if not args.application_id:
        sys.exit("--application-id is required")
    patch_app(args.dir, args.application_id, args.label)
    patch_root(args.dir)
    if args.label:
        patch_manifest_label(args.dir, args.label)


if __name__ == "__main__":
    main()
