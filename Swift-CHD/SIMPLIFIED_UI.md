# Simplified UI with Terminal Output - What Changed

## Problem
The app had too many confusing options and it was hard to debug what was happening when chdman ran.

## Solutions Implemented

### 1. Simplified Default Options

**Before:**
- Many options: `-c`, `-q`, `-f`, `-v`, `-i`, `-o`
- Confusing which ones to enable
- `-i` and `-o` caused duplicate arguments

**After:**
- **ISO/BIN → CHD**: Only `-c cd` (compression) and `-f` (force overwrite)
- **CHD → ISO/BIN**: Only `-f` (force overwrite)
- Minimal, sensible defaults that "just work"

### 2. Added Live Terminal Output

**New Feature: Console Output Window**
- Shows the exact command being run
- Displays real-time output from chdman
- Auto-scrolls to bottom as new output appears
- Text is selectable for copying
- Shows success ✅ or error ❌ messages clearly

### 3. Cleaner Options UI

**Before:**
```
[Toggle] -c  [text field]  Long description...
[Toggle] -q  [text field]  Long description...
```

**After:**
```
☑ -c cd  Compression codec for CD images
☑ -f     Force overwrite if output exists
```

Simpler toggles with inline values.

## How to Use the New UI

1. **Select conversion type** (e.g., ISO → CHD)
2. **Choose input and output files**
3. **Click Verify** to find chdman
4. **Click Run** - that's it!

The options are already set to sensible defaults. You can toggle `-f` off if you don't want to overwrite, but usually you want it on.

## What You'll See When Running

### Console Output Shows:
```
$ /opt/homebrew/bin/chdman createcd -i /path/to/input.iso -o /path/to/output.chd -c cd -f
============================================================
chdman - MAME Compressed Hunks of Data (CHD) manager...
Compressing, 50% complete...
Compressing, 100% complete...
============================================================
✅ SUCCESS: Conversion completed!
```

### On Error:
```
$ /opt/homebrew/bin/chdman createcd ...
============================================================
Error: Invalid option: -q
Usage: chdman createcd ...
============================================================
❌ ERROR: chdman error (exit code 1):
--hunksize, -hs <bytes>: size of each hunk...
```

## Benefits

✅ **Simpler** - No confusion about which options to enable  
✅ **Transparent** - See exactly what's happening  
✅ **Debuggable** - Copy console output for troubleshooting  
✅ **Professional** - Looks like a proper Mac utility  
✅ **Error-resistant** - Fewer ways to misconfigure  

## Advanced Users

If you need more options in the future, you can easily add them back to the `knownOptions` dictionary, but for 95% of users, this simplified version is all they need!
