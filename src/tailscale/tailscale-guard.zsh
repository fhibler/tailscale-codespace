# Tailscale failsafe for interactive zsh sessions.
# With TS_ENFORCE=1, Tailscale must be signed in and routing through an online
# exit node. Otherwise the prompt is prefixed with UNSECURE and a warning is
# printed when the shell starts; when it is, the prompt is prefixed with SECURE
# unless TS_SECURE_MARKER=0. Re-checked before every prompt.
#
# install.sh copies this to /usr/local/share/tailscale/ and sources it from the
# system zshrc, so it loads before ~/.zshrc and any oh-my-zsh theme.

[[ -o interactive ]] || return 0
[[ "${TS_ENFORCE:-0}" == "1" ]] || return 0

# Prints the reason the connection is unsecure; prints nothing when it is fine.
_ts_guard_problem() {
    if ! command -v tailscale >/dev/null 2>&1; then
        print "tailscale is not installed"
        return
    fi
    if ! command -v jq >/dev/null 2>&1; then
        print "jq is not installed"
        return
    fi

    local json
    if ! json=$(timeout 3 tailscale status --json --peers=false 2>/dev/null) || [[ -z "$json" ]]; then
        print "tailscaled is not reachable"
        return
    fi

    jq -r '
        if .BackendState != "Running" then
            "tailscale is not signed in (state: \(.BackendState // "Unknown"))"
        elif .ExitNodeStatus == null then "no exit node is in use"
        elif .ExitNodeStatus.Online != true then "the exit node is offline"
        else empty end' <<<"$json" 2>/dev/null ||
        print "tailscale status is unreadable"
}

typeset -g _TS_GUARD_SECURE='%K{green}%F{black}%B SECURE %b%f%k '
[[ "${TS_SECURE_MARKER:-1}" == "0" ]] && _TS_GUARD_SECURE=''
typeset -g _TS_GUARD_PREFIX="%(9V.%K{red}%F{white}%B UNSECURE %b%f%k .$_TS_GUARD_SECURE)"

# Prepends the marker here rather than at load time: the system zshrc sources
# this file before ~/.zshrc and its theme, which then overwrite PROMPT. Strips
# any existing copy first, since VS Code's shell integration wraps PROMPT in its
# own markers and a plain prefix check would then add the marker a second time.
_ts_guard_precmd() {
    PROMPT="$_TS_GUARD_PREFIX${PROMPT//"$_TS_GUARD_PREFIX"/}"
    if [[ -n "$(_ts_guard_problem)" ]]; then
        psvar[9]=1
    else
        psvar[9]=()
    fi
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _ts_guard_precmd

() {
    local problem
    problem=$(_ts_guard_problem)
    [[ -n "$problem" ]] || return 0
    print -P "%K{red}%F{white}%B                                                            %b%f%k"
    print -P "%K{red}%F{white}%B  WARNING: UNSECURE CONNECTION (TS_ENFORCE=1)               %b%f%k"
    print -P "%K{red}%F{white}%B                                                            %b%f%k"
    print -P "%F{red}%B  Reason:%b%f $problem"
    print -P "%F{red}%B  Traffic is NOT routed through a Tailscale exit node.%b%f"
    print -r -- "  Fix: sudo tailscale up && sudo tailscale set --exit-node=${TS_EXIT_NODE:-<node>}"
    print
}
