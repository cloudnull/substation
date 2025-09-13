#!/bin/bash

echo "=== OpenStack TUI Resize Functionality Test ==="
echo

echo "1. Building the application..."
cd /Users/kevin.carter/projects/otui
swift build

echo
echo "2. Testing resize functionality..."
echo "   a. Launch the app with: ./.build/debug/otui --cloud rxt-sjc-mine-free"
echo "   b. Press 'S' to go to servers view"
echo "   c. Navigate to the 'Test' server using arrow keys"
echo "   d. Press 'Z' to initiate resize"
echo "   e. Use ←/→ to select flavor (look for gp.0.2.4)"
echo "   f. Press ENTER to start resize confirmation"
echo "   g. Press 'Y' to confirm the resize"
echo
echo "Expected debug output should show:"
echo "  - DEBUG: Starting resize for server: Test"
echo "  - DEBUG: Opening resize dialog with X flavors available"
echo "  - DEBUG: Flavor listings..."
echo "  - DEBUG: User confirmed resize to flavor: [flavor-id]"
echo "  - DEBUG: Resizing server [server-id] to flavor [flavor-id]"
echo "  - DEBUG: Request body: {\"resize\":{\"flavorRef\":\"[flavor-id]\"}}"
echo "  - DEBUG: Resize request completed successfully - received 202 response"
echo
echo "If any of these debug messages are missing, it indicates where the process fails."
echo
echo "Common issues and debugging:"
echo "  - No debug output at all: Z key binding not working or server not selected"
echo "  - Dialog opens but no confirmation: User not pressing Y after ENTER"
echo "  - API call fails: Check authentication, server state, or flavor availability"
echo
echo "Launch the app manually to test the resize functionality:"
echo "./.build/debug/otui --cloud rxt-sjc-mine-free"