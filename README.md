# Codespace feature for Tailscale connectivity

> This is the `fhibler` fork of
> [tailscale/codespace](https://github.com/tailscale/codespace). It adds
> `TS_EXIT_NODE` and the `TS_ENFORCE` shell guard described below. Fork
> releases carry a `-fhibler` version suffix.

This repository contains a feature for [GitHub Codespaces](https://github.com/features/codespaces)
to connect the running VM to a [Tailscale network](https://tailscale.com).

![Start a new codespace](codespace.jpg)

To get started, add the following [feature](https://docs.github.com/en/codespaces/setting-up-your-project-for-codespaces/adding-features-to-a-devcontainer-file)
to your `devcontainer.json`:

```json
"features": {
  "ghcr.io/fhibler/tailscale-codespace/tailscale": {
    "version": "latest"
  }
}
```

## Starting Tailscale

The Tailscale daemon starts automatically as part of the devcontainer entrypoint.

### Manual Log in

```shell
sudo tailscale up --accept-routes
```

More info: [`tailscale up`](https://tailscale.com/kb/1080/cli/#up)

### Automatic login

Create an [auth key](https://tailscale.com/kb/1085/auth-keys) in the Tailscale
[admin panel](https://login.tailscale.com/admin/settings/keys).

Create a codespace secret called `TS_AUTH_KEY` in your
[codespaces configuration](https://github.com/settings/codespaces) containing
the auth key you made above.

Now whenever you launch a devcontainer with access to this secret, it will
automatically perform a `tailscale up --accept-routes --auth-key=$TS_AUTH_KEY`.

## Environment variables

| Variable | Effect |
| --- | --- |
| `TS_AUTH_KEY` | Signs in automatically on start, see above. Removed from the environment before your shell starts. |
| `TS_EXIT_NODE` | Passed to `tailscale up --exit-node=`. Takes a node name or IP, or `auto:any` to let Tailscale choose. An `auto:` pick is retried for up to 120s, because tailscaled gives up on it when it has no home DERP yet. Needs `TS_AUTH_KEY`. |
| `TS_ENFORCE` | `1` turns on the zsh guard below. Anything else, or unset, leaves it off. |

Outside Codespaces, keep them in an untracked env file and pass it to the
container:

```jsonc
// devcontainer.json
"runArgs": ["--env-file", ".devcontainer/devcontainer.env"]
```

```shell
# .devcontainer/devcontainer.env (add it to .gitignore)
TS_ENFORCE=1
TS_AUTH_KEY=tskey-auth-...
TS_EXIT_NODE=auto:any
```

`containerEnv` works too for `TS_EXIT_NODE` and `TS_ENFORCE`, but would put
the auth key into `devcontainer.json`.

## Enforcing an exit node in zsh

With `TS_ENFORCE=1`, every interactive zsh checks that Tailscale is signed in
and routing through an online exit node. When it is not, the shell prints a
red `UNSECURE CONNECTION` banner with the reason at startup and prefixes the
prompt with `UNSECURE`. The check is repeated before every prompt, so the
marker appears and disappears as the connection changes.

The guard is installed to `/usr/local/share/tailscale/tailscale-guard.zsh` and
sourced from the system zshrc (`/etc/zsh/zshrc` or `/etc/zshrc`), so it works
with or without oh-my-zsh and survives any theme. The feature installs after
`common-utils` so that its zsh is present. A zsh installed by anything later
does not get the guard; source the file from your own `.zshrc` instead. The
guard needs `jq`, which the feature installs if it is missing.

It is a warning, not a kill switch: traffic still flows without an exit node.

## Details

- A mount is added called `tailscale-${devcontainerId}` mapped to
  `/var/lib/tailscale` to persist taislcaled state across devcontainer rebuilds,
  so a single devcontainer will remain logged in for the devcontainer lifetime.
- The feature requires `CAP_NET_ADMIN` in order to configure certain network
  properties for kernel mode tailscale.
- The feature requires kernel tun support in the runtime and `CAP_MKNOD` so that
  it can create a tun device node if needed.
- `CAP_NET_RAW` enables the feature to send ICMP.

## Development

A convenient way to develop this feature is to use codespaces, as they start by
default with many of the dependencies required (at least Docker and npx).

Inside a codespace you can use the `Tasks:Run Test Task` command.

On a standalone machine tests can be run with:

```shell
npx @devcontainers/cli features test
```