#!/bin/bash
# verify_chdman.sh - Run this in Terminal to verify your chdman installation

echo "==================================="
echo "CHDMan Installation Verification"
echo "==================================="
echo ""

# Check if chdman is in PATH
echo "1. Checking for chdman in PATH..."
if command -v chdman &> /dev/null; then
    CHDMAN_PATH=$(which chdman)
    echo "   ✅ Found: $CHDMAN_PATH"
else
    echo "   ❌ NOT found in PATH"
fi
echo ""

# Check common Homebrew locations
echo "2. Checking common Homebrew locations..."

if [ -f "/opt/homebrew/bin/chdman" ]; then
    echo "   ✅ Apple Silicon: /opt/homebrew/bin/chdman EXISTS"
    if [ -x "/opt/homebrew/bin/chdman" ]; then
        echo "      ✅ Is executable"
    else
        echo "      ❌ NOT executable (run: chmod +x /opt/homebrew/bin/chdman)"
    fi
else
    echo "   ❌ Apple Silicon: /opt/homebrew/bin/chdman NOT FOUND"
fi

if [ -f "/usr/local/bin/chdman" ]; then
    echo "   ✅ Intel Mac: /usr/local/bin/chdman EXISTS"
    if [ -x "/usr/local/bin/chdman" ]; then
        echo "      ✅ Is executable"
    else
        echo "      ❌ NOT executable (run: chmod +x /usr/local/bin/chdman)"
    fi
else
    echo "   ❌ Intel Mac: /usr/local/bin/chdman NOT FOUND"
fi
echo ""

# Try to get version
echo "3. Testing chdman execution..."
if [ -n "$CHDMAN_PATH" ]; then
    VERSION=$("$CHDMAN_PATH" --help 2>&1 | head -n 1)
    echo "   Version info: $VERSION"
    echo "   ✅ chdman can be executed"
else
    echo "   ⚠️  Cannot test execution (chdman not found)"
fi
echo ""

# Check MAME installation
echo "4. Checking MAME (parent package)..."
if brew list mame &> /dev/null; then
    echo "   ✅ MAME is installed via Homebrew"
    MAME_VERSION=$(brew list --versions mame)
    echo "      $MAME_VERSION"
else
    echo "   ❌ MAME is NOT installed via Homebrew"
    echo ""
    echo "   To install, run:"
    echo "   brew install mame"
fi
echo ""

# Final recommendation
echo "==================================="
echo "RECOMMENDATIONS FOR YOUR APP"
echo "==================================="
echo ""

if [ -n "$CHDMAN_PATH" ]; then
    echo "✅ Use this path in your app:"
    echo "   $CHDMAN_PATH"
    echo ""
    echo "✅ Paste this exact path into the 'chdman:' field"
    echo "✅ Then click the 'Verify' button"
else
    echo "❌ chdman is NOT installed!"
    echo ""
    echo "Install it with:"
    echo "   brew install mame"
    echo ""
    echo "If Homebrew is not installed:"
    echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
fi

echo ""
echo "==================================="
echo "IMPORTANT: DISABLE APP SANDBOX!"
echo "==================================="
echo ""
echo "In Xcode:"
echo "1. Select target → Signing & Capabilities"
echo "2. Remove 'App Sandbox' (click ❌)"
echo "3. Clean build (Cmd+Shift+K)"
echo "4. Rebuild and run"
echo ""
echo "Without this, your app CANNOT run chdman!"
echo ""
