#!/bin/zsh
cd ${0:a:h}/../bin
until ./via-raw 01 2>/dev/null | grep -q '^resp 01'; do sleep 2; done
echo "device up"
fn=$(./via-raw 04 00 05 0a | awk '/resp/{print $6$7}'); caps=$(./via-raw 04 00 03 00 | awk '/resp/{print $6$7}')
echo "layer0 Fn=$fn Caps=$caps"
[[ $fn == 5221 && ( $caps == 0039 || $caps == 5227 || $caps == 4768 ) ]] || { echo "unexpected keycodes, abort"; exit 1; }
set_key(){ ./via-raw 05 $1 $2 $3 $4 $5 | grep resp; }
# layer7: arrows -> mouse move, space -> left click, del -> right click
set_key 07 04 0f 00 cd; set_key 07 05 0f 00 ce; set_key 07 05 0e 00 cf; set_key 07 05 10 00 d0
set_key 07 02 0e 00 d2
# clear keys used by earlier snap versions (H/J/K/L, A/S/W/D, Enter)
for rc in "03 06" "03 07" "03 08" "03 09" "03 01" "03 02" "02 02" "03 03" "04 09" "03 0d"; do set_key 07 ${=rc} 00 01; done
set_key 07 05 06 00 d1   # Caps+Space -> left click
# Caps: hold -> layer 7, tap -> F13 (snap pad); kvm firmware lights the letter block meanwhile on Mac(0) and Win(3) base layers
set_key 00 03 00 47 68; set_key 03 03 00 47 68
echo verify; ./via-raw 04 00 03 00 | grep resp; ./via-raw 04 07 05 0e | grep resp
echo DONE
