# Quick Fix for Permission Denied Error

## The Problem You're Seeing

Your screenshot shows the path is set to `/opt/homebrew/bin` but it should be `/opt/homebrew/bin/chdman` (with the executable name).

## Immediate Solutions (Try in order)

### Solution 1: Fix the chdman Path (Quick!)
1. In your app, change the chdman path from:
   ```
   /opt/homebrew/bin
   ```
   to:
   ```
   /opt/homebrew/bin/chdman
   ```
2. Click "Verify" button
3. Try running again

### Solution 2: Disable App Sandbox (Most Reliable)
1. Open Xcode
2. Select your **CHDMan Mac GUI** target
3. Click **Signing & Capabilities** tab
4. If you see "App Sandbox" section, click the **❌** to remove it
5. **Clean Build Folder** (Cmd+Shift+K)
6. **Rebuild and Run**

This removes all file permission restrictions!

### Solution 3: Verify chdman Installation
Open Terminal and run:
```bash
which chdman
```

It should output something like:
- `/opt/homebrew/bin/chdman` (Apple Silicon)
- `/usr/local/bin/chdman` (Intel Mac)

Copy this EXACT path into your app's chdman field.

If `which chdman` returns nothing, install it:
```bash
brew install mame
```

## Why This Happens

macOS has two levels of protection:

1. **File Access**: Sandboxed apps can only access user-selected files
   - ✅ Fixed by security-scoped resources (already in code)
   
2. **App Sandbox**: Restricts what apps can do
   - ❌ This is blocking chdman from running
   - ✅ Fix: Disable App Sandbox in Xcode

## After Fixing

Your app should:
1. Show a ✅ green checkmark next to the Verify button
2. Allow conversion without permission errors
3. Show progress as the conversion runs

## Still Not Working?

Try this test in Terminal:
```bash
/opt/homebrew/bin/chdman createcd -i ~/Downloads/descent.iso -o ~/Downloads/test.chd -c cd -q 9
```

If this works in Terminal but not in your app, it's 100% a sandbox issue.

## Most Common Mistakes

❌ Wrong path: `/opt/homebrew/bin` (missing executable name)  
✅ Correct path: `/opt/homebrew/bin/chdman`

❌ App Sandbox still enabled  
✅ App Sandbox disabled (for development)

❌ Not clicking "Verify" after changing path  
✅ Always verify after path changes
