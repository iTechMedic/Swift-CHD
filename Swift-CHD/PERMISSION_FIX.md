# Permission Denied Fix Summary

## What Changed

### 1. **ConversionViewModel.swift**
- Added security-scoped resource access in `start()` function
- Resources are properly acquired before file operations
- Resources are always released after operations (even on error)
- Enhanced error messages to guide users to solutions

### 2. **CHDManTask.swift**
- Added validation that chdman executable exists and is accessible
- Enhanced PATH environment to include Homebrew locations
- Better error messages for execution failures

### 3. **CHDMan_Mac_GUI.entitlements** (NEW FILE)
- Template entitlements file for proper file access
- Allows user-selected file read/write
- Permits execution of external tools (chdman)

### 4. **TROUBLESHOOTING.md** (NEW FILE)
- Comprehensive guide for common issues
- Step-by-step fixes for permission problems
- Debugging tips and manual testing instructions

## Required Actions in Xcode

### Quick Fix (Recommended for Development)

1. Open your Xcode project
2. Select **CHDMan Mac GUI** target
3. Click **Signing & Capabilities** tab
4. If "App Sandbox" exists, click the **❌** to remove it
5. Clean (Cmd+Shift+K) and rebuild

✅ **This removes all permission restrictions**

### Alternative: Configure Sandbox Properly

If you need sandboxing (for App Store):

1. Keep **App Sandbox** enabled
2. Enable these under App Sandbox:
   - ✅ User Selected File (Read/Write)
   - ✅ Downloads Folder (Read/Write)
3. Add **Hardened Runtime** capability
4. Under Hardened Runtime:
   - ✅ Disable Library Validation
   - ✅ Allow Unsigned Executable Memory
5. Add entitlements file:
   - Build Settings → Code Signing Entitlements
   - Set to: `CHDMan_Mac_GUI.entitlements`

## How Security-Scoped Resources Work

When a user selects files via `NSOpenPanel` or `NSSavePanel`, macOS grants temporary access to those specific files. However, you must explicitly tell the system you're using that access:

```swift
// Start access before using the file
let success = url.startAccessingSecurityScopedResource()

// Do your file operations...

// Always release when done
if success {
    url.stopAccessingSecurityScopedResource()
}
```

The code now does this automatically in the `start()` function.

## Testing the Fix

1. Build and run the app
2. Select an input file (e.g., .iso)
3. Choose an output location
4. Click Run

If you still get permission errors:
- Check Xcode console for specific error messages
- Review TROUBLESHOOTING.md for solutions
- Try running without App Sandbox first

## Why This Happens

macOS apps have restricted file system access by default:
- **Sandboxed apps**: Can only access files user explicitly selects
- **Non-sandboxed apps**: Can access any location, but may trigger security warnings

Your app:
- Lets users select files (handled by system file panels)
- Runs external tool (chdman) that needs to read/write those files
- Must properly bridge the permission from UI to the external process

The security-scoped resource calls create that bridge.
