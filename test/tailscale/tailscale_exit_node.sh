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

check "sets the exit node" grep -qx -- --exit-node=test-exit-node /tmp/test-tailscale-up-args

reportResults
