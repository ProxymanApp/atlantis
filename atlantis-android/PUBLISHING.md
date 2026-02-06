# Publishing Atlantis Android

This guide explains how to publish the Atlantis Android library to Maven Central and JitPack.

## Prerequisites

- JDK 17+
- Gradle 8.x
- GPG key for signing (Maven Central only)
- Sonatype OSSRH account (Maven Central only)

---

## Option 1: JitPack (Recommended for Quick Setup)

JitPack automatically builds and publishes your library from GitHub releases. No account setup required.

### Steps

1. **Create a GitHub Release**

   ```bash
   # Tag the release
   git tag -a v1.0.0 -m "Release version 1.0.0"
   git push origin v1.0.0
   ```

2. **Create Release on GitHub**
   - Go to your repository on GitHub
   - Click "Releases" → "Create a new release"
   - Select the tag `v1.0.0`
   - Add release notes
   - Publish the release

3. **Wait for JitPack Build**
   - Visit `https://jitpack.io/#ProxymanApp/atlantis`
   - JitPack will automatically build when someone requests the dependency
   - First build may take a few minutes

4. **Users can now add the dependency:**

   ```kotlin
   // settings.gradle.kts
   dependencyResolutionManagement {
       repositories {
           maven { url = uri("https://jitpack.io") }
       }
   }

   // build.gradle.kts
   dependencies {
       implementation("com.github.ProxymanApp:atlantis:v1.0.0")
   }
   ```

### JitPack Configuration

JitPack uses `jitpack.yml` for custom build configuration (optional):

```yaml
# jitpack.yml (place in atlantis-android/ folder)
jdk:
  - openjdk17
install:
  - cd atlantis-android && ./gradlew :atlantis:publishToMavenLocal
```

---

## Option 2: Maven Central

Publishing to Maven Central requires more setup but provides better discoverability and CDN distribution.

### 1. Create Sonatype OSSRH Account

1. Create a Sonatype JIRA account at https://issues.sonatype.org
2. Create a "New Project" ticket requesting access to your group ID
3. Wait for approval (usually 1-2 business days)

### 2. Configure GPG Signing

```bash
# Generate GPG key
gpg --full-generate-key

# List keys to get key ID
gpg --list-keys --keyid-format LONG

# Export public key to keyserver
gpg --keyserver keyserver.ubuntu.com --send-keys YOUR_KEY_ID

# Export private key for CI (store securely)
gpg --export-secret-keys YOUR_KEY_ID | base64 > private-key.gpg.b64
```

### 3. Configure `gradle.properties`

Create/update `~/.gradle/gradle.properties` (NOT in version control):

```properties
# Sonatype credentials
ossrhUsername=your-sonatype-username
ossrhPassword=your-sonatype-password

# GPG signing
signing.keyId=YOUR_KEY_ID_LAST_8_CHARS
signing.password=your-gpg-passphrase
signing.secretKeyRingFile=/path/to/secring.gpg
```

### 4. Update `build.gradle.kts`

Add Maven Central publishing configuration to `atlantis/build.gradle.kts`:

```kotlin
plugins {
    // ... existing plugins
    id("signing")
}

// Add to afterEvaluate block
afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                from(components["release"])
                
                groupId = "com.proxyman"
                artifactId = "atlantis-android"
                version = project.findProperty("VERSION_NAME") as String? ?: "1.0.0"
                
                pom {
                    name.set("Atlantis Android")
                    description.set("Capture HTTP/HTTPS traffic from Android apps and send to Proxyman for debugging")
                    url.set("https://github.com/ProxymanApp/atlantis")
                    
                    licenses {
                        license {
                            name.set("Apache License, Version 2.0")
                            url.set("https://www.apache.org/licenses/LICENSE-2.0.txt")
                        }
                    }
                    
                    developers {
                        developer {
                            id.set("proxymanllc")
                            name.set("Proxyman LLC")
                            email.set("support@proxyman.com")
                        }
                    }
                    
                    scm {
                        url.set("https://github.com/ProxymanApp/atlantis")
                        connection.set("scm:git:git://github.com/ProxymanApp/atlantis.git")
                        developerConnection.set("scm:git:ssh://git@github.com/ProxymanApp/atlantis.git")
                    }
                }
            }
        }
        
        repositories {
            maven {
                name = "sonatype"
                val releasesRepoUrl = uri("https://s01.oss.sonatype.org/service/local/staging/deploy/maven2/")
                val snapshotsRepoUrl = uri("https://s01.oss.sonatype.org/content/repositories/snapshots/")
                url = if (version.toString().endsWith("SNAPSHOT")) snapshotsRepoUrl else releasesRepoUrl
                
                credentials {
                    username = findProperty("ossrhUsername") as String? ?: ""
                    password = findProperty("ossrhPassword") as String? ?: ""
                }
            }
        }
    }
    
    signing {
        sign(publishing.publications["release"])
    }
}
```

