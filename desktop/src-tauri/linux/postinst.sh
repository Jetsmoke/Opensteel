#!/bin/sh
# Apply the new udev rule to a mouse that is already plugged in.
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=hidraw 2>/dev/null || true
