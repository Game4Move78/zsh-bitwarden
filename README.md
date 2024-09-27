# zsh-bitwarden
This plugin provides functions to manage a [bitwarden](https://github.com/bitwarden/cli) session


## Installation

See [INSTALL.md](INSTALL.md).

## Usage

| Command    | Description                 |
|------------|-----------------------------|
| `bwul`     | unlock the vault            |
| `bwtsv`    | select tsv data             |
| `bwtsv -t` | print tsv table             |
| `bwg`      | alphanum + special password |
| `bwgs`     | alphanum password           |
| `bwus`     | get username                |
| `bwuse`    | edit username               |
| `bwpw`     | get password                |
| `bwpwe`    | edit password               |
| `bwfl`     | get field                   |
| `bwfle`    | edit field                  |
| `bwfle -r` | rename field                |
| `bwfle -d` | delete field                |
| `bwfla`    | add field                   |
| `bwno`     | get note                    |
| `bwnoe`    | edit note                   |
| `bwne`     | edit item name              |
| `bwup`     | copy username then password |
| `bwlc`     | create login                |
| `bwnc`     | create note                 |

## Examples

```zsh
# create entry called `mylogin` with username `user123@example.com` and copy secure password to clipboard
bwlc -n mylogin -u user123@example.com
# rename to mynewlogin
echo mynewlogin | bwne -s mylogin
# get username and password
bwup -s mynewlogin
# add field
echo myvalue | bwfla -s mynewlogin -f myfield
# copy field
bwfl -s mynewlogin -f myfield
# rename field to `newvalue`
echo newvalue | bwfle -s mynewlogin -f myfield -r
```

### Search

```zsh
bwtsv -s gmail -lrc -c .name -c .login.username -o '.[] | .fields | length'
```

This command searches for "gmail" (`-s gmail`) and returns matching logins (`-l`). The use of `-c` along with argument `.name` causes the name of each item to be displayed in `fzf`. The use of `-o` along with `'.[] | .fields | length'` causes the number of fields to be displayed in `fzf` and also printed to output when selected. 

| Character | Visible in fzf | Printed to output |
|-----------|----------------|-------------------|
| c         | yes            | no                |
| o         | yes            | yes               |
| O         | no             | yes               |

```zsh
local fieldname="email"
local fieldpath="[.fields[] | select(.name == \"$fieldname\") | .value] | first"
bwtsv -lrs wikipedia -c .name -c .login.username -o "$fieldpath"
```

By using the JQ path `$fieldpath` that selects the field named "email", this example lets you copy one of the emails associated with the search string `wikipedia`. Any item not containing this field will not be displayed.

```zsh
local fieldname="email"
local fieldpath=".fields.value | select(.name == \"$fieldname\") | .value"
bwtsv -flrs wikipedia -c .name -c .login.username -o "$fieldpath"
```

Equivalent code but using group by field (`-f`) rather than selecting the first matching (in case of duplicates)

### TSV Table

```zsh
local fieldname="email"
local fieldpath=".fields.value | select(.name == \"$fieldname\") | .value"
bwtsv -ls wikipedia -c .name -c .login.username -o '.[] | .fields | length'
```

When omitting `-r` instead of fzf selection, `bwtsv` displays all results in a TSV table.

## GPG caching

Since Bitwarden CLI can have slow startup times, GPG can be used to cache the encrypted results in memory and decrypt when needed.

```
bw_enable_cache
```

When this command is in the zshrc file, it will set the `ZSH_BW_CACHE*` environmental variables. When these variables are set `gpg --encrypt --default-recipient-self` will encrypt the vault and store it in memory. Alternatively set them yourself. E.g.

```
export ZSH_BW_CACHE="/run/user/$UID/zsh-bitwarden"
export ZSH_BW_CACHE_LIST="$ZSH_BW_CACHE/bw-list-cache.gpg"
export ZSH_BW_CACHE_SESSION="$ZSH_BW_CACHE/bw-session.gpg"
mkdir -p "$ZSH_BW_CACHE"
chmod 700 "$ZSH_BW_CACHE"
```
