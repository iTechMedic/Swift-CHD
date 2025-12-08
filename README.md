# Swift-CHD

A modern macOS application for converting disc images to and from CHD (Compressed Hunks of Data) format. Built with SwiftUI, this app provides an intuitive interface for working with ISO, BIN/CUE, GDI, and CHD files.

## Overview

Swift-CHD is a native Mac app that provides a graphical frontend for the powerful `chdman` command-line tool. CHD is a highly compressed file format designed for archiving disc images, particularly useful for retro gaming emulation.

### Features

- ✅ **Single File Mode**: Convert individual disc images with full control
- ✅ **Batch Mode**: Process multiple files at once with progress tracking
- ✅ **Multiple Format Support**: 
  - ISO → CHD
  - BIN/CUE → CHD
  - GDI → CHD (Dreamcast)
  - CHD → ISO
  - CHD → BIN/CUE
  - CHD → GDI
- ✅ **Advanced Options**: Customize compression codecs, hunk sizes, and more
- ✅ **Real-time Progress**: Live progress tracking and console output
- ✅ **Automatic chdman Detection**: Finds and verifies your chdman installation

## Requirements

- **macOS**: macOS 12.0 (Monterey) or later
- **chdman**: The MAME CHD Manager tool (installation instructions below)

## Installing chdman (Required)

Swift-CHD requires `chdman`, which is part of the MAME project. The easiest way to install it is using Homebrew.

### Step 1: Install Homebrew (if not already installed)

If you don't have Homebrew installed, open Terminal and run:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the on-screen instructions. After installation, you may need to add Homebrew to your PATH. The installer will provide instructions specific to your Mac.

### Step 2: Install MAME (includes chdman)

Once Homebrew is installed, install MAME which includes chdman:

```bash
brew install mame
```

This will download and install MAME along with all its command-line tools, including chdman.

### Step 3: Verify Installation

After installation completes, verify that chdman is available:

```bash
chdman --version
```

You should see output showing the chdman version number. If you see "command not found", try the full path:

```bash
# For Apple Silicon Macs (M1, M2, M3, etc.)
/opt/homebrew/bin/chdman --version

# For Intel Macs
/usr/local/bin/chdman --version
```

### Alternative: Manual Installation

If you prefer not to use Homebrew, you can:

1. Download MAME from the official website: https://www.mamedev.org/release.html
2. Extract the download
3. Locate the `chdman` executable
4. Note the full path to use in Swift-CHD

## Using Swift-CHD

### First Launch

1. **Launch the app**: Double-click Swift-CHD to open it
2. **Verify chdman**: The app will automatically try to find chdman on your system
   - If found automatically, you'll see a green checkmark ✅
   - If not found, click "Verify" or manually enter the path to chdman

### Single File Mode

Perfect for converting individual disc images with full control over options.

1. **Select Conversion Type**: Choose your conversion type from the sidebar (e.g., "ISO → CHD")
2. **Choose Input File**: Click "Browse…" next to Input to select your source file
3. **Choose Output Location**: Click "Browse…" next to Output to set where the converted file will be saved
4. **Configure Options** (Optional): 
   - Expand the "Options" section to customize compression and other settings
   - Common options include:
     - `-f`: Force overwrite existing files
     - `-c`: Compression codec (cd, cdlz, cdzl, cdfl)
     - `-np`: Proceed even if not perfect
5. **Run Conversion**: Click the "Run" button (or press Return)
6. **Monitor Progress**: Watch the progress bar and console output as conversion proceeds

### Batch Mode

Ideal for converting multiple files at once.

1. **Switch to Batch Mode**: Click "Batch Mode" in the mode selector at the top
2. **Select Conversion Type**: Choose your conversion type from the sidebar
3. **Add Files**: 
   - Click "Add Files…" to select multiple files to convert
   - You can add files multiple times to build your batch list
4. **Set Output Directory** (Optional):
   - By default, output files are saved next to their source files
   - Click "Choose…" to select a different output directory for all files
