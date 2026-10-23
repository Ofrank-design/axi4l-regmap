#!/bin/sh
# Fetch the third-party AXI pieces used by the integration test and the
# external protocol check. Nothing is vendored; they land in third_party/
# (git-ignored) so their Apache-2.0 licence stays with them.
set -e
cd "$(dirname "$0")/.."
if [ ! -d third_party/wb2axip ]; then
    mkdir -p third_party
    git clone --depth 1 https://github.com/ZipCPU/wb2axip.git third_party/wb2axip
fi
echo "third_party/wb2axip ready"
