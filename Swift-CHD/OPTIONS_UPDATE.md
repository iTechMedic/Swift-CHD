# Options Update - All Improvements

## ✅ Fixed Issues

### 1. **Dropdown Not Updating**
**Problem:** Selecting a codec from the dropdown always showed "cd"  
**Cause:** Wrong binding - was creating a computed binding that always returned the default  
**Fix:** Changed to direct binding `$opt.value` with proper `String?` tags

```swift
// Before (broken):
Picker("", selection: Binding(
    get: { opt.value ?? choices.first ?? "" },
    set: { opt.value = $0 }
))

// After (works):
Picker("", selection: $opt.value) {
    ForEach(choices, id: \.self) { choice in
        Text(choice).tag(choice as String?)
    }
}
```

### 2. **No Options by Default**
**Before:** Started with `-c cd` and `-f` enabled  
**Now:** Starts clean with no options

**Simple Mode:**
- Empty by default
- Clean slate
- User enables what they need

**Advanced Mode:**
- Shows all available options
- All disabled by default
- User toggles on what they want

### 3. **Added Verification Option**
New `-v` flag for both compression and extraction:
- **Compression:** Verifies CHD after creation
- **Extraction:** Verifies extracted files
- Ensures data integrity
- Good for archival/important files

### 4. **Added Hunk Size Option**
New `-hs` option with text input:
- Customize chunk size for compression
- Common values: 2048, 4096, 8192
- Default is auto-detected if not specified
- Advanced users can optimize for their use case

## 🎨 New Features

### **Compression Codec Descriptions**

When you **enable** the `-c` option and select a codec, you see a description:

```
☑️ -c  [cdlz ▼]  Compression codec
   ℹ️ CD-ROM + LZMA - Smaller size, slower compression, good for archival
```

**Codec Guide:**
- **cd** - Standard CD-ROM (recommended) - Best compatibility, fast compression
- **cdlz** - CD-ROM + LZMA - Smaller size, slower compression, good for archival
- **cdzl** - CD-ROM + Zlib - Balanced size/speed, good general purpose
- **cdfl** - CD-ROM + FLAC - Best for audio-heavy games, preserves audio quality

The description automatically updates when you change the codec selection!

### **Empty State Message**

In Simple Mode (no options), you see:
```
No options enabled. Toggle 'Advanced' to see all available options.
```

Makes it clear that you need to toggle Advanced to enable options.

## 📋 Complete Option List

### **Creating CHD (ISO/CUE/GDI → CHD):**
- ☐ `-c` Compression codec (dropdown: cd, cdlz, cdzl, cdfl) + descriptions
- ☐ `-hs` Hunk size in bytes (text input, e.g., "2048")
- ☐ `-f` Force overwrite existing files (flag)
- ☐ `-v` Verify after compression (flag) **NEW**
- ☐ `-np` Proceed even if not perfect (flag)

### **Extracting CHD (CHD → ISO/CUE/GDI):**
- ☐ `-f` Force overwrite existing files (flag)
- ☐ `-v` Verify after extraction (flag) **NEW**
- ☐ `-ob` Output BIN filename (text input)

## 🎯 Typical Usage

### **Quick Conversion (Simple Mode)**
1. Select ISO → CHD
2. Choose files
3. Click Run
4. Done! (uses chdman defaults)

### **Custom Compression (Advanced Mode)**
1. Toggle "Advanced"
2. Enable `-c` and choose codec (e.g., `cdlz` for archival)
3. Enable `-v` to verify
4. Optionally enable `-f` to overwrite
5. Click Run

### **High-Quality Audio Game**
1. Toggle "Advanced"  
2. Enable `-c` and select `cdfl`
3. See: "CD-ROM + FLAC - Best for audio-heavy games..."
4. Enable `-v` to verify
5. Click Run

### **Custom Hunk Size**
1. Toggle "Advanced"
2. Enable `-hs` and enter "4096"
3. Enable `-v` to verify
4. Click Run

## 💡 Why These Changes?

### **Cleaner Start**
- No assumptions about what user wants
- Prevents accidental overwrites (no default `-f`)
- Professional tools don't force defaults

### **Informative**
- Codec descriptions help users choose
- No need to google "what is cdlz"
- Contextual help right in the UI

### **Flexible**
- Power users get all options
- Beginners get clean, simple interface
- Everyone can customize their workflow

### **Safe**
- Verification option catches corruption
- No forced overwrites by default
- User explicitly chooses risky options

## 🔧 Technical Details

### **Dropdown Binding Fix**
The key was using `String?` tags to match the optional value type:
```swift
Text(choice).tag(choice as String?)
```

This allows proper bidirectional binding with the optional string value.

### **Codec Descriptions**
Stored as static dictionary in ConversionType:
```swift
static let codecDescriptions: [String: String] = [
    "cd": "Standard CD-ROM...",
    // ...
]
```

Accessed in UI when codec option is enabled and has a value.
