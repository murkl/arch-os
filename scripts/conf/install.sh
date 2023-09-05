#!/usr/bin/env bash

# Dash to panel
dconf reset -f /org/gnome/shell/extensions/dash-to-panel/
dconf load /org/gnome/shell/extensions/dash-to-panel/ <dash-to-panel.conf

# Just Perfection
dconf reset -f /org/gnome/shell/extensions/just-perfection/
dconf load /org/gnome/shell/extensions/just-perfection/ <just-perfection.conf
