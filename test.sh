#!/bin/sh
# Self-check of refdata-update, run by the test stage of the Dockerfile against a local httpd.
set -eu

work=$(mktemp -d)
www="$work/www"
root="$work/refdata"
mkdir -p "$www/inner" "$root/a"

old='<?xml version="1.0"?><TRANSFER xmlns="http://www.interlis.ch/INTERLIS2.3">old</TRANSFER>'
new='<?xml version="1.0"?><TRANSFER xmlns="http://www.interlis.ch/INTERLIS2.3">new</TRANSFER>'
first='<?xml version="1.0"?><ili:transfer xmlns:ili="http://www.interlis.ch/xtf/2.4/INTERLIS">first</ili:transfer>'
second='<?xml version="1.0"?><ili:transfer xmlns:ili="http://www.interlis.ch/xtf/2.4/INTERLIS">second</ili:transfer>'

echo "$new" > "$www/good.xtf"
echo '<html>Service unavailable</html>' > "$www/error.html"
echo "$first" > "$www/inner/first.xtf"
echo "$second" > "$www/inner/second.xtf"
echo 'readme' > "$www/inner/readme.txt"
(cd "$www" && zip -q archive.zip inner/first.xtf inner/second.xtf inner/readme.txt && rm -r inner)
for f in a/replaced.xtf a/kept-on-404.xtf a/kept-on-invalid.xtf a/kept-on-missing-entry.xtf a/kept-on-scheme.xtf \
  a/kept-on-both.xtf; do
  echo "$old" > "$root/$f"
done

base=http://127.0.0.1:8099
# Written with CRLF line endings, as a sources file edited on Windows would be.
sed 's/$/\r/' > "$work/sources.yaml" << EOF
# comment
- source: $base/good.xtf
  destination: a/replaced.xtf
- source: $base/missing.xtf
  destination: a/kept-on-404.xtf
- source: $base/error.html
  destination: a/kept-on-invalid.xtf
- source: $base/archive.zip
  extract:
    - entry: inner/first.xtf
      destination: b/first.xtf
    - entry: inner/second.xtf
      destination: b/second.xtf
    - entry: inner/absent.xtf
      destination: a/kept-on-missing-entry.xtf
    - entry: inner/first.xtf
      destination: /absolute.xtf
- source: $base/good.xtf
  destination: ../escape.xtf
- source: ftp://127.0.0.1/good.xtf
  destination: a/kept-on-scheme.xtf
- source: $base/good.xtf
  destination: a/kept-on-both.xtf
  extract:
    - entry: inner/first.xtf
      destination: a/kept-on-both.xtf
- source: $base/good.xtf
  destination: new/created.xtf
EOF

httpd -f -p 127.0.0.1:8099 -h "$www" &
httpd_pid=$!
trap 'kill $httpd_pid' EXIT
sleep 1

# Records every download, so the test can tell that an archive is fetched once for all its entries.
mkdir "$work/bin"
printf '#!/bin/sh\necho "$@" >> %s\nexec busybox wget "$@"\n' "$work/wget.log" > "$work/bin/wget"
chmod +x "$work/bin/wget"

status=0
PATH="$work/bin:$PATH" REFDATA_SOURCES="$work/sources.yaml" REFDATA_ROOT="$root" REFDATA_STAMP="$work/stamp" \
  refdata-update || status=$?

failures=0
fail() {
  echo "FAIL $*"
  failures=$((failures + 1))
}
expect() {
  [ "$(cat "$root/$1" 2>/dev/null)" = "$2" ] || fail "$1: expected '$2', got '$(cat "$root/$1" 2>/dev/null)'"
}
expect a/replaced.xtf "$new"
expect a/kept-on-404.xtf "$old"
expect a/kept-on-invalid.xtf "$old"
expect b/first.xtf "$first"
expect b/second.xtf "$second"
expect a/kept-on-missing-entry.xtf "$old"
expect a/kept-on-scheme.xtf "$old"
expect a/kept-on-both.xtf "$old"
expect new/created.xtf "$new"
[ ! -e "$work/escape.xtf" ] || fail "../escape.xtf was written outside the root"
[ ! -e /absolute.xtf ] || fail "/absolute.xtf was written outside the root"
[ "$status" -eq 1 ] || fail "exit code: expected 1, got $status"
downloads=$(grep -c 'archive.zip' "$work/wget.log" || true)
[ "$downloads" -eq 1 ] || fail "archive.zip: expected one download, got $downloads"
leftovers=$(find "$root" -name '.*.part')
[ -z "$leftovers" ] || fail "leftovers: $leftovers"
[ ! -e "$work/stamp" ] || fail "a run with failures touched the success stamp"

printf -- '- source: %s/good.xtf\n  destination: a/replaced.xtf\n' "$base" > "$work/good.yaml"
REFDATA_SOURCES="$work/good.yaml" REFDATA_ROOT="$root" REFDATA_STAMP="$work/stamp" refdata-update > /dev/null ||
  fail "a run without failures exited with an error"
[ -e "$work/stamp" ] || fail "a run without failures did not touch the success stamp"

if [ "$failures" -gt 0 ]; then
  echo "refdata-update test: $failures failure(s)"
  exit 1
fi
echo "refdata-update test: passed"
