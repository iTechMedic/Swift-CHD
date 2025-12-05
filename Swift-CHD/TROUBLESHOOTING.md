# Troubleshooting CHDMan Mac GUI

## "Permission Denied" Errors

### Quick Fix (Development/Testing)
1. Open Xcode project
2. Select your target
3. Go to **Signing & Capabilities**
4. Remove **App Sandbox** capability (click the ❌)
5. Clean build folder (Cmd+Shift+K)
6. Rebuild and run

### For Mac App Store / Distribution

If you need sandboxing enabled:

1. Keep **App Sandbox** enabled
2. Under App Sandbox, check:
   - ✅ User Selected File (Read/Write)
   - ✅ Downloads Folder (Read/Write) - optional
3. Add **Hardened Runtime** capability
4. Under Hardened Runtime, check:
   - ✅ Disable Library Validation
   - ✅ Allow Unsigned Executable Memory

### Entitlements File Setup

Add `CHDMan_Mac_GUI.entitlements` to your project:
- In Xcode: File → Add Files to Project
- Select the `.entitlements` file
- In target's Build Settings, search for "Code Signing Entitlements"
- Set it to: `CHDMan_Mac_GUI.entitlements`

## "chdman not found" Errors

### Verify Installation
```bash
# Check if chdman is installed
which chdman

# If not found, install via Homebrew
brew install mame

# Verify installation
/opt/homebrew/bin/chdman --version  # Apple Silicon
# or
/usr/local/bin/chdman --version     # Intel Mac
```

### Manual Path Entry
If the app still can't find chdman:
1. Find the full path: `which chdman`
2. Copy the full path
3. In the app, paste it in the "chdman:" field
4. Click "Verify"

## Common Issues

### Issue: "Operation not permitted"
**Cause:** App Sandbox blocking file access  
**Fix:** Follow "Permission Denied" fixes above

### Issue: "chdman exited with code 1"
**Cause:** Invalid arguments or file format  
**Fix:** 
- Check input file is valid
- For BIN/CUE, ensure you select the .cue file
- Verify output path is writable

### Issue: Conversion starts but immediately fails
**Cause:** Output file already exists and `-f` flag not set  
**Fix:** Enable the `-f` (force overwrite) option in the app

### Issue: Can't write to external drives
**Cause:** Sandbox restrictions on removable media  
**Fix:** 
1. Disable App Sandbox, OR
2. Add to entitlements:
```xml
<key>com.apple.security.files.downloads.read-write</key>
<true/>
<key>com.apple.security.temporary-exception.files.absolute-path.read-write</key>
<array>
    <string>/Volumes/</string>
</array>
```

## Debugging Tips

### Enable Verbose Output
In the Options section, enable the `-v` flag to see detailed chdman output.

### Check Console.app
1. Open Console.app
2. Filter for "CHDMan" or your app name
3. Look for security/permission errors

### Manual Command Test
Copy the command from the error message and test in Terminal:
```bash
/opt/homebrew/bin/chdman createcd -i /path/to/input.iso -o /path/to/output.chd -c cd -q 9
```

If it works in Terminal but not in the app, it's a permissions issue.
