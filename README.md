# Swift-CHD

A modern macOS application for converting disc images to and from CHD (Compressed Hunks of Data) format. Built with SwiftUI, this app provides an intuitive interface for working with ISO, BIN/CUE, GDI, and CHD files.

## Overview

Swift-CHD is a native Mac app that provides a graphical frontend for the powerful `chdman` command-line tool. CHD is a highly compressed file format designed for archiving disc images, particularly useful for retro gaming emulation.

### Supported Formats at a Glance

| Conversion | Supported | Notes |
|---|---|---|
| ISO → CHD | ✅ Yes | Single-track disc images |
| BIN/CUE → CHD | ✅ Yes | Select the `.cue` file |
| GDI → CHD | ✅ Yes | Dreamcast |
| CDI → CHD | ⚠️ Some discs | Dreamcast. Read by Swift-CHD itself — see [CDI Files](#cdi-files) |
| CHD → ISO | ✅ Yes | |
| CHD → BIN/CUE | ✅ Yes | |
| CHD → GDI | ✅ Yes | |

### Features

- ✅ **Single File Mode**: Convert individual disc images with full control
- ✅ **Batch Mode**: Process multiple files at once with progress tracking
- ✅ **Multiple Format Support**:
  - ISO → CHD
  - BIN/CUE → CHD
  - GDI → CHD (Dreamcast)
  - CDI → CHD (Dreamcast, DiscJuggler)
  - CHD → ISO
  - CHD → BIN/CUE
  - CHD → GDI
- ✅ **Advanced Options**: Customize compression codecs, hunk sizes, and more
- ✅ **Real-time Progress**: Live progress tracking and console output
- ✅ **Automatic chdman Detection**: Finds and verifies your chdman installation

## CDI Files

CDI is a proprietary DiscJuggler container, and `chdman` has no parser for it — MAME
[declined to add one upstream](https://github.com/mamedev/mame/issues/11457). Swift-CHD reads the
format itself: select a `.cdi` file and convert it like any other, with no third-party tools.

**Not every Dreamcast CDI can become a working CHD, and the reason is worth understanding before
you try.** A CDI is always a *CD* — a self-boot CD-R burnt from a GD-ROM so it would play from an
ordinary drive. A Dreamcast CHD is always a *GD-ROM*: redream and Flycast both assume that geometry
for CHD input and ignore what the disc's table of contents actually says. redream reads the boot
header at disc address 45000 whatever the disc is, and Flycast rejects a CHD with fewer than three
tracks outright.

So the conversion is a rebuild, not a copy. Swift-CHD prefers to move nothing at all: it keeps
every original track exactly where it was — the filesystem records absolute disc addresses — and
adds a copy of the boot session at address 45000, where an emulator insists on finding it.

That works only if the disc's own data does not already sit across address 45000. On a small disc
it does not. On a large one it does, and Swift-CHD falls back to rebuilding the disc around that
address: the boot session moves onto it, everything else moves after it, and every address in the
ISO 9660 filesystem is rewritten so each file is still found by name. A disc converted this way is
flagged in the UI, because it is worth testing before you delete the CDI.

Rebuilding is not always sound. **Games that read the disc by raw sector number** ship a build-time
table of sector addresses and never ask the filesystem anything, so rewriting the filesystem does
not help them — they boot and then reboot-loop. Swift-CHD spots this by looking for the disc's own
directory addresses inside the boot binary (Sonic Adventure, for one, has them) and **refuses with
the reason** rather than writing a CHD that looks fine and will not boot.

Discs with **CD audio** are refused. A GD-ROM's boot header sits at address 45000, so only that
many sectors exist beneath it — far fewer than a CD soundtrack needs — and the music necessarily
lands above, inside the area a GD-ROM reserves for game data and a Dreamcast never plays audio
from. Neo XYX, measured: its CDI reaches attract-mode gameplay in both emulators, while every CHD
built from it boots and then stops, black in redream and frozen on the licence screen in Flycast.
This is a property of the disc rather than of the conversion — a build that relocated *nothing*,
every original address kept, failed in exactly the same way — so there is no layout to be cleverer
about.

A refused disc is not a bug, and the CDI itself still works — redream and Flycast both open `.cdi`
files directly.

See [Converting CDI to CHD](#converting-cdi-to-chd) below for details.

## Requirements

- **macOS**: macOS 12.0 (Monterey) or later
- **chdman**: The MAME CHD Manager tool (installation instructions below)

## Installing chdman (Required)

Swift-CHD requires `chdman`, which is part of the MAME project. The easiest way to install it is using Homebrew.

### Step 1: Install Homebrew (if not already installed)

If you don't have Homebrew installed, open Terminal and run:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the on-screen instructions. After installation, you may need to add Homebrew to your PATH. The installer will provide instructions specific to your Mac.

### Step 2: Install rom-tools (includes chdman)

Once Homebrew is installed, install rom-tools which includes chdman:

```
brew install rom-tools
```

This will download and install rom-tools along with chdman and other ROM management utilities.

### Step 3: Verify Installation

After installation completes, verify that chdman is available:

```
chdman --version
```

You should see output showing the chdman version number. If you see "command not found", try the full path:

```
# For Apple Silicon Macs (M1, M2, M3, etc.)
/opt/homebrew/bin/chdman --version

# For Intel Macs
/usr/local/bin/chdman --version
```

### Alternative: Manual Installation

If you prefer not to use Homebrew, you can:

1. Download MAME from the official website: <https://www.mamedev.org/release.html>
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
     * `-f`: Force overwrite existing files
     * `-c`: Compression codec (cdlz, cdzl, cdfl)
     * `-np`: Limit how many CPU cores are used (takes a number)
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
  * `cdlz,cdzl,cdfl`: chdman's default, picks the best of the three per hunk (recommended)
  * `cdlz`: LZMA compression (better compression, slower)
  * `cdzl`: Zlib compression (faster, larger files)
  * `cdfl`: FLAC compression (audio-focused)

#### Converting BIN/CUE to CHD

- Always select the `.cue` file, not the `.bin` file
- The .cue file references the .bin file(s), and chdman will handle them automatically
- Make sure the .cue and .bin files are in the same directory

#### Converting GDI to CHD

- GDI is the Dreamcast disc image format
- Select the `.gdi` file as input
- Make sure all associated track files are in the same directory

#### Converting CDI to CHD
- CDI (DiscJuggler) is a Dreamcast disc image format chdman cannot read, so Swift-CHD reads it
  itself: it parses the image's track table, writes the tracks out as raw sectors alongside a
  generated GDI, and points chdman at that. The staged files are deleted when the run finishes.
- Select the `.cdi` file as input. Everything else works as it does for any other conversion.
- Conversion needs temporary disk space roughly equal to the size of the image, checked before
  anything is written. The first part of the progress bar covers this staging step.
- CDI images that have been renamed to `.iso` are recognised by content and converted correctly.
  chdman would otherwise accept them as a single 2048-byte-sector track and silently compress
  them into an unusable CHD.
- **A disc that cannot be converted is refused before anything is written**, with the address, the
  track, or the CD audio that is in the way named in the message. See [CDI Files](#cdi-files) for
  why. This is checked as soon as you select the file, not after a conversion has run.
- **A disc that had to be rebuilt around address 45000 is flagged, not refused.** The conversion is
  sound as far as it can be checked, but a game that keeps sector addresses somewhere other than
  its boot binary would not be caught. Test the CHD before deleting the CDI.

What the rebuild does, and why each step is needed:

- **Tracks stay where they were, whenever possible.** A Dreamcast filesystem records absolute disc
  addresses, so a track that moves takes every file on the disc with it. GDI is used as the
  intermediate because it is the only sidecar chdman accepts that can state a track's absolute
  position.
- **The boot session is copied to address 45000.** That is where a GD-ROM keeps its high-density
  area, and where an emulator reads the boot header and filesystem descriptor from regardless of
  the table of contents.
- **Or, if address 45000 is already occupied, the disc is rebuilt around it.** The boot session
  moves onto the address and everything else moves after it, and every address in the ISO 9660
  filesystem — the volume descriptors, both path tables, and the extent of every directory record
  — is rewritten so each file is still found by name.
- **Data tracks are rewritten as Mode 1.** redream's and Flycast's CHD readers understand only
  `AUDIO` and `MODE1_RAW`. A self-boot CD-R is usually Mode 2, whose user data sits eight bytes
  further into each sector — declaring it Mode 1 without moving the data is what made every CHD
  produced before v1.5.1 unreadable.
- **The boot binary is shuffled the way a GD-ROM master holds it.** A pressed GD-ROM stores the
  binary as a permutation of 32-byte slices and the bootstrap unshuffles it on load, while a
  self-boot CD-R — which a DiscJuggler image is by construction — stores it straight, because the
  ripper that made the CD-R unshuffled it. What is written here is a GD-ROM, so the shuffle goes
  back on. This is unconditional: an earlier version guessed from the binary's byte statistics
  whether it was already shuffled, and on real discs the guess was wrong often enough to be
  useless — and getting it wrong loads garbage into RAM and reboot-loops the game.
- **Filler tracks are added if the disc has fewer than three**, since Flycast refuses a CHD with
  fewer. The filler is empty data sectors in the low-density area, which nothing reads. They have
  to be *data* tracks — a reader that finds only audio there decides the disc has no regions and
  rejects it — and the first track has to start at address zero, because addresses are rebased on
  track 1 when the CHD is written.

#### Extracting CHD Files

- When extracting CHD → BIN/CUE or CHD → GDI, multiple files may be created
- The output path you specify will be the main file (cue or gdi)
- Associated track files will be created in the same directory

### Advanced Options

Enable "Advanced Mode" in the Options section to access more chdman parameters:

- **Hunk Size (`-hs`)**: Adjust the compression chunk size (advanced users only)
- **Output BIN Filename (`-ob`)**: Specify custom output filename for BIN files when extracting
- **Verify (`-v`)**: Verify the file after compression/extraction
- **Proceed if not perfect (`-np`)**: Continue even if chdman detects a non-perfect source

### Troubleshooting

If you encounter issues, check the built-in troubleshooting guide:

1. See `TROUBLESHOOTING.md` in the app's documentation folder
2. Common issues:
   - **"Permission Denied"**: May need to disable App Sandbox in development builds
   - **"chdman not found"**: Verify chdman is installed and the path is correct
   - **"File exists"**: Enable the `-f` (force overwrite) option
   - **Conversion fails immediately**: Check that input file format matches conversion type
   - **CDI refused with "cannot be converted to a CHD"**: The disc's own data sits across the
     address an emulator reads a GD-ROM's boot header from, and the disc cannot safely be rebuilt
     around it — its boot program reads the disc by raw address. See
     [CDI Files](#cdi-files). Use the `.cdi` directly — redream and Flycast both open them.
   - **CDI refused for having CD audio tracks**: A GD-ROM has nowhere to keep a CD soundtrack, and
     such a disc boots and then stops at its first screen. See [CDI Files](#cdi-files). Use the
     `.cdi` directly.

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

### CDI

- Dreamcast disc image format created by DiscJuggler
- Proprietary single-file container with no public specification
- Not readable by `chdman`, so it cannot be converted directly by Swift-CHD
- Convert to BIN/CUE first with a third-party tool if you need a CHD

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

- **chdman**: Part of the MAME project (<https://www.mamedev.org>)
- **Swift-CHD**: A modern Swift/SwiftUI frontend for macOS

## License

Swift-CHD is free software, licensed under the **GNU General Public License, version 2 or later** —
see [LICENSE](LICENSE) for the full text.

You may use, modify, and redistribute it, including commercially. If you distribute a modified
version, it must also be released under the GPL with its source available. Note that GPL licensing
is incompatible with Mac App Store distribution; direct downloads and Homebrew are unaffected.

All code here is original. The DiscJuggler reader in `CDIImage.swift` was written from an empirical
analysis of real disc images rather than from any existing implementation — see that file's header.

chdman itself is part of MAME and is not bundled — Swift-CHD launches whichever copy you have
installed, as a separate process. Please respect the MAME project's licensing terms when using it.

---

**Enjoy preserving your disc images with Swift-CHD!** 🎮💿