### 5. Publish to Maven Central

```bash
cd atlantis-android

# Publish to staging repository
./gradlew :atlantis:publishReleasePublicationToSonatypeRepository

# Or publish all publications
./gradlew :atlantis:publishAllPublicationsToSonatypeRepository
```

### 6. Release from Staging

1. Log in to https://s01.oss.sonatype.org
2. Go to "Staging Repositories"
3. Find your repository (named `comproxyman-XXXX`)
4. Click "Close" and wait for validation
5. If validation passes, click "Release"
6. Wait 10-30 minutes for sync to Maven Central

---

## CI/CD with GitHub Actions

### JitPack (Automatic)

JitPack works automatically with GitHub releases - no CI configuration needed.

### Maven Central with GitHub Actions

Create `.github/workflows/publish.yml`:

```yaml
name: Publish to Maven Central

on:
  release:
    types: [published]

jobs:
  publish:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
          
      - name: Setup Gradle
        uses: gradle/gradle-build-action@v2
        
      - name: Decode GPG Key
        run: |
          echo "${{ secrets.GPG_PRIVATE_KEY }}" | base64 --decode > private-key.gpg
          gpg --import private-key.gpg
          
      - name: Publish to Maven Central
        working-directory: atlantis-android
        env:
          OSSRH_USERNAME: ${{ secrets.OSSRH_USERNAME }}
          OSSRH_PASSWORD: ${{ secrets.OSSRH_PASSWORD }}
          SIGNING_KEY_ID: ${{ secrets.SIGNING_KEY_ID }}
          SIGNING_PASSWORD: ${{ secrets.SIGNING_PASSWORD }}
        run: |
          ./gradlew :atlantis:publishReleasePublicationToSonatypeRepository \
            -PossrhUsername=$OSSRH_USERNAME \
            -PossrhPassword=$OSSRH_PASSWORD \
            -Psigning.keyId=$SIGNING_KEY_ID \
            -Psigning.password=$SIGNING_PASSWORD \
            -Psigning.secretKeyRingFile=$HOME/.gnupg/secring.gpg
```

### Required GitHub Secrets

Add these secrets to your repository settings:

- `GPG_PRIVATE_KEY`: Base64-encoded GPG private key
- `OSSRH_USERNAME`: Sonatype username
- `OSSRH_PASSWORD`: Sonatype password
- `SIGNING_KEY_ID`: Last 8 characters of GPG key ID
- `SIGNING_PASSWORD`: GPG key passphrase

---

## Version Management

### Updating Version

Update `gradle.properties`:

```properties
VERSION_NAME=1.1.0
VERSION_CODE=2
```

### Version Naming Convention

- `1.0.0` - Initial release
- `1.0.1` - Bug fixes
- `1.1.0` - New features (backward compatible)
- `2.0.0` - Breaking changes

### Snapshot Releases

For development versions, use `-SNAPSHOT` suffix:

```properties
VERSION_NAME=1.1.0-SNAPSHOT
```

Publish to snapshot repository:

```bash
./gradlew :atlantis:publishReleasePublicationToSonatypeRepository
```

---

## Verification

### Check Maven Central

After publishing, verify your artifact is available:

```bash
# Check Maven Central
curl -s "https://repo1.maven.org/maven2/com/proxyman/atlantis-android/maven-metadata.xml"

# Or search on search.maven.org
# https://search.maven.org/search?q=g:com.proxyman%20AND%20a:atlantis-android
```

### Check JitPack

Visit: `https://jitpack.io/#ProxymanApp/atlantis`

---

## Troubleshooting

### "Could not find artifact" on JitPack

1. Check build logs at `https://jitpack.io/#ProxymanApp/atlantis`
2. Ensure `build.gradle.kts` is in the correct location
3. Try rebuilding by clicking "Get it" again

### GPG Signing Errors

1. Ensure GPG key is not expired
2. Check that the key is uploaded to keyserver
3. Verify key ID and passphrase are correct

### Sonatype Validation Failures

Common issues:
- Missing POM information (name, description, URL, SCM)
- Missing Javadoc JAR
- Missing Sources JAR
- Invalid signature

Check the staging repository "Activity" tab for specific errors.

---

## Support

For publishing issues, contact:
- JitPack: https://github.com/jitpack/jitpack.io/issues
- Sonatype: https://central.sonatype.org/support/
- Atlantis: https://github.com/ProxymanApp/atlantis/issues
