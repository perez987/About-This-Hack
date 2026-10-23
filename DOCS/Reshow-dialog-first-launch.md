## Update dialog at first launch

The dialog is controlled by ATHUpdateConsentAsked in UserDefaults.standard. Your actual choice is stored separately as `ATHAutomaticallyChecksForUpdates`.

For the current, non-sandboxed build, these live in:

`~/Library/Preferences/com.0xCUBE.About-This-Hack.plist`

Deleting the plist directly may not work because macOS caches preferences through `cfprefsd`.

For recover the dialog as if it is the first launch:

- Quit the app completely
- Run `defaults delete com.0xCUBE.About-This-Hack ATHUpdateConsentAsked`
- Relaunch the app: the consent dialog should appear again.

You do not need to delete the entire plist or reset other preferences.

The condition is implemented in `Xcode-project/About This Hack/Models/UpdateController.swift:485–495`.

If you only want to change the choice, the application menu also contains an automatic-update-check toggle.