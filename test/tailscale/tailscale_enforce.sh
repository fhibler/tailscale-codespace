#!/usr/bin/env bash
# Copyright (c) 2025 Tailscale Inc & AUTHORS All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

set -e

source dev-container-features-test-lib

# Starts an interactive zsh, which loads the guard from the system zshrc, and
# prints its startup output followed by a "PROMPT:" line with the prompt as it
# renders after two precmd runs.
guarded_zsh() {
    zsh -ic '_ts_guard_precmd; _ts_guard_precmd; print -r -- "PROMPT:${(%)PROMPT}"' 2>&1
}

# Same, but with a stand-in for the tailscale CLI that reports $1 as its
# status, or fails if $1 is empty, to reach states that need a real tailnet.
stub_dir=$(mktemp -d)
cat > "$stub_dir/tailscale" <<'EOF'
#!/bin/sh
[ -n "$FAKE_STATUS" ] && printf '%s\n' "$FAKE_STATUS"
EOF
chmod +x "$stub_dir/tailscale"
guarded_zsh_with_status() {
    FAKE_STATUS="$1" PATH="$stub_dir:$PATH" guarded_zsh
}

# Succeeds if output $2 warns with reason $1 and marks the prompt exactly once.
warns() {
    grep -q "Reason:.* $1" <<<"$2" &&
        [[ $(grep '^PROMPT:' <<<"$2" | grep -o ' UNSECURE ' | wc -l) -eq 1 ]]
}

# Succeeds if output $1 does not warn and marks the prompt SECURE exactly once.
is_secure() {
    ! grep -q UNSECURE <<<"$1" &&
        [[ $(grep '^PROMPT:' <<<"$1" | grep -o ' SECURE ' | wc -l) -eq 1 ]]
}

# Succeeds if output $1 neither warns nor marks the prompt.
is_silent() {
    ! grep -q SECURE <<<"$1"
}

# No auth key is set, so the real tailscaled is never signed in.
check "warns when not signed in" warns "tailscale is not signed in" "$(guarded_zsh)"
check "is silent without TS_ENFORCE" is_silent "$(TS_ENFORCE=0 guarded_zsh)"

check "warns when tailscaled is unreachable" warns "tailscaled is not reachable" \
    "$(guarded_zsh_with_status '')"
check "warns without an exit node" warns "no exit node is in use" \
    "$(guarded_zsh_with_status '{"BackendState": "Running"}')"
check "warns when the exit node is offline" warns "the exit node is offline" \
    "$(guarded_zsh_with_status '{"BackendState": "Running", "ExitNodeStatus": {"Online": false}}')"
online='{"BackendState": "Running", "ExitNodeStatus": {"Online": true}}'
check "marks the prompt secure with an online exit node" is_secure \
    "$(guarded_zsh_with_status "$online")"
check "is silent with an online exit node and TS_SECURE_MARKER=0" is_silent \
    "$(TS_SECURE_MARKER=0 guarded_zsh_with_status "$online")"

reportResults
