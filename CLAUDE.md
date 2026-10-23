# About This Hack – Codebase Guide for Claude

## Project Purpose

**About This Hack** is a macOS app that recreates the classic pre-Ventura "About This Mac" window with modern enhancements. It targets both Hackintosh users (PCs running macOS via OpenCore or Clover bootloaders) and real Mac users. It displays hardware info (CPU, RAM, GPU, displays, storage, audio codec), bootloader version, serial number, and support links.

- macOS 15 (Sequoia) minimum deployment target
- Swift 6 + SwiftUI UI (migrated from AppKit/XIB)
- Storyboard-free (AppDelegate bootstraps everything manually)
- Native auto-updater via Foundation, CryptoKit, and Security (no Sparkle runtime dependency)
- Localized into: English (`en`), Spanish (`es`), German (`de`), French (`fr`), Italian (`it`), Russian (`ru`)
- Transparent/liquid-glass window style (`.ultraThinMaterial` / `.regularMaterial` backgrounds)

## Tech Stack

| Area | Technology |
|---|---|
| Language | Swift 6 |
| UI framework | SwiftUI (macOS 15+) |
| App lifecycle | AppKit (`NSApplicationDelegate`, no storyboard) |
| Auto-updater | Native `UpdaterController` with signed RSS appcast, Ed25519 verification, and Apple code-signing checks |
| Shell execution | Custom `run(_ command: String) -> String` via `/bin/zsh` subprocess |
| Localization | `NSLocalizedString` + `.strings` files per language |
| Persistence | `UserDefaults.standard` (window frame, custom logo path, language) |
| IPC / system data | `system_profiler`, `diskutil`, `nvram`, `sw_vers`, `sysctlbyname`, IOKit, `/bin/zsh` subprocesses |

## Repository Layout

```
About-This-Hack/
├── CLAUDE.md                          ← this file
├── README.md
├── DOCS/                              ← Developer documentation (markdown)
│   ├── AppKit-XIB-to-SwiftUI.md
│   ├── ATHLogger-to-print.md
│   ├── App-damaged.md
│   ├── Console-warning.md
│   ├── Replace-custom-logo.md
│   ├── Transparent-windows.md
│   └── appcast-backup.xml
├── Images/                            ← README screenshots (not bundled)
├── Releases-changelog.md
├── appcast.xml
├── appcast-glass.xml
└── About This Hack/                   ← All source code
    ├── AppDelegate.swift              ← App entry point, window/menu setup
    ├── HardwareCollector.swift        ← Central data collector (singleton)
    ├── About_This_Hack.entitlements
    ├── Info.plist
    ├── Assets.xcassets/               ← Images (OS badges, disk icons, display icons)
    ├── HardwareCollectors/            ← Individual hardware data collectors
    │   ├── HCAudio.swift
    │   ├── HCBootloader.swift
    │   ├── HCCPU.swift
    │   ├── HCDisplay.swift
    │   ├── HCGPU.swift
    │   ├── HCMacModel.swift
    │   ├── HCRAM.swift
    │   ├── HCSerialNumber.swift
    │   ├── HCStartupDisk.swift
    │   └── HCVersion.swift
    ├── Models/                        ← Shared state, data init, utilities
    │   ├── CreateDataFiles.swift      ← Async creation of temp data files
    │   ├── InitGlobalVariables.swift  ← All global constants and paths
    │   ├── LoadingIndicatorController.swift
    │   ├── SystemFunctions.swift      ← getSysctlValueByKey(), IOKit port helpers, Bundle ext.
    │   ├── Tooltips.swift             ← Lazy tooltip strings (expensive to compute)
    │   ├── UpdateController.swift     ← Native updater, feed parser, verification, install helper
    ├── Utilities/                     ← Small helpers
    │   ├── CustomLogoConstants.swift  ← UserDefaults key + Notification.Name
    │   ├── InsertExtension.swift      ← String/Data extensions
    │   ├── Reachability.swift         ← Network reachability helper
    │   └── Shell.swift                ← run() function definition
    ├── Views/                         ← All SwiftUI views + AppState
    │   ├── ContentView.swift          ← Root view: LoadingView or FakeSidebarLayout
    │   ├── ViewController.swift       ← OverviewView + OverviewViewModel
    │   ├── ViewControllerDisplays.swift ← DisplaysView + DisplaysViewModel
    │   ├── ViewControllerStorage.swift  ← StorageView + StorageViewModel
    │   ├── ViewControllerAudio.swift    ← AudioView + AudioViewModel
    │   ├── ViewControllerSupport.swift  ← SupportView
    │   ├── SettingsView.swift           ← Settings window (custom logo)
    │   ├── SettingsWindowController.swift
    │   ├── LanguageSelectorView.swift
    │   ├── LanguageSelectorWindowController.swift
    │   └── WindowController.swift       ← AppState: ObservableObject shared state
    └── {en,es,fr,it,de,ru}.lproj/
        └── Localizable.strings
```

## Architecture & Data Flow

### Startup sequence

```
AppDelegate.init()
  ├── AppState.shared: registers DataFilesCreated notification observer
  │     and checks CreateDataFiles.dataFilesCreated in case files are already ready
  └── CreateDataFiles.getInitDataFilesAsync { }
        └── background thread: runs system_profiler / diskutil commands
              → writes temp files to InitGlobVar.athDirectory (`FileManager.default.temporaryDirectory/.ath`)
              → posts DataFilesCreatedNotification

AppState receives DataFilesCreatedNotification
  └── loadDataAsync()
        └── background thread: HardwareCollector.shared.getAllData()
              ├── prefetches temp files into in-memory cache
              ├── runs system_profiler SPDisplaysDataType (no file; stored in cache)
              ├── calls every HC*.shared.getXxx() to pre-warm lazy vars
              └── sets dataHasBeenSet = true
        → main thread: AppState.isDataLoaded = true → ContentView switches to FakeSidebarLayout
```

### Key singletons

| Singleton | Role |
|---|---|
| `AppState.shared` | `ObservableObject` injected via `.environmentObject`. Drives navigation (`selectedSection`), loading state (`isDataLoaded`), sidebar visibility (`isSidebarVisible`). Also determines `isHackintosh` and `shouldShowAudioTab`. Persists window frame via `savedWindowFrame(for:)` / `saveWindowFrame(_:)`. |
| `HardwareCollector.shared` | Central cache. Holds parsed display/storage arrays. `getCachedFileContent(_:)` reads temp files once and caches them. `storeCachedFileContent(_:content:)` populates the cache directly (used for SPDisplaysDataType). |
| `HCVersion.shared` | OS version string, build number, `MacOSVersion` enum (`.sierra`→`.tahoe`), OS image name. |
| `HCCPU.shared` | CPU brand string and info. |
| `HCRAM.shared` | RAM size string. |
| `HCGPU.shared` | GPU name and info (lazy, reset-able). |
| `HCDisplay.shared` | Primary display summary string (lazy, reset-able). |
| `HCMacModel.shared` | Mac model name + model identifier. |
| `HCSerialNumber.shared` | Serial number + hardware info tooltip. |
| `HCStartupDisk.shared` | Boot volume name + info. |
| `HCBootloader.shared` | Bootloader string (OpenCore/Clover/Apple iBoot/Apple UEFI) + boot-args. Both are `lazy var`. |
| `HCAudio.shared` | Audio codec info (driver, codec, vendor, device, layout). |
| `Tooltips.shared` | Lazy tooltip strings used by OverviewViewModel. |

### Navigation

`AppSection` enum (`.overview`, `.displays`, `.storage`, `.audio`, `.support`) is the navigation token. It lives in `AppState.selectedSection`. `ContentView` (via `FakeSidebarLayout`) switches the detail panel by reading this value. The macOS `Window` menu items call `AppDelegate` actions that write to `AppState.selectedSection` directly.

The sidebar is a plain `HStack` (not `NavigationSplitView`), to avoid tap-event reliability issues on macOS Tahoe.

### View / ViewModel pattern

Each tab's view file contains both the SwiftUI `View` struct and a `ViewModel` struct/class:

- `OverviewView` + `OverviewViewModel: ObservableObject` (class, `@StateObject`). Includes a `SerialRow` private struct with show/hide toggle (`isSerialHidden: Bool`).
- `DisplaysView` + `DisplaysViewModel` (enum with static factory)
- `StorageView` + `StorageViewModel` (plain struct)
- `AudioView` + `AudioViewModel` (plain struct)
- `SupportView` (no dedicated VM, links are inline)
- `SettingsView` + `SettingsViewModel: ObservableObject`

### Shell execution

All subprocess calls go through `run(_ command: String) -> String` in `Shell.swift`. It launches `/bin/zsh -c <command>`, reads stdout, and returns the result. **Important:** `waitUntilExit()` is intentionally NOT called (see comment in `Shell.swift`) – `readDataToEndOfFile()` already blocks until the subprocess closes stdout, and calling `waitUntilExit()` would additionally spin the RunLoop, allowing nested SwiftUI updates to fire during a render pass and trigger "setting value during update" assertion crashes. All `run()` calls must happen on background threads.

## Temp Files

Data is collected into `InitGlobVar.athDirectory` (`FileManager.default.temporaryDirectory/.ath`) inside the app sandbox temp container and deleted on termination.

| File path constant | Content |
|---|---|
| `InitGlobVar.hwFilePath` | `system_profiler SPHardwareDataType` |
| `InitGlobVar.sysmemFilePath` | `system_profiler SPMemoryDataType` |
| `InitGlobVar.bootvolnameFilePath` | `diskutil info /` |
| `InitGlobVar.bootvollistFilePath` | `diskutil list /` |
| `InitGlobVar.storagedataFilePath` | `system_profiler SPStorageDataType` |
| `InitGlobVar.scrFilePath` | Virtual key – `system_profiler SPDisplaysDataType` result is stored directly into the `HardwareCollector` cache under this key (never written to disk) |
| `InitGlobVar.oclpXmlFilePath` | `/System/Library/CoreServices/OpenCore-Legacy-Patcher.plist` (system file, read-only) |

## Audio Tab Visibility

The Audio tab is only shown on Hackintoshes or Macs with OCLP / OpenCore:

1. `AppState.isHackintosh` → true when bootloader is Clover; true when bootloader is OpenCore without OCLP; true when bootloader is OpenCore with OCLP **and** `HCAudio` reports an expected driver (`AppleALC`, `VoodooHDA`, `HDAUniversal`, `USB`, `HDMI`, or `DisplayPort`). Returns false on Apple iBoot (Apple Silicon) or Apple UEFI (real Intel Mac without OpenCore).
2. `AppState.shouldShowAudioTab` → true when `isHackintosh` AND `HCAudio` reports driver = `AppleALC`, `VoodooHDA`, `HDAUniversal`, `USB`, `HDMI`, or `DisplayPort`.
3. The `Audio` menu item in AppDelegate is also validated against `shouldShowAudioTab`.

## Localization

- All user-facing strings use `NSLocalizedString("key", comment: "…")`.
- String files live at `{lang}.lproj/Localizable.strings`.
- Supported languages: `en`, `es`, `de`, `fr`, `it`, `ru`.
- Language is changed at runtime by writing `[langCode]` to `UserDefaults "AppleLanguages"` and restarting the app. The Language Selector window (`LanguageSelectorView`) handles this.
- When adding a new string, add it to all six `.strings` files. The key in every file must match exactly.

## Assets

Assets are in `Assets.xcassets`. Notable image sets:

- `Golden Gate`, `Tahoe`, `Sequoia`, `Sonoma`, `Ventura`, `Monterey`, `Big Sur`, etc. – OS badge images used in Overview.
- `{OS} Internal SSD`, `{OS} External SSD`, `{OS} Internal HDD`, `{OS} External HDD` – Storage tab disk icons.
- `genericMacBook`, `genericMacBook{BigSur,Monterey,Ventura,Sonoma,Sequoia,Tahoe,GoldenGate}` – Built-in / MacBook display icons (one per macOS version, selected at runtime by `genericMacBookImageNameForCurrentOS()`).
-  `genericLCD`, `genericLCD{BigSur,Monterey,Ventura,Sonoma,Sequoia,Tahoe,GoldenGate}` – Generic internal LCD icons (one per macOS version, selected at runtime by `genericLCDImageNameForCurrentOS()`).
- `genericImac`, `genericImac{BigSur,Monterey,Ventura,Sonoma,Sequoia,Tahoe,GoldenGate}` – Generic internal Imac icons (one per macOS version, selected at runtime by `genericImacImageNameForCurrentOS()`).
- `iPad` – Specific external display icon.
- `Audio` – Audio tab icon.
- `AppIcon` – App icon.

