# Releases Changelog

## 5.1.1 - Oct 20,2026

**Fix Unknown in GPU name**

- Fix for GPUs not exposed by Metal or reported with blank/Unknown names (such as `Intel(R) KBL Unknown`)

## 5.1.0 - Oct 19,2026

**Add XCTest**

- Add macOS XCTest target and coverage

## 5.0.8 - Oct 15, 2026

**Audio tab visibility**

- Fix: ensure the Audio tab is displayed from the startup

## 5.0.7 - Oct 14, 2026

**Speed up initial load**

- Implement a staged startup flow so Overview renders quickly from native APIs, then fills detailed tooltips/hardware data in the background
- Based on [2009-Nissan-Cube](https://github.com/2009-Nissan-Cube/About-This-Hack) latest commits

## 5.0.6 - Aug 31, 2026

**Improve SystemsFunction.swift**

- Improve SystemsFunction.swift, thanks to [Ybronst](https://github.com/ybronst)

## 5.0.5 - Aug 25, 2026

**Normalize display refresh rates**

- Normalize display refresh rates to whole-number Hz (no decimals)


## 5.0.4 - Aug 24, 2026

**Scroll bar in displays tab**

- Improved the horizontal scroll bar when 2 or more screens are connected
- Improve detection of Sidecar and AirPlay screens

## 5.0.3 - Aug 19, 2026

**Russian language**

- Add Russian language, thanks to [iTGower](https://github.com/iTGower)

## 5.0.2 - Aug 6, 2026

**Hide serial number by default**

- Serial number is hidden when the app starts

## 5.0.1 - Aug 17, 2026

**Update app icon**

- Update app icon, thanks to [anto65](https://github.com/antuneddu)

## 5.0.0 - Aug 2, 2026

**Migrate to Swift 6 (WIP)**

- Major update: migration to Swift 6 → fix errors and warnings, UI enhancements, more robust logic
- Higher minimum requirements:
   - macOS 15 Sequoia
   - Xcode supporting Swift 6

## 4.4.8 - Jul 31, 2026

**Fix OpenCore info**

- Fix an issue with the bootloader name in the Overview tab:
   - Improve OpenCore detection reliability
   - Revert app sandbox

## 4.4.7 - Jul 13, 2026

**Improve startup disk detection**

- Improve startup disk data detection on Ventura, thanks to [maxpicelli](https://github.com/maxpicelli)

## 4.4.6 - Jul 12, 2026

**Sandboxed app**

- App is sandboxed
- Bundled as DMG instead of ZIP to avoid Sparkle updates issues
- Add Sparkle entitlements
- Fix persistence of custom logo
- Minor localization changes in Storage label

## 4.4.4 - Jul 10, 2026

**Notarized app**

- The app is now notarized by Apple, no more needing Gatekeeper issues

## 4.4.0 - Jul 8, 2026

**Set macOS signing identity**

- Configure the Xcode project to use the `Apple Development` code signing identity

## 4.3.9 - Jul 5, 2026

**Prefer scaled display resolution**

- Update display to use `UI Looks Like` dimensions when present (scaled dimensions), falling back to `Resolution` (maximum resolution supported by the hardware); this improves reported display resolution for scaled modes

## 4.3.8 - Jun 30, 2026

**Add HDAUniversal audio**

- Add HDAUniversal audio: detection of `HDAUniversal.kext` (new audio system for Hackintoshes, made by *Mald0n*)

## 4.3.7 - Jun 28, 2026

**Per-macOS-version artwork for displays**

- Review the Displays tab: display images are now larger
- Use per-macOS-version artwork for built-in screens (MacBook assets), generic external monitors and iMac screens (proper iMac icons has been added)
- Several asset files have been cleaned up and normalized

## 4.3.6 - Jun 27, 2026

**Update Audio imageset**

- Update `Audio` imageset, thanks to [chris1111](https://github.com/chris1111)
- Adjust sidebar width in `ContentView.swift` to accommodate localized strings

## 4.3.5 - Jun 26, 2026

**Update Unknown imageset**

- Update `Unknown` imageset, used when macOS version is not recognized; thanks to [chris1111](https://github.com/chris1111)

## 4.3.4 - Jun 24, 2026

**Refactor SIP and Mac model**

- Improve Mac model identification
- Refactor SIP detection (drop Objective-C files, not needed anymore)
- Add Sparkle 2.9.3 by SPM replacing the integrated Sparkle `xcframework`
- Update to macOS 27 Golden Gate

## 4.3.2 - May 19, 2026

**Update Sparkle to 2.9.2**

- Update Sparkle integrated framework to 2.9.2

## 4.3.1 - May 16, 2026

**Add German language**

- Add German language (thanks to [kgp-macPro]( https://github.com/kgp-macPro))
- Rename `Storage` to `System disk` in locales

## 4.3.0 - May 15, 2026

**Update Sparkle and glass version**

- Update Sparkle and app digital signatures by applying `codesign` to the compiled bundle
- Glass version: apply translucent effect to language selector and about dialog 

## 4.2.9 - Embed Sparkle.xcframework

- Embed Sparkle by adding Sparkle.xcframework to the project
- Remove the Swift package product dependency for Sparkle

## 4.2.8 - DisplayPort audio support

- Add DisplayPort audio device support to the Audio tab

## 4.2.7 - Update documentation

- Update Sparkle documentation

## 4.2.6 - HDMI audio support

- Add HDMI audio device support to the Audio tab

## 4.2.5 - USB audio support · Get back Sparkle updater

- Add USB audio device support to the Audio tab
- Replace the custom GitHub-based update checker with Sparkle

## 4.2.4 - Native updater replaces Sparkle

- Sparkle is replaced by a native, lightweight SwiftUI GitHub-based update checker that uses the GitHub versioning API and requires no third-party dependencies
- Localize updater messages

## 4.2.2 - VoodooHDA audio detection

- Improve audio detection and VoodooHDA support via the `getdump` tool (work in progress)
- Fix accents in the French `Localizable.strings` file
- README: Document audio tab behavior, `getdump` requirement for VoodooHDA, and update screenshot references
- Assets: Renamed Audio screenshot for AppleALC and added a VoodooHDA screenshot

## 4.2.0 - Display detection · Audio tab

- Add Audio sidebar tab (work in progress):
  - Displays audio codec information
  - Applies only to Hackintosh having AppleALC enabled
  - Hackintosh using VoodooHDA do not have an audio tab
  - Detection of `alc-layout-id` over `layout-id`
  - Treat OpenCore+OCLP as a Hackintosh (only when audio injection drivers are detected)
- The custom updater system is replaced by Sparkle
- Remove scr.txt intermediary file for SPDisplaysDataType: `system_profiler SPDisplaysDataType` is written to `scr.txt` and then read back into the cache; the file round-trip is unnecessary
- Update Italian translation, thanks to [Anto65](https://github.com/antuneddu)
- Add the refresh rate in the Displays tab
- Add sidebar toggle button to hide / show the sidebar with animation
- Center content when the sidebar is hidden
- Conditionally show scroll indicator in Displays tab: hidden for 1–3 monitors, visible for 4 or more monitors

## 4.0.0 - Migrate to SwiftUI

- Migrate main UI to SwiftUI keeping app functionality
- Add language menu and language selector window (en, es, fr, it)
- Keep existing Settings window (custom logo) behavior
- Minimum target is macOS 13.5+
- Rework the Displays UI to use a horizontal `ScrollView` and enable full display counts (removed hard limit of 3)
- Replace ATHLogger with print statements (error/warning prints where failures are meaningful for debugging)
- Replace macOS version icons with liquid glass badges, thanks to [chris1111](https://github.com/chris1111)
- The app bundle size has been reduced from 29 to 11 MB

## 3.0.0 - Faster startup and custom logo

- Shorter app startup time
- Introduces a new Preferences window for customizing the macOS logo in the Overview tab
- Users can drag and drop a 1024×1024 PNG image to set a custom logo, which is persisted in UserDefaults
- Replaces custom updater system by Sparkle
- Adds missing image assets for Tahoe External/Internal HDD and SSD
- UI fixes for macOS Tahoe
- Minimum target is macOS 11.5+
