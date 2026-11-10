#!/bin/zsh
# Build the "kvm" firmware: stock NuPhy Air60 V2 VIA firmware where the rear
# Mac/Win switch also selects the Bluetooth slot (Mac -> BT1, Win -> BT2).
# Requires git, python3, and arm-none-eabi-gcc on PATH.
set -euo pipefail
here=${0:a:h}
work=${1:-$here/.work}
mkdir -p $work
if [[ ! -d $work/qmk ]]; then
  git clone -q https://github.com/nuphy-src/qmk_firmware.git $work/qmk
  git -C $work/qmk checkout -q $(cat $here/UPSTREAM_COMMIT)
  git -C $work/qmk submodule update --init --depth 1 -q
fi
cd $work/qmk
git checkout -q -- keyboards/nuphy/air60_v2/ansi/ansi.c
git apply $here/sys-sw-bt-slot.patch
km=keyboards/nuphy/air60_v2/ansi/keymaps
rm -rf $km/kvm && cp -r $km/via $km/kvm && cp $here/kvm-config.h $km/kvm/config.h
cp $here/kvm-pad.c $km/kvm/pad.c && printf 'SRC += pad.c\n' >> $km/kvm/rules.mk
[[ -d $work/venv ]] || { python3 -m venv $work/venv && $work/venv/bin/pip -q install -r requirements.txt; }
command -v dfu-suffix >/dev/null || { mkdir -p $work/stub; printf '#!/bin/sh\nexit 0\n' > $work/stub/dfu-suffix; chmod +x $work/stub/dfu-suffix; }
PATH=$work/stub:$work/venv/bin:$PATH make -j8 nuphy/air60_v2/ansi:kvm
ls -l $work/qmk/nuphy_air60_v2_ansi_kvm.bin
