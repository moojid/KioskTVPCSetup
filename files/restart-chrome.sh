#!/bin/bash

export DISPLAY=:0
export XAUTHORITY=/home/boom/.Xauthority

pkill -f chromium
sleep 3

/usr/bin/chromium \
  --disable-infobars \
  --remote-debugging-port=9222 \
  --kiosk "$DISP_URL" &