#!/bin/sh
      while [ "$(hostname -I)" = "" ]; do
        sleep 1
      done
      tmux new-session -d  'pianobar'
      tmux split-window -v 'cd ~/Patiobar && node index.js'
      tmux split-window -h  "bluetoothctl connect $SPK_MAC"