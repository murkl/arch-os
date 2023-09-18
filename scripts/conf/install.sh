#!/usr/bin/env bash

# Just Perfection
# Bug: dash-separator=false (must not exists in dconf)
# dconf dump /org/gnome/shell/extensions/just-perfection/ >just-perfection.conf
dconf reset -f /org/gnome/shell/extensions/just-perfection/
dconf load /org/gnome/shell/extensions/just-perfection/ <just-perfection.conf

# Dash to panel (optional)
# dconf dump /org/gnome/shell/extensions/dash-to-panel/ >dash-to-panel.conf
dconf reset -f /org/gnome/shell/extensions/dash-to-panel/
dconf load /org/gnome/shell/extensions/dash-to-panel/ <dash-to-panel.conf
