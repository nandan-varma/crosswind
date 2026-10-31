#!/bin/sh
# Writes GuestImage.json for an image directory built by image/build.sh.
# usage: image-manifest.sh <image-dir> <version> <base-url> > GuestImage.json
set -eu
dir=$1 version=$2 base=$3
python3 -I - "$dir" "$version" "$base" <<'PY'
import json, os, sys
d, version, base = sys.argv[1:4]
files = []
for line in open(os.path.join(d, "SHA256SUMS")):
    digest, name = line.split()
    files.append({"name": name, "size": os.path.getsize(os.path.join(d, name)),
                  "sha256": digest, "url": base.rstrip("/") + "/" + name})
print(json.dumps({"version": version, "files": files}, indent=2))
PY
