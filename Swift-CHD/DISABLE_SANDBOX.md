# CRITICAL: You Must Disable App Sandbox!

## The Real Problem

Your app **CANNOT** access files outside its sandbox, even with security-scoped resources. The verification is failing because **App Sandbox is blocking access** to `/opt/homebrew/bin/chdman`.

## THE FIX (Do This Now!)

### In Xcode:

1. **Click on your project** in the navigator (top file)
2. **Select the "CHDMan Mac GUI" target** (not the project)
3. **Click "Signing & Capabilities" tab** at the top
4. **Look for "App Sandbox"** section
5. **Click the ❌ (X) button** next to "App Sandbox" to completely remove it
6. **Press Cmd+Shift+K** to clean the build folder
7. **Press Cmd+R** to rebuild and run

### Screenshots to Help:

```
Project Navigator
├── CHDMan Mac GUI (← click this first)
    └── TARGETS
        └── CHDMan Mac GUI (← select this)
            └── Signing & Capabilities (← click this tab)
                └── App Sandbox (← click ❌ to remove)
```

## Why This Is Necessary

macOS App Sandbox prevents your app from:
- ✅ Reading/writing files (we fixed this with security-scoped resources)
- ❌ **Executing external programs** (chdman) - **CANNOT be fixed with just code**
- ❌ Accessing system directories like `/opt/homebrew/bin`

Since your app needs to run the external `chdman` tool, **App Sandbox MUST be disabled**.

## Alternatives (If You Really Want Sandbox)

If you absolutely need sandbox (for Mac App Store):

1. **Bundle chdman inside your app**
   - Put chdman in your app bundle
   - Use `Bundle.main.path(forResource: "chdman", ofType: nil)`
   - But this might violate MAME's license

2. **Use XPC service** (complex)
   - Create a privileged helper tool
   - Requires code signing and notarization
   - Much more complex

3. **Just disable sandbox** ✅ (Recommended for utility apps)
   - Most Mac utilities do NOT use sandbox
   - Your app is a file converter, not handling sensitive data
   - Users explicitly select files to convert

## Verification After Fix

After disabling App Sandbox and rebuilding:

1. Click "Verify" button in your app
2. You should see a **green ✅ checkmark**
3. The red error message should disappear
4. Try running a conversion

## Debug Info

When you run the app after this change, check Xcode's console for debug messages like:
```
DEBUG: Checking path: /opt/homebrew/bin/chdman
DEBUG: File exists: true
DEBUG: Is executable: true
```

If you still see `false`, then chdman really isn't installed. Run:
```bash
brew install mame
```

## Common Mistakes

❌ Clicking "App Sandbox" but leaving it enabled  
✅ **REMOVE the entire capability** by clicking ❌

❌ Making changes but not cleaning build folder  
✅ Always clean (Cmd+Shift+K) after capability changes

❌ Testing without rebuilding  
✅ Stop app, clean, rebuild, then test

## This Will Work!

Once App Sandbox is removed:
- ✅ Verification will find chdman
- ✅ Conversions will work
- ✅ No permission errors

Trust me on this one - **App Sandbox is the blocker**. Remove it and everything will work!
