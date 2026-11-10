#!/bin/zsh
# Put Dvorak into the keyboard firmware (Mac layer 0 and Win layer 3) and make a
# Ctrl tap toggle the Japanese IME, then switch macOS to the QWERTY (ABC) layout
# so the OS does not apply Dvorak a second time.
#   Mac: Ctrl tap -> F18, bound to "Select the previous input source".
#   Win: Ctrl tap -> LANG2 (VK_KANJI, IME on/off in MS-IME).
# Holding Ctrl still acts as Ctrl. Fn-layer shortcuts keep their physical positions.
set -euo pipefail
cd ${0:a:h}/../bin
via() { ./via-raw "$@" | awk '/^resp/{print}'; }
until ./via-raw 01 2>/dev/null | grep -q '^resp 01'; do sleep 2; done
echo "keyboard on USB"
fn=$(./via-raw 04 00 05 0a | awk '/resp/{print $6$7}')
[[ $fn == 5221 ]] || { echo "layer 0 Fn is $fn, expected 5221; abort"; exit 1; }

# row col keycode (QWERTY position -> Dvorak keycode)
map=(
  "01 0b 00 2f" "01 0c 00 30"
  "02 01 00 34" "02 02 00 36" "02 03 00 37" "02 04 00 13" "02 05 00 1c" "02 06 00 09"
  "02 07 00 0a" "02 08 00 06" "02 09 00 15" "02 0a 00 0f" "02 0b 00 38" "02 0c 00 2e"
  "03 01 00 04" "03 02 00 12" "03 03 00 08" "03 04 00 18" "03 05 00 0c" "03 06 00 07"
  "03 07 00 0b" "03 08 00 17" "03 09 00 11" "03 0a 00 16" "03 0b 00 2d"
  "04 02 00 33" "04 03 00 14" "04 04 00 0d" "04 05 00 0e" "04 06 00 1b" "04 07 00 05"
  "04 08 00 10" "04 09 00 1a" "04 0a 00 19" "04 0b 00 1d"
)
for layer in 00 03; do
  for e in $map; do via 05 $layer ${=e} >/dev/null; done
done
via 05 00 05 00 21 6d >/dev/null   # Mac: LCTL_T(KC_F18)
via 05 03 05 00 21 91 >/dev/null   # Win: LCTL_T(KC_LNG2)
echo "verify: L0 Q-pos=$(./via-raw 04 00 02 01 | awk '/resp/{print $6$7}') L3 S-pos=$(./via-raw 04 03 03 02 | awk '/resp/{print $6$7}') L0 Ctrl=$(./via-raw 04 00 05 00 | awk '/resp/{print $6$7}') L3 Ctrl=$(./via-raw 04 03 05 00 | awk '/resp/{print $6$7}')"

if [[ $(uname) == Darwin ]]; then
  # "Select the previous input source" (id 60) -> F18 (keycode 79, function-key flag)
  /usr/bin/defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 60 \
    '<dict><key>enabled</key><true/><key>value</key><dict><key>type</key><string>standard</string><key>parameters</key><array><integer>65535</integer><integer>79</integer><integer>8388608</integer></array></dict></dict>'
  /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  ./input-source enable com.apple.keylayout.ABC
  ./input-source select com.apple.keylayout.ABC
  ./input-source disable com.apple.keylayout.Dvorak || true
fi
echo DONE
