# Gopass

Fuzzy-search your [gopass](https://www.gopass.pw/) secrets from an Omarchy
overlay. TOTP accounts get their own section with live, refreshing codes.

## Install

```
omarchy plugin add https://github.com/dima-engineer/omarchy-gopass.git --enable
```

(Or, for local development: symlink this checkout into
`~/.config/omarchy/plugins/io.github.dima-engineer.gopass` and run
`omarchy-shell shell rescanPlugins`.)

Bind a key to open it, in `~/.config/hypr/bindings.conf`:

```
bindd = SUPER, p, Gopass, exec, omarchy-shell shell toggle io.github.dima-engineer.gopass
```

## Using it

With no filter, each tab shows the store as a directory tree, one folder at a
time — just like `gopass ls` — instead of one long flat list. Move the
selection onto a folder and press `Enter`/`→` to open it, or `←`/`Backspace`/
`Esc` to go back up. Start typing at any point to fall back to the flat,
whole-store fuzzy search this plugin always had (`wdbroot` matches
`work/dev/db/root`) — search always looks at the whole tab, regardless of
which folder you have open. Any entry whose leaf is literally named `totp`
(e.g. `work/github/alice/totp`) is treated as an OTP-only entry and lives in
the **TOTP** tab instead of **Secrets**.

| | |
|---|---|
| Type | Fuzzy-filter the whole current tab |
| `↑` `↓` | Move the selection |
| `→` / `Enter` on a folder | Open that folder |
| `←` / `Backspace` | Go up one folder (when not filtering) |
| `Tab` | Switch between Secrets and TOTP |
| `Enter` on an entry | Copy the password (or current TOTP code) and close |
| `Shift+Enter` | Type it into the window that was focused before, and close |
| `Esc` | Clear the filter, then go up a folder, then close |

A copied password clears itself from the clipboard after 45 seconds — but
only if the clipboard still holds exactly what was copied, so it never
clobbers something you copied afterward. TOTP codes aren't cleared since they
expire on their own every 30 seconds.

## What it needs

Everything here is either already part of a standard Omarchy install or a
dependency of `gopass` itself:

| | |
|---|---|
| `gopass` | Reads and decrypts the store; this plugin never touches GPG directly |
| `wl-clipboard` | `wl-copy`/`wl-paste`, for copying and for the delayed clipboard-clear check |
| `wtype` | Typing a password/code into the previously focused window (optional — only needed for `Shift+Enter`) |
| `libnotify` | `notify-send`, for the "copied" / error toasts |

If `gopass` needs your GPG passphrase, the overlay has already closed by the
time the pinentry prompt would appear — `copySecret`/`typeSecret` dismiss the
overlay before fetching the secret — so the prompt gets normal keyboard focus.

## How the TOTP section works

`gopass ls --flat` is cheap — it just walks the store's directory tree, no
decryption. This plugin uses that to build both tabs and to decide, purely
from the entry's path, which leaves belong in **TOTP** (leaf name exactly
`totp`, case-insensitive). Nothing is decrypted until you open the TOTP tab or
copy/type an entry.

Codes assume the standard 30-second period, since `gopass otp` doesn't expose
a per-entry period without decrypting it. An entry on a nonstandard period
still works — the displayed countdown just won't line up with its real
rollover.

## Security

This plugin runs unsandboxed, inside the long-running `omarchy-shell`
process, with your user's permissions — true of any Omarchy plugin, and worth
knowing for one that touches your password store.

- **A secret is never on a command line.** Only the entry's *path* is (not
  sensitive); the decrypted value crosses into `wl-copy`/`wtype` over stdin.
  `/proc/<pid>/cmdline` is readable by every process running as you.
- **Nothing decrypted is cached.** A password/TOTP-code value exists only for
  the instant between `gopass` exiting and being handed to `wl-copy`/`wtype`.
  The TOTP tab caches the *rotating code* it already fetched, never the
  shared secret, and only while the overlay is open — closing it drops the
  cache.
- **The clipboard auto-clear only ever compares**, never assumes: it rereads
  the clipboard via `wl-paste` before deciding to clear it.
- **Entry names are rendered as plain text**, never rich text, so a path
  cannot smuggle in markup.
- **No network access of any kind.** Whatever sync gopass itself is
  configured to do is between you and gopass; this plugin makes no
  connections.

## License

MIT — see [LICENSE](LICENSE).
