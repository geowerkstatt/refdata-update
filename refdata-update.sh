#!/bin/sh
# Refreshes the reference data named in the sources file. Each source is downloaded once per run; a destination is only
# replaced by a complete file that looks like an INTERLIS transfer, renamed over the old one, so a failed fetch leaves
# the last state in place.
# shortcut: atomic per file, not across the set, so a validation running meanwhile may see old and new files mixed.
# shortcut: the model cache of the ilitools-wrapper is not reset afterwards, that operation does not exist yet
# (geowerkstatt/geopilot#1043). Files in a subfolder are fetched fresh by every run today only because of
# claeis/ili2c#165.
set -u

# Overridable so test.sh can run against its own directories.
sources=${REFDATA_SOURCES:-/config/sources.yaml}
root=${REFDATA_ROOT:-/refdata}
# Touched after a run without failures; the HEALTHCHECK of the image reports its age.
stamp=${REFDATA_STAMP:-/var/lib/refdata-update/last-success}
failed=0

log() {
  echo "$(date '+%Y-%m-%dT%H:%M:%S%z') refdata-update: $*"
}

kept() {
  log "kept $1: $2"
  failed=$((failed + 1))
}

field() {
  yq -r "$1 // \"\"" "$sources"
}

is_relative_path() {
  case "$1" in '' | /* | .. | ../* | */.. | */../*) return 1 ;; esac
}

is_transfer() {
  [ -s "$1" ] && head -c 4096 "$1" | grep -qiE '<([a-z0-9]+:)?transfer[ >]'
}

has_entry() {
  unzip -l "$1" | sed -n 's/^ *[0-9][0-9]* *[^ ][^ ]* *[^ ][^ ]* *//p' | grep -Fxq "$2"
}

# Prints the hidden file beside a destination that a download is written to before it is renamed over it.
part_of() {
  dest="$root/$1"
  mkdir -p "$(dirname "$dest")" && echo "$(dirname "$dest")/.$(basename "$dest").part"
}

publish() {
  part=$1 destination=$2 origin=$3
  if ! is_transfer "$part"; then
    rm -f "$part"
    kept "$destination" "$origin did not deliver an INTERLIS transfer"
    return
  fi
  if mv -f "$part" "$root/$destination"; then
    log "replaced $destination ($(wc -c < "$root/$destination") bytes) from $origin"
  else
    kept "$destination" "could not replace it"
  fi
}

refresh_file() {
  source=$1 destination=$2
  if ! is_relative_path "$destination"; then
    kept "${destination:-source $source}" "the destination must be a relative path below $root"
    return
  fi
  part=$(part_of "$destination") || { kept "$destination" "could not create its folder"; return; }
  if ! wget -q -T 60 -O "$part" "$source"; then
    rm -f "$part"
    kept "$destination" "download from $source failed"
    return
  fi
  publish "$part" "$destination" "$source"
}

refresh_archive() {
  index=$1 source=$2
  count=$(yq ".[$index].extract | length" "$sources")
  if [ "$count" -eq 0 ]; then
    kept "source $source" "extract names no entry"
    return
  fi

  archive="$work/$index.zip"
  if ! wget -q -T 60 -O "$archive" "$source"; then
    j=0
    while [ "$j" -lt "$count" ]; do
      kept "$(field ".[$index].extract[$j].destination")" "download from $source failed"
      j=$((j + 1))
    done
    rm -f "$archive"
    return
  fi

  j=0
  while [ "$j" -lt "$count" ]; do
    entry=$(field ".[$index].extract[$j].entry")
    destination=$(field ".[$index].extract[$j].destination")
    j=$((j + 1))
    if ! is_relative_path "$destination"; then
      kept "${destination:-entry $entry}" "the destination must be a relative path below $root"
    elif [ -z "$entry" ] || ! has_entry "$archive" "$entry"; then
      kept "$destination" "$source holds no entry '$entry'"
    elif ! part=$(part_of "$destination"); then
      kept "$destination" "could not create its folder"
    elif ! unzip -p "$archive" "$entry" > "$part"; then
      rm -f "$part"
      kept "$destination" "could not unpack $entry from $source"
    else
      publish "$part" "$destination" "$source ($entry)"
    fi
  done
  rm -f "$archive"
}

refresh_source() {
  index=$1
  source=$(field ".[$index].source")
  destination=$(field ".[$index].destination")
  has_extract=$(yq ".[$index] | has(\"extract\")" "$sources")
  case "$source" in
    http://* | https://*) ;;
    *) kept "source $((index + 1))" "only http and https sources are supported, got '$source'"; return ;;
  esac
  if [ "$has_extract" = true ] && [ -n "$destination" ]; then
    kept "source $source" "it names both destination and extract"
  elif [ "$has_extract" = true ]; then
    refresh_archive "$index" "$source"
  else
    refresh_file "$source" "$destination"
  fi
}

if [ ! -r "$sources" ]; then
  log "no sources file at $sources"
  exit 1
fi
if ! yq -e 'tag == "!!seq"' "$sources" > /dev/null 2>&1; then
  log "$sources is not a YAML list of sources"
  exit 1
fi

# The start run and a scheduled run may overlap when large files are fetched.
exec 9> /tmp/refdata-update.lock
if ! flock -n 9; then
  log "a previous run is still active, skipped"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

total=$(yq 'length' "$sources")
i=0
while [ "$i" -lt "$total" ]; do
  refresh_source "$i"
  i=$((i + 1))
done

if [ "$failed" -gt 0 ]; then
  log "finished, $failed destination(s) kept their last state"
  exit 1
fi
mkdir -p "$(dirname "$stamp")" && touch "$stamp"
log "finished"
