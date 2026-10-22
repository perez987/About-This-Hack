## Replace ATHLogger with print statements

Removes the custom `ATHLogger` unified logging system in favour of plain `print` calls. Noisy step-by-step debug traces are dropped; only actionable messages (errors, warnings, key lifecycle events) are kept.

## Changes

- **Deleted** `ATHLogger.swift` and removed its Xcode project references
- **Replaced** all `ATHLogger.*` calls with `print(...)` — untranslated, literal English strings
- **Kept** error/warning prints where failures are meaningful for debugging:
  - Hardware data read failures (CPU, RAM, GPU, display, startup disk, serial)
  - CPU core-count fallback chain warnings
  - Network reachability errors and connectivity status
  - URL open failure in support view
- **Kept** lifecycle prints: `"Application starting"`, `"Application terminating"`, `"Data files created"`
- **Removed** all `log.*` localization keys from `en/fr/es` `Localizable.strings` and cleaned up resulting empty section headers; `loading.data.message` (used in the loading window UI) is retained
- **Added** `print("Checking for updates")` to `UpdaterController.checkForUpdates()`

```swift
func checkForUpdates() {
    print("Checking for updates")
    updaterController.updater.checkForUpdates()
}
```
