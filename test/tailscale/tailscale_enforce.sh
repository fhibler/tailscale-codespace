#!/usr/bin/env bash
# Copyright (c) 2025 Tailscale Inc & AUTHORS All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

set -e

source dev-container-features-test-lib

# No auth key is set, so the container is never signed in and the guard must
# flag every interactive zsh.
check "jq is installed" jq --version
check "guard is installed" test -r /usr/local/share/tailscale/tailscale-guard.zsh
check "guard warns when not signed in" bash -c "zsh -ic true 2>&1 | grep -q 'UNSECURE CONNECTION'"
check "guard names the reason" bash -c "zsh -ic true 2>&1 | grep -q 'Reason:'"
check "guard marks the prompt" bash -c "zsh -ic '_ts_guard_precmd; print -rn -- \${(%)PROMPT}' 2>&1 | grep -q 'UNSECURE'"
check "guard is silent without TS_ENFORCE" bash -c "! TS_ENFORCE=0 zsh -ic true 2>&1 | grep -q UNSECURE"

reportResults
