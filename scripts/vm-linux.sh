#!/opt/homebrew/bin/bash
# Linux VM management for rawenv testing
# Usage: ./vm-linux.sh [start|stop|ssh|screenshot|build|test]

set -euo pipefail
VM_DIR="$(dirname "$0")/vms"
VM_CONF="$VM_DIR/ubuntu-server-24.04.conf"
SSH_PORT=22220
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
USER=user
PASS=user

wait_for_ssh() {
  echo "Waiting for SSH..."
  for i in $(seq 1 60); do
    if sshpass -p "$PASS" ssh $SSH_OPTS -p $SSH_PORT $USER@localhost "echo ok" &>/dev/null; then
      echo "SSH ready"
      return 0
    fi
    sleep 2
  done
  echo "SSH timeout"
  exit 1
}

case "${1:-help}" in
  start)
    quickemu --vm "$VM_CONF" --display none &
    wait_for_ssh
    ;;
  stop)
    pkill -f "$VM_CONF" 2>/dev/null || true
    ;;
  ssh)
    shift
    perl -e 'alarm 30; exec @ARGV' -- sshpass -p "$PASS" ssh $SSH_OPTS -p $SSH_PORT $USER@localhost "$@"
    ;;
  screenshot)
    perl -e 'alarm 10; exec @ARGV' -- sshpass -p "$PASS" ssh $SSH_OPTS -p $SSH_PORT $USER@localhost \
      "DISPLAY=:0 scrot /tmp/rawenv-screenshot.png"
    sshpass -p "$PASS" scp $SSH_OPTS -P $SSH_PORT $USER@localhost:/tmp/rawenv-screenshot.png /tmp/rawenv-linux-screenshot.png
    echo "Screenshot: /tmp/rawenv-linux-screenshot.png"
    ;;
  build)
    perl -e 'alarm 120; exec @ARGV' -- sshpass -p "$PASS" ssh $SSH_OPTS -p $SSH_PORT $USER@localhost \
      "cd /mnt/rawenv/gui/linux && meson setup build 2>/dev/null || true && ninja -C build 2>&1 | tail -5"
    ;;
  test)
    perl -e 'alarm 120; exec @ARGV' -- sshpass -p "$PASS" ssh $SSH_OPTS -p $SSH_PORT $USER@localhost \
      "cd /mnt/rawenv/gui/linux && python3 -m pytest tests/e2e/ -v 2>&1 | tail -20"
    ;;
  *)
    echo "Usage: $0 [start|stop|ssh|screenshot|build|test]"
    ;;
esac
