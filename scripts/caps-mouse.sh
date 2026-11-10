#!/bin/zsh
cd ${0:a:h}/../bin
until ./via-raw 01 2>/dev/null | grep -q '^resp 01'; do sleep 2; done
echo "device up"
fn=$(./via-raw 04 00 05 0a | awk '/resp/{print $6$7}'); caps=$(./via-raw 04 00 03 00 | awk '/resp/{print $6$7}')
echo "layer0 Fn=$fn Caps=$caps"
[[ $fn == 5221 && ( $caps == 0039 || $caps == 5227 ) ]] || { echo "unexpected keycodes, abort"; exit 1; }
set_key(){ ./via-raw 05 $1 $2 $3 $4 $5 | grep resp; }
# layer7: arrows -> mouse move, space -> left click, del -> right click
set_key 07 04 0f 00 cd; set_key 07 05 0f 00 ce; set_key 07 05 0e 00 cf; set_key 07 05 10 00 d0
set_key 07 05 06 00 d1; set_key 07 02 0e 00 d2
# layer7 snap keys for bin/snap: H/J/K/L -> F13-F16 (element), A/S/W/D -> Shift+F13-F16 (window)
set_key 07 03 06 00 68; set_key 07 03 07 00 69; set_key 07 03 08 00 6a; set_key 07 03 09 00 6b
set_key 07 03 01 02 68; set_key 07 03 02 02 69; set_key 07 02 02 02 6a; set_key 07 03 03 02 6b
# Caps -> MO(7) on Mac(0) and Win(3) base layers
set_key 00 03 00 52 27; set_key 03 03 00 52 27
echo verify; ./via-raw 04 00 03 00 | grep resp; ./via-raw 04 07 05 0e | grep resp
echo DONE
