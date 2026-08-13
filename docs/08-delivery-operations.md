# Delivery and Operations

## 1. Repository policy

Commit source, project configuration, tools, tests, docs, manifests, and
licensed release assets. Ignore Godot `.godot`, editor caches, temporary files,
logs, APK/AAB outputs, and machine-local configuration. Use Git LFS only after
checking Codespace quota impact.

## 2. Environment

Pin the Godot 4.x version, Android SDK/Build Tools versions, Java version, and
export template version. Provide a dev-container or setup script that verifies
tools without silently downloading large dependencies.

The 32 GB disk is a hard constraint. Keep one build artifact at a time, clean
engine caches deliberately, and fail early with a clear disk-space message.

## 3. CI pipeline

1. Validate repository structure and formatting.
2. Run headless unit, property, integration, and smoke tests.
3. Validate the complete level manifest.
4. Build a debug APK for pull requests.
5. Build a signed release artifact only from an approved tag and protected secrets.
6. Publish checksums and test evidence as artifacts.

## 4. Offline verification

Install the release APK with network disabled. Launch, complete tutorial
actions, start and finish levels, close/reopen the app, change settings, and
verify progression and saves. Automated tests must also fail if unexpected
network calls or network permissions appear.

## 5. Versioning and recovery

Use semantic versions for the app and a separate schema version for save data.
Every release has a rollback decision, known-issues list, checksum, and
reproducible source revision. Never overwrite a valid save during migration
failure; restore the backup and report the issue.
