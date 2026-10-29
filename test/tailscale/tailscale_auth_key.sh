#!/usr/bin/env bash
# Copyright (c) 2025 Tailscale Inc & AUTHORS All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

set -e

source dev-container-features-test-lib

# Wait for the start script to record the `tailscale up` arguments.
count=100
while ((count--)); do
    [[ -f /tmp/test-tailscale-up-args ]] && break
    sleep 0.1
done

check "accepts routes" grep -qx -- --accept-routes /tmp/test-tailscale-up-args
check "uses the codespace name as hostname" grep -qx -- --hostname=test-codespace /tmp/test-tailscale-up-args
check "sets no exit node by default" bash -c "! grep -q -- --exit-node /tmp/test-tailscale-up-args"

# It would be nice to directly test that the entrypoint is doing unset
# TS_AUTH_KEY, however that isn't visible to the test execution.

reportResults
