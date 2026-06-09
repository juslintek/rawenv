#!/opt/homebrew/bin/bash
# Windows VM management for rawenv testing
# Usage: ./vm-windows.sh [start|stop|ssh|screenshot|build|test]
# NOTE: On ARM64 Mac, quickget cannot download Windows ISOs automatically.
#       Manually place a Windows 11 ARM64 ISO and create windows-11.conf,
#       or use UTM/Parallels for Windows ARM64 testing.

set -euo pipefail
VM_DIR="$(dirname "$0")/vms"
VM_CONF="$VM_DIR/windows-11.conf"
SSH_PORT=22221
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
USER=user
PASS=user

wait_for_ssh() {
  echo "Waiting for SSH..."
  for i in $(seq 1 90); do
    if sshpass -p "$PASS" ssh $SSH_OPTS -p $SSH_PORT $USER@localhost "echo ok" &>/dev/null; then
      echo "SSH ready"
      return 0
    fi
    sleep 3
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
  build)
    perl -e 'alarm 180; exec @ARGV' -- sshpass -p "$PASS" ssh $SSH_OPTS -p $SSH_PORT $USER@localhost \
      "cd C:/rawenv/gui/windows && dotnet build Rawenv.sln 2>&1 | tail -10"
    ;;
  test)
    perl -e 'alarm 180; exec @ARGV' -- sshpass -p "$PASS" ssh $SSH_OPTS -p $SSH_PORT $USER@localhost \
      "cd C:/rawenv/gui/windows && dotnet test Rawenv.E2E/ 2>&1 | tail -20"
    ;;
  *)
    echo "Usage: $0 [start|stop|ssh|screenshot|build|test]"
    ;;
esac