## Settings (Custom Logo)

- The Settings window (`⌘,`) lets users drag-drop a 1024×1024 PNG to replace the macOS badge in Overview.
- The dropped image is **copied** into the app's Application Support folder (`customLogo.png`) via `CustomLogoConstants.savedLogoURL`, so it persists across app runs within the sandbox. The path to that copy is saved to `UserDefaults` under key `"customLogoPath"` (`CustomLogoConstants.customLogoPathKey`).
- On reset, the copy is deleted from Application Support and the `UserDefaults` entry is removed.
- A `Notification.Name.customLogoDidChange` notification is posted when the logo changes; `OverviewViewModel` listens and reloads.

## Native Auto-Updater

- `UpdaterController` uses Foundation, CryptoKit, and Security; there is no Sparkle SPM dependency.
- `ATHUpdateFeedURL` in `Info.plist` and `UpdateSecurity.feedURL` must both point to `https://raw.githubusercontent.com/perez987/About-This-Hack/main/appcast-ath.xml`.
- Only `About.This.Hack.VERSION.dmg` downloads from `perez987/About-This-Hack` releases are accepted. The DMG must contain `About This Hack.app`, not the glass edition.
- The installed version/build come from the bundle. Preserve the existing Ed25519 public key in `ATHUpdatePublicEDKey`; see `DOCS/Native-updater-signing.md` for publishing.
- Weekly automatic checks are opt-in; downloads and installation always require approval. `AppDelegate` starts the scheduler after launching the main window.
- It publishes `canCheckForUpdates` so `AppDelegate.validateMenuItem` can enable/disable the menu item.
- The "Check for Updates…" menu item (`⌘U`) calls `updaterController?.checkForUpdates()`.

## Building

- Open `About This Hack.xcodeproj` in a current Xcode release with Swift 6 support.
- No third-party packages are required for the updater.
- Target: macOS 15+, architecture: universal (Apple Silicon + Intel).
- The `AboutThisHackTests` XCTest target includes:
  - Formatting checks for processor and bootloader output, plus system-version comparison.
  - Localization key parity checks across `en`, `de`, `es`, `fr`, `it`, and `ru`.
  - Live hardware collector checks. These wait up to 60 seconds for `AppState.isDataLoaded` before reading collector values.
  - An audio collector check that runs only when `AppState.shouldShowAudioTab` is true; otherwise XCTest skips it.
- Run the tests from `Xcode-project` with:
  ```sh
  xcodebuild test -project "About This Hack.xcodeproj" -scheme "About This Hack" -destination platform=macOS
  ```
- The app is storyboard-free: `NSPrincipalClass` points to `AppDelegate`, and `AppDelegate.main()` is the entry point (marked `@main`).

## Agent Quickstart (for new tasks)

Use this checklist when starting a new session:

1. Read `README.md` and this file to confirm current behavior and constraints.
2. If touching UI/navigation: inspect `Views/ContentView.swift`, `Views/WindowController.swift`, and `AppDelegate.swift`.
3. If touching hardware data: inspect `HardwareCollector.swift` plus relevant `HardwareCollectors/HC*.swift`.
4. If adding user-visible text: update all `Localizable.strings` files in `en/es/fr/it/de`.
5. If adding shell/system calls: keep them off the main thread and route through `run(_:)`.
6. If changing updater behavior: verify `Models/UpdateController.swift`, native update settings in `Info.plist`, and menu/scheduler wiring in `AppDelegate`.

## Task-to-File Map (fast lookup)

