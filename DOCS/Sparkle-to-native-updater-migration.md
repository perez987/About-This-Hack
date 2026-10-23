# Migrating Sparkle 5.1.2 installations to the native updater

Existing About This Hack 5.1.2 installations can update to 5.1.3 without changing or rebuilding the installed 5.1.2 apps. Publish the 5.1.3 release information at the old feed URLs that those apps already check.

Sparkle in the installed 5.1.2 app downloads and installs the replacement app. The replacement does not need to contain Sparkle. After relaunching, 5.1.3 uses its native updater and its new feed URL.

These instructions are for the developer publishing the migration. For release signing and key management, see [Native updater: signing keys and release publishing](Native-updater-signing.md).

## Feed configuration

All feed URLs below are relative to:

`https://raw.githubusercontent.com/perez987/About-This-Hack/main/`

| Feed | Installed clients | Edition |
| --- | --- | --- |
| `appcast-6.xml` | 5.1.2 with Sparkle | Standard, without liquid glass |
| `appcast-6glass.xml` | 5.1.2 with Sparkle | Liquid glass |
| `appcast-ath.xml` | 5.1.3 with the native updater | Standard, without liquid glass |
| `appcast-glass-ath.xml` | 5.1.3 with the native updater | Liquid glass |
| `appcast.xml` | Legacy 4.5.0, for macOS 13+ | Legacy; leave unchanged |

The old and new feeds use Sparkle-compatible RSS XML. No HTTP redirect, XML redirect element, or intermediate application release is necessary.

## 1. Confirm release compatibility

Before changing the feeds, confirm the following for both editions:

- The 5.1.3 app has `CFBundleVersion` **1663**, greater than 5.1.2's **1662**, and `CFBundleShortVersionString` **5.1.3**. The appcast values must match the app inside the DMG.
- The appcast's minimum macOS version matches the replacement app's requirements. The current 5.1.3 feeds specify **15.6**.
- The final DMG is signed with the Ed25519 private key corresponding to the installed 5.1.2 app's `SUPublicEDKey`. A working native update alone does not prove compatibility if the signing key changed.
- The replacement preserves the edition's bundle identifier and valid Apple code-signing identity, and the expected app is at the DMG's root. Retain notarization and stapling as part of release publishing.
- The replacement's `ATHUpdatePublicEDKey` matches the key used to sign future native updates.
- The replacement's `ATHUpdateFeedURL` points to `appcast-ath.xml` for standard or `appcast-glass-ath.xml` for glass.
- Both published 5.1.3 DMGs are downloadable, and each enclosure contains the signature and exact byte length for that specific DMG.

Do not reuse the 5.1.2 signature or byte length. Do not modify or repackage a DMG after signing it; any byte change requires a new signature and length.

## 2. Publish 5.1.3 through the old feeds

In a checkout of **`perez987/About-This-Hack`**, copy each native feed to its corresponding old Sparkle feed:

```sh
cp appcast-ath.xml appcast-6.xml
cp appcast-glass-ath.xml appcast-6glass.xml

git diff -- appcast-6.xml appcast-6glass.xml
```

Review the changes, then commit and publish them to that repository's `main` branch using the normal review process.

| Feed requested by 5.1.2 | Copy contents from |
| --- | --- |
| `appcast-6.xml` | `appcast-ath.xml` |
| `appcast-6glass.xml` | `appcast-glass-ath.xml` |

Copy the complete feed, including the 5.1.3 download URL, signature, byte length, build number, display version, and minimum macOS version. Keep standard and glass downloads separate.

**Updating copies only in `perez987/About-This-Hack-glass` does not affect installed apps requesting feeds from `perez987/About-This-Hack`.** The files must be published at the exact URLs embedded in the installed 5.1.2 apps.

Leave `appcast.xml` unchanged.

## 3. Verify both migration paths

After publishing, inspect the raw contents of both old feed URLs to confirm they advertise 5.1.3. Allow for hosting cache propagation before testing.

Test on a Mac supported by the replacement release, using the actual released, signed apps installed in a writable Applications location, not running from a DMG or App Translocation:

1. Launch the released **5.1.2 standard app**, choose **Check for Updates**, and confirm it offers 5.1.3.
2. Install the update and confirm the app relaunches as **5.1.3 standard**, preserving the standard appearance.
3. Confirm the installed app's `ATHUpdateFeedURL` points to `appcast-ath.xml`, and check for updates using its native updater.
4. Repeat with the released **5.1.2 glass app**. Confirm it installs **5.1.3 glass**, preserves the glass appearance, and uses `appcast-glass-ath.xml` afterward.

The resulting paths are:

```text
5.1.2 standard -> appcast-6.xml      -> 5.1.3 standard -> appcast-ath.xml
5.1.2 glass    -> appcast-6glass.xml -> 5.1.3 glass    -> appcast-glass-ath.xml
```

Here, automatic updating means that existing installations can discover the update through their configured Sparkle checks. Users with automatic checks disabled must check manually. Download and installation follow the installed app's existing Sparkle settings and prompts; changing the feed does not force a silent installation.

## 4. Keep the migration bridge available

Keep `appcast-6.xml` and `appcast-6glass.xml` available indefinitely. They can remain fixed at 5.1.3 as permanent migration bridges, while future releases update only the native feeds.

Keep the referenced 5.1.3 DMGs available as well. Users returning much later can then migrate through 5.1.3 before discovering newer releases through the native updater, subject to their macOS compatibility.

Do not delete the old feeds or assume all 5.1.2 installations have already upgraded.
