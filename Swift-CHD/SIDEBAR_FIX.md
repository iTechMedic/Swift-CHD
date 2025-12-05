# Sidebar Click Fix

## The Problem
The sidebar items weren't clickable - clicking on "ISO → CHD", "CUE → CHD", etc. did nothing.

## Root Causes

### 1. Enum Cases Mismatch
The `ConversionType` enum had old case names that didn't match our updates:
- Old: `.binCueToChd`, `.chdToBinCue`
- New: `.cueToChd`, `.gdiToChd`, `.chdToCue`, `.chdToGdi`

### 2. List Selection Binding Issue
The `NavigationSplitView` selection binding wasn't working properly with the non-optional `conversionType`.

## The Fix

### 1. Updated ConversionType Enum
Replaced with the complete new enum featuring:
- **6 conversion types** (ISO, CUE, GDI)
- **CHDManOptionType** enum for dropdown/flag/text
- **defaultOptions** and **advancedOptions** properties
- Extension properties for file handling

### 2. Changed Sidebar to Button-Based
Instead of relying on List selection binding, we now use explicit buttons:

```swift
List(ConversionType.allCases) { type in
    Button(action: {
        vm.conversionType = type
    }) {
        HStack {
            Text(type.title)
            Spacer()
            if vm.conversionType == type {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
    }
    .buttonStyle(.plain)
}
```

This approach:
- ✅ Always works (no binding issues)
- ✅ Shows selected state with checkmark
- ✅ More explicit and debuggable
- ✅ Works with `@Published` property

## Now It Works!

Click any item in the sidebar:
- **ISO → CHD** - Shows codec dropdown + force flag
- **CUE → CHD** - Same (for multi-track)
- **GDI → CHD** - Same (for Dreamcast)
- **CHD → ISO** - Shows just force flag
- **CHD → CUE** - Shows force + output BIN name option
- **CHD → GDI** - Shows force + output BIN name option

Each click:
1. Updates `vm.conversionType`
2. Triggers `didSet` which calls `resetOptionsForType()`
3. Loads appropriate default or advanced options
4. Updates the UI instantly

## Visual Feedback

Selected item shows a blue checkmark ✓ so you always know which conversion type is active.