5. **Configure Batch Options** (Optional):
   - "Skip existing files": Automatically skip files that have already been converted
   - "Stop on first error": Stop batch processing if any conversion fails
6. **Review File List**: Check the list of files to be converted and their status
7. **Run Batch**: Click the "Run Batch" button
8. **Monitor Progress**: Watch as each file is processed, with status indicators for each:
   - ⚪️ Pending
   - 🔵 Processing
   - ✅ Completed
   - ❌ Failed
   - 🟠 Skipped
9. **View Summary**: When complete, a summary shows total files processed, succeeded, failed, and skipped

### Tips for Best Results

#### Converting ISO to CHD
- ISO files are single-track disc images
- Choose compression codec based on your needs:
  - `cd`: Standard CD compression (recommended)
  - `cdlz`: LZMA compression (better compression, slower)
  - `cdzl`: Zlib compression (faster, larger files)
  - `cdfl`: FLAC compression (audio-focused)

#### Converting BIN/CUE to CHD
- Always select the `.cue` file, not the `.bin` file
- The .cue file references the .bin file(s), and chdman will handle them automatically
- Make sure the .cue and .bin files are in the same directory

#### Converting GDI to CHD
- GDI is the Dreamcast disc image format
- Select the `.gdi` file as input
- Make sure all associated track files are in the same directory

#### Extracting CHD Files
- When extracting CHD → BIN/CUE or CHD → GDI, multiple files may be created
- The output path you specify will be the main file (cue or gdi)
- Associated track files will be created in the same directory

### Advanced Options

Enable "Advanced Mode" in the Options section to access more chdman parameters:

- **Hunk Size (`-hs`)**: Adjust the compression chunk size (advanced users only)
- **Output BIN Filename (`-ob`)**: Specify custom output filename for BIN files when extracting
- **Custom Arguments**: Add any additional chdman arguments manually

### Troubleshooting

If you encounter issues, check the built-in troubleshooting guide:

1. See `TROUBLESHOOTING.md` in the app's documentation folder
2. Common issues:
   - **"Permission Denied"**: May need to disable App Sandbox in development builds
   - **"chdman not found"**: Verify chdman is installed and the path is correct
   - **"File exists"**: Enable the `-f` (force overwrite) option
   - **Conversion fails immediately**: Check that input file format matches conversion type

### Console Output

The console output section shows real-time output from chdman, including:
- Progress percentages
- Compression statistics
- Warnings or errors
- File verification results

You can select and copy text from the console output for sharing or debugging.

## File Format Information

### CHD (Compressed Hunks of Data)
- Developed by the MAME team for disc image archiving
- Highly efficient compression specifically designed for disc images
- Supports CD-ROM, DVD-ROM, and hard drive images
- Widely supported in emulators (RetroArch, MAME, etc.)

### ISO
- Raw uncompressed disc image
- Standard single-track format
- Simple but larger file sizes

### BIN/CUE
- Multi-track disc image format
- .cue file contains track layout
- .bin file(s) contain actual data
- Supports audio tracks, mixed-mode CDs

### GDI
- Dreamcast disc image format
- Contains multiple track files
- .gdi file lists track information

## Building from Source

If you want to build Swift-CHD yourself:

1. Clone the repository
2. Open `Swift-CHD.xcodeproj` in Xcode
3. Select your development team in Signing & Capabilities
4. Build and run (Cmd+R)

**Note**: For development builds, you may need to disable App Sandbox to allow chdman execution:
- Select your target
- Go to Signing & Capabilities
- Remove the "App Sandbox" capability

## Support

For issues, feature requests, or questions:
- Check `TROUBLESHOOTING.md` for common problems
- Review console output for error messages
- Verify chdman installation with `chdman --version` in Terminal

## Credits

- **chdman**: Part of the MAME project (https://www.mamedev.org)
- **Swift-CHD**: A modern Swift/SwiftUI frontend for macOS

## License

This application is a frontend for chdman. Please respect the MAME project's licensing terms when using chdman.

---

**Enjoy preserving your disc images with Swift-CHD!** 🎮💿
