#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/create-local-appcast.sh <dmg-path> <short-version> <build-number> <sparkle-ed-signature> [port] [output-dir]

Example:
  scripts/create-local-appcast.sh ~/Desktop/Odysseus-1.0.1.dmg 1.0.1 101 'BASE64_SIGNATURE' 8808 /tmp/odysseus-ota
USAGE
}

if [[ $# -lt 4 || $# -gt 6 ]]; then
  usage >&2
  exit 64
fi

dmg_path="$1"
short_version="$2"
build_number="$3"
signature="$4"
port="${5:-8808}"
output_dir="${6:-/tmp/odysseus-ota}"

if [[ ! -f "$dmg_path" ]]; then
  echo "DMG not found: $dmg_path" >&2
  exit 66
fi

mkdir -p "$output_dir"
dmg_name="$(basename "$dmg_path")"
cp "$dmg_path" "$output_dir/$dmg_name"

byte_length="$(stat -f%z "$output_dir/$dmg_name")"
pub_date="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

cat > "$output_dir/appcast.xml" <<XML
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>Odysseus Local Updates</title>
        <item>
            <title>Odysseus ${short_version}</title>
            <pubDate>${pub_date}</pubDate>
            <sparkle:version>${build_number}</sparkle:version>
            <sparkle:shortVersionString>${short_version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.2</sparkle:minimumSystemVersion>
            <enclosure
                url="http://127.0.0.1:${port}/${dmg_name}"
                length="${byte_length}"
                type="application/octet-stream"
                sparkle:edSignature="${signature}"/>
        </item>
    </channel>
</rss>
XML

echo "Wrote $output_dir/appcast.xml"
echo "Copied $output_dir/$dmg_name"
echo "Serve with:"
echo "  cd \"$output_dir\" && python3 -m http.server $port --bind 127.0.0.1"