- App lifecycle and menu/actions: `About This Hack/AppDelegate.swift`
- Shared app state and tab routing: `About This Hack/Views/WindowController.swift`
- Root layout / sidebar / detail switching: `About This Hack/Views/ContentView.swift`
- Hardware aggregation cache and preload: `About This Hack/HardwareCollector.swift`
- Startup data file generation: `About This Hack/Models/CreateDataFiles.swift`
- Global constants/paths: `About This Hack/Models/InitGlobalVariables.swift`
- Shell helper: `About This Hack/Utilities/Shell.swift`
- Overview tab: `About This Hack/Views/ViewController.swift`
- Displays tab: `About This Hack/Views/ViewControllerDisplays.swift`
- Storage tab: `About This Hack/Views/ViewControllerStorage.swift`
- Audio tab: `About This Hack/Views/ViewControllerAudio.swift`
- Support tab: `About This Hack/Views/ViewControllerSupport.swift`
- Settings + custom logo flow: `About This Hack/Views/SettingsView.swift`
- Language picker window: `About This Hack/Views/LanguageSelectorView.swift`

## Common Pitfalls

- **Never call `run()` on the main thread.** `waitUntilExit()` is not called, but `readDataToEndOfFile()` still blocks; calling `run()` from a SwiftUI body-evaluation pass on the main thread allows spin-loop interactions with the RunLoop and causes "setting value during update" crashes. Pre-warm all lazy hardware vars in `HardwareCollector.getAllData()` on a background thread.
- **`HardwareCollector.clearCache()` + `reset()`** must be called if hardware data needs to be refreshed (it resets `HCGPU` and `HCDisplay` lazy vars).
- **`HCBootloader` lazy vars** (`bootloaderInfo`, `bootargsInfo`) are expensive (shell calls). They must be pre-warmed on a background thread inside `getAllData()`.
- **`Tooltips._macModeltoolTip`** runs `system_profiler SPPCIDataType` and must be pre-warmed on a background thread (done in `AppState.loadDataAsync()`).
- **Sidebar toggle animation** uses `withAnimation(.easeInOut(duration: 0.25))`. The sidebar and divider use `.transition(.move(edge: .leading))` / `.transition(.opacity)`.
- **`run()` does not call `waitUntilExit()`** by design (see `Shell.swift` comment). `readDataToEndOfFile()` already provides the necessary blocking; adding `waitUntilExit()` would spin the RunLoop. This is intentional and must not be reverted.
- **Transparent window (current default)**: the main window, Settings window, and Language Selector window all use a transparent/liquid-glass setup (`NSWindow.isOpaque = false`, `backgroundColor = .clear`, transparent title bars, and material-backed SwiftUI content). The older opaque-window code paths are still present as comments in some files.
- **`AppSection.audio`** is filtered out of the sidebar list when `shouldShowAudioTab` is false.

## Where to Look for Things

| Need to… | Look in |
|---|---|
| Add/change a hardware data field | `HardwareCollectors/HC*.swift` + update the relevant ViewModel in `Views/ViewController*.swift` |
| Add a new tab | Add a case to `AppSection` in `WindowController.swift`, add a new view file in `Views/`, update `FakeSidebarLayout.detailView`, add menu item in `AppDelegate.createMainMenu()` |
| Change the Language menu | `AppDelegate.insertLanguageMenu()` – inserts a "Language" submenu (⌘L) between the main app menu and the Window menu |
| Change global paths or URLs | `Models/InitGlobalVariables.swift` |
| Add/edit a Localized string | All five `{lang}.lproj/Localizable.strings` |
| Change update checker | `Models/UpdateController.swift` (native updater and `UpdateSecurity` channel restrictions) |
| Change window appearance | `AppDelegate.createAndShowMainWindow()` |
| Change Settings/custom logo logic | `Views/SettingsView.swift` + `Utilities/CustomLogoConstants.swift` |
| Change tooltip content | `Models/Tooltips.swift` |
| Change sidebar navigation model | `Views/WindowController.swift` (AppState + AppSection) |
| Change how data files are created | `Models/CreateDataFiles.swift` |
| Change how data is read and cached | `HardwareCollector.swift` |
| Understand SIP reading | `HardwareCollectors/HCVersion.swift` (`csrActiveConfig()` uses `dlsym` to call `csr_get_active_config`) |
