## Update dialog at first launch

The dialog is controlled by SUHasLaunchedBefore in UserDefaults.standard. Your actual choice is stored separately as `SUEnableAutomaticChecks`.

For the current, non-sandboxed build, these live in:

`~/Library/Preferences/com.0xCUBE.About-This-Hack.plist`

Deleting the plist directly may not work because macOS caches preferences through `cfprefsd`.

For recover the dialog as if it is the first launch:

- Quit the app completely
- Run `defaults delete com.0xCUBE.About-This-Hack SUHasLaunchedBefore`
- Run `defaults delete com.0xCUBE.About-This-Hack SUEnableAutomaticChecks`
- Relaunch the app: the consent dialog should appear again.

You do not need to delete the entire plist or reset other preferences.
