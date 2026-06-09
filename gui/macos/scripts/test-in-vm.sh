#!/bin/bash
# gui/macos/scripts/test-in-vm.sh
# Runs the macOS SwiftUI app and tests inside a Tart VM with full desktop access.
#
# Prerequisites:
#   brew install cirruslabs/cli/tart sshpass
#   tart clone ghcr.io/cirruslabs/macos-tahoe-xcode:latest rawenv-test
#
# Usage:
#   ./scripts/test-in-vm.sh [build|run|test|screenshot|all]

set -euo pipefail

VM_NAME="rawenv-test"
VM_USER="admin"
VM_PASS="admin"
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
MOUNT_NAME="rawenv"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

ssh_cmd() {
    sshpass -p "$VM_PASS" ssh $SSH_OPTS "$VM_USER@$VM_IP" "$@"
}

scp_cmd() {
    sshpass -p "$VM_PASS" scp $SSH_OPTS "$@"
}

wait_for_vm() {
    info "Waiting for VM to boot and SSH to become available..."
    for i in $(seq 1 60); do
        VM_IP=$(tart ip "$VM_NAME" 2>/dev/null || true)
        if [ -n "$VM_IP" ]; then
            if sshpass -p "$VM_PASS" ssh $SSH_OPTS -o ConnectTimeout=3 "$VM_USER@$VM_IP" "echo ok" &>/dev/null; then
                info "VM ready at $VM_IP"
                return 0
            fi
        fi
        sleep 2
    done
    err "VM did not become ready within 120 seconds"
}

ensure_vm_running() {
    if ! tart list | grep -q "$VM_NAME"; then
        err "VM '$VM_NAME' not found. Run: tart clone ghcr.io/cirruslabs/macos-tahoe-xcode:latest $VM_NAME"
    fi

    # Check if already running
    if tart ip "$VM_NAME" &>/dev/null; then
        VM_IP=$(tart ip "$VM_NAME")
        info "VM already running at $VM_IP"
    else
        info "Starting VM with project directory mounted..."
        tart run "$VM_NAME" --dir="$MOUNT_NAME:$PROJECT_DIR" --no-graphics &
        VM_PID=$!
        wait_for_vm
    fi
}

do_build() {
    info "Building SwiftUI app inside VM..."
    ssh_cmd "cd '/Volumes/My Shared Files/$MOUNT_NAME/gui/macos' && swift build 2>&1" | tail -5
    local exit_code=${PIPESTATUS[0]}
    if [ $exit_code -eq 0 ]; then
        info "Build successful"
    else
        err "Build failed"
    fi
}

do_run() {
    info "Launching app inside VM..."
    ssh_cmd "cd '/Volumes/My Shared Files/$MOUNT_NAME/gui/macos' && .build/debug/Rawenv &>/dev/null & disown; sleep 3; echo 'App PID:' \$(pgrep -f Rawenv)"
}

do_test() {
    info "Running unit tests inside VM..."
    ssh_cmd "cd '/Volumes/My Shared Files/$MOUNT_NAME/gui/macos' && swift test 2>&1" | tail -20
    info "Running XCUITest (requires Xcode)..."
    ssh_cmd "cd '/Volumes/My Shared Files/$MOUNT_NAME/gui/macos' && xcodebuild test -scheme Rawenv -destination 'platform=macOS' 2>&1" | tail -20
}

do_screenshot() {
    info "Taking screenshot via VNC..."
    # Method 1: SSH + screencapture (works when logged in)
    ssh_cmd "screencapture -x /tmp/rawenv-screenshot.png" 2>/dev/null && \
        scp_cmd "$VM_USER@$VM_IP:/tmp/rawenv-screenshot.png" "/tmp/rawenv-vm-screenshot.png" && \
        info "Screenshot saved to /tmp/rawenv-vm-screenshot.png" && return 0

    # Method 2: vncdotool via VNC (works headless)
    info "Falling back to VNC capture..."
    local VNC_PORT=5900
    ~/Library/Python/3.9/bin/vncdotool -s "$VM_IP::$VNC_PORT" -p "$VM_PASS" capture /tmp/rawenv-vm-screenshot.png
    info "VNC screenshot saved to /tmp/rawenv-vm-screenshot.png"
}

do_stop() {
    info "Stopping VM..."
    tart stop "$VM_NAME" 2>/dev/null || true
}

# Main
case "${1:-all}" in
    build)
        ensure_vm_running
        do_build
        ;;
    run)
        ensure_vm_running
        do_build
        do_run
        ;;
    test)
        ensure_vm_running
        do_build
        do_test
        ;;
    screenshot)
        ensure_vm_running
        do_screenshot
        ;;
    all)
        ensure_vm_running
        do_build
        do_run
        sleep 2
        do_screenshot
        do_test
        do_stop
        ;;
    stop)
        do_stop
        ;;
    *)
        echo "Usage: $0 [build|run|test|screenshot|all|stop]"
        exit 1
        ;;
esac
