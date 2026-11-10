#!/bin/zsh
# Install kvm-switch as a per-user LaunchAgent.
# usage: scripts/install-kvm-switch.sh <connect-input> [disconnect-input]
# example (this Mac on HDMI2, other host on HDMI1): scripts/install-kvm-switch.sh 18 17
set -euo pipefail
[[ $# -ge 1 ]] || { echo "usage: $0 <connect-input> [disconnect-input]"; exit 64; }
root=${0:a:h:h}
bin=$HOME/.local/bin/kvm-switch
label=dev.nuphy.kvm-switch
plist=$HOME/Library/LaunchAgents/$label.plist
mkdir -p ${bin:h} ${plist:h} $HOME/Library/Logs
install -m 755 $root/bin/kvm-switch $bin
args="<string>$bin</string><string>--connect</string><string>$1</string>"
[[ $# -ge 2 ]] && args+="<string>--disconnect</string><string>$2</string>"
cat > $plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>$args</array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/kvm-switch.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/kvm-switch.log</string>
</dict></plist>
PLIST
launchctl bootout gui/$(id -u)/$label 2>/dev/null || true
launchctl bootstrap gui/$(id -u) $plist
echo "installed $label: connect -> $1${2:+, disconnect -> $2}"
