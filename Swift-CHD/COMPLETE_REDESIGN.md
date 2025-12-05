# Complete Redesign - All Conversion Types Supported!

## 🎉 What's New

### **6 Conversion Types** (from your scripts!)
1. **ISO → CHD** - Single-track ISO to compressed CHD
2. **CUE → CHD** - Multi-track BIN/CUE to CHD  
3. **GDI → CHD** - Dreamcast GDI to CHD
4. **CHD → ISO** - Extract CHD to ISO
5. **CHD → CUE** - Extract CHD to BIN/CUE
6. **CHD → GDI** - Extract CHD to Dreamcast GDI

### **Smart Option System**

#### **Simple Mode** (Default)
- Only essential options shown
- Matches your shell scripts exactly (`--force` equivalent)
- Perfect for beginners

**Creating CHD:**
- ☑️ `-c cd` (Compression codec) - dropdown menu
- ☑️ `-f` (Force overwrite) - flag

**Extracting CHD:**
- ☑️ `-f` (Force overwrite) - flag

#### **Advanced Mode** 
Toggle "Advanced" to see all options:

**Creating CHD:**
- ☑️ `-c` Compression codec (dropdown: cd, cdlz, cdzl, cdfl)
- ☐ `-hs` Hunk size in bytes (text input)
- ☑️ `-f` Force overwrite (flag)
- ☐ `-np` Proceed if not perfect (flag)

**Extracting CHD:**
- ☑️ `-f` Force overwrite (flag)
- ☐ `-ob` Output BIN filename (text input)

### **UI Improvements**

#### **Dropdown Menus**
For compression codec (`-c`), you get a proper dropdown:
```
[cd ▼]  ← Click to choose
├─ cd (default)
├─ cdlz
├─ cdzl  
└─ cdfl
```

#### **Three Input Types**
1. **Flag** - Just enable/disable (e.g., `-f`)
2. **Text** - Free text input (e.g., `-hs 2048`)
3. **Dropdown** - Pre-defined choices (e.g., `-c cd`)

#### **Visual Feedback**
- Each option shows: `Toggle | Key | Value | Help Text`
- Disabled options are grayed out
- Flags show "(flag)" instead of input field
- Dropdowns show all valid choices

### **Smart File Handling**
- Input/output extensions automatically match conversion type
- File browsers only show relevant formats
- Suggested output names based on input

### **Console Output**
- Shows exact command being run
- Real-time chdman output
- Clear success ✅ or error ❌ messages
- Scrollable and selectable text

## How to Use

### **Quick Start (Simple Mode)**
1. Select conversion type from sidebar
2. Choose input file
3. Choose output location  
4. Click **Run**

That's it! Default options are already optimal.

### **Advanced Usage**
1. Toggle **"Advanced"** switch
2. Enable additional options as needed
3. For dropdowns: Click the dropdown menu to choose
4. For text fields: Enter custom values
5. Disable options you don't want

## Option Explanations

### **Compression Codecs (`-c`)**
- **cd** (default) - Standard CD compression, best compatibility
- **cdlz** - CD with LZMA compression, smaller but slower
- **cdzl** - CD with zlib compression, good balance
- **cdfl** - CD with FLAC audio compression, best for audio

### **Hunk Size (`-hs`)**
- Chunk size for compression (bytes)
- Default: auto-detected based on disc type
- Larger = faster but less compression
- Smaller = slower but better compression

### **Force Overwrite (`-f`)**
- Overwrites output file if it exists
- **Enabled by default** (matches your scripts)
- Disable if you want to prevent accidental overwrites

### **Not Perfect (`-np`)**
- Proceeds even if conversion isn't perfect
- Useful for damaged/unusual discs
- Usually not needed

### **Output BIN Name (`-ob`)**
- Specify custom BIN filename for CUE/GDI extraction
- Default: uses input filename
- Only applies to CUE/GDI extraction

## Technical Details

### **What Your Scripts Did**
```bash
chdman createcd -i "input.iso" -o "output.chd" --force
```

### **What The App Does (Simple Mode)**
```bash
chdman createcd -i /path/to/input.iso -o /path/to/output.chd -c cd -f
```

Same result, but with:
- ✅ Explicit compression codec
- ✅ GUI file selection
- ✅ Progress bar
- ✅ Error handling
- ✅ Console output

## Compression Codec Guide

### **When to use each:**

**cd** - Use for:
- PlayStation games
- Sega CD/Saturn
- Most arcade CD games
- Maximum compatibility

**cdlz** - Use for:
- Archival purposes
- When storage space is critical
- You don't mind slower load times

**cdzl** - Use for:
- Good balance of speed and size
- Modern systems with fast CPU

**cdfl** - Use for:
- Audio CDs
- Games with lots of CD audio
- Best quality audio preservation

## Examples

### **Convert PSX Game**
1. Type: ISO → CHD
2. Input: Final Fantasy VII.iso
3. Output: Final Fantasy VII.chd
4. Options: `-c cd` (default), `-f` (enabled)
5. Result: Perfectly compatible CHD

### **Convert Dreamcast Game**
1. Type: GDI → CHD
2. Input: Sonic Adventure.gdi
3. Output: Sonic Adventure.chd
4. Options: `-c cd`, `-f`
5. Result: Ready for emulators

### **Extract for Burning**
1. Type: CHD → CUE
2. Input: Game.chd
3. Output: Game.cue (creates Game.bin automatically)
4. Options: `-f`
5. Result: Burnable BIN/CUE

## Pro Tips

1. **Always keep `-f` enabled** unless you specifically want protection
2. **Simple mode is usually enough** - advanced options rarely needed
3. **Watch the console** - it shows what's actually happening
4. **For Dreamcast**, always use GDI format (not CUE)
5. **For PSX multi-disc**, convert each disc separately

## Troubleshooting

**"Invalid option"** error?
- Try Simple Mode first
- Check console output for details

**Compression taking forever?**
- Use `cd` codec instead of `cdlz`
- Normal ISO to CHD takes 1-5 minutes

**Output file huge?**
- Wrong codec selected
- Try `cd` for best results

**Can't select my file?**
- Check you're using the right conversion type
- App only shows compatible formats
