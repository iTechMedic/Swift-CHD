# What I Just Fixed

## The Problem
Your app was showing "chdman failed with exit code 1" because the `-i` and `-o` options in the UI were **enabled by default**, causing duplicate arguments.

The command was effectively:
```bash
chdman createcd -i input.iso -o output.chd -c cd -q 9 -i value -o value
```

Notice the duplicate `-i` and `-o` at the end!

## The Fix
Changed the default options so `-i` and `-o` are **disabled by default** since they're automatically added by the code.

Now the toggles for `-i` and `-o` will be **OFF (gray)** when you start the app.

## What to Do Now

1. **Restart your app** (or switch conversion types to reset options)
2. The `-i` and `-o` toggles should now be **OFF**
3. Try running your conversion again - it should work! 🎉

## If You See the Toggles Still ON

Just **click them to turn them OFF** - they should be gray/disabled. The UI will show:
- `-c` toggle: **ON** ✅ (blue)
- `-q` toggle: **ON** ✅ (blue)
- `-i` toggle: **OFF** ❌ (gray) 
- `-o` toggle: **OFF** ❌ (gray)

## Other Improvements I Made

1. **Better error messages** - Now shows actual chdman output when it fails
2. **Debug logging** - Check Xcode console to see the exact command being run
3. **Error context** - Shows the last 5 lines of chdman output for troubleshooting

## Test It!

Your conversion should now work. The app will:
1. Start the conversion
2. Show progress percentage
3. Display status updates
4. Complete successfully! 🎉

If you still get errors, check the Xcode console (bottom panel) for the debug output showing the exact command being run.
