#!/bin/bash
# Back up and restore LaunchSet's data files around a test on the real Mac.
#   userdata.sh backup <dir>    stop LaunchSet, copy config.json and history.json into <dir>
#   userdata.sh restore <dir>   stop LaunchSet, put the files back byte for byte, reopen it if it was running
set -euo pipefail
DATA="${LAUNCHSET_DATA:-$HOME/Library/Application Support/LaunchSet}"
FILES=(config.json history.json)
cmd="${1:-}"
dir="${2:-}"
[[ -n "$cmd" && -n "$dir" ]] || { echo "usage: $0 backup|restore <dir>" >&2; exit 2; }

stop_app() {
  if pgrep -x LaunchSet >/dev/null; then pkill -x LaunchSet; sleep 1; echo running; else echo stopped; fi
}

case "$cmd" in
  backup)
    [[ ! -e "$dir/.complete" ]] || { echo "$dir already holds a backup; pick a new folder so it isn't overwritten" >&2; exit 1; }
    mkdir -p "$dir"
    state=$(stop_app)
    for f in "${FILES[@]}"; do
      if [[ -f "$DATA/$f" ]]; then
        cp -p "$DATA/$f" "$dir/$f"
        cmp -s "$DATA/$f" "$dir/$f" || { echo "copy of $f doesn't match" >&2; exit 1; }
      else
        touch "$dir/$f.absent"
      fi
    done
    echo "$state" > "$dir/.app-was"
    touch "$dir/.complete"
    echo "Backed up LaunchSet data to $dir (app was $state). Nothing else will be written there."
    ;;
  restore)
    [[ -f "$dir/.complete" ]] || { echo "no complete backup in $dir" >&2; exit 1; }
    stop_app >/dev/null
    for f in "${FILES[@]}"; do
      if [[ -f "$dir/$f.absent" ]]; then
        rm -f "$DATA/$f"
      else
        cp -p "$dir/$f" "$DATA/$f"
        cmp "$dir/$f" "$DATA/$f"
      fi
    done
    echo "Restored LaunchSet data from $dir byte for byte."
    if [[ "$(cat "$dir/.app-was")" == running && -z "${LAUNCHSET_DATA:-}" ]]; then open -b local.minhdevtree.launchset; echo "Reopened LaunchSet."; fi
    ;;
  *) echo "usage: $0 backup|restore <dir>" >&2; exit 2 ;;
esac
