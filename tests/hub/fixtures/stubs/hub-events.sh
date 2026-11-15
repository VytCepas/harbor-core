#!/usr/bin/env sh
# Stub of hub-events.sh (harbor#1278): logs every record.
printf '%s\n' "$*" >> "${0%/*}/stub-events.log"
exit 0
