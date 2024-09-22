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
bwlc -n mylogin -u user123@example.com | clipcopy'
# rename to mynewlogin
echo mynewlogin | bwne -s mylogin
# get username and password
bwup -s mynewlogin
# add field
echo myvalue | bwfla -s mynewlogin -f myfield
# copy field
bwfl -s mynewlogin -f myfield | clipcopy
# rename field to `newvalue`
echo newvalue | bwfle -s mynewlogin -f myfield -r
```

### Search

```zsh
bwtsv -lrc cco .name .login.username '.[] | .fields | length' | clipcopy
```

This command searches for "gmail" (`-s gmail`) and returns matching logins (`-l`). When using `bwtsv` each character in option `-c` (`cco`) corresponds to the arguments. The use of `cc` along with first two arguments `.name` and `.login.username` causes the name and username of each item to be displayed in `fzf`. The use of `o` along with `'.[] | .fields | length'` causes the number of fields to be displayed in `fzf`, and be printed to output when selected. If `-c` is omitted all are printed.

| Character | Visible in fzf | Printed to output |
|-----------|----------------|-------------------|
| c         | yes            | no                |
| o         | yes            | yes               |
| O         | no             | yes               |

```zsh
local fieldname="email"
local fieldpath="[.fields[] | select(.name == \"$fieldname\") | .value] | first"
bwtsv -lrs wikipedia -c cco .name .name .login.username "$fieldpath" | clipcopy
```

By using the JQ path `$fieldpath` that selects the field named "email", this example lets you copy one of the emails associated with the search string `wikipedia`. Any item not containing this field will not be displayed.

```zsh
local fieldname="email"
local fieldpath=".fields.value | select(.name == \"$fieldname\") | .value"
bwtsv -flrs wikipedia -c cco .name .name .login.username "$fieldpath" | clipcopy
```

Equivalent code but using group by field (`-f`) rather than selecting the first matching (in case of duplicates)

### TSV Table

```zsh
local fieldname="email"
local fieldpath=".fields.value | select(.name == \"$fieldname\") | .value"
bwtsv -ls wikipedia .name .name .login.username '.[] | .fields | length' | clipcopy
```

When omitting `-r` instead of fzf selection, `bwtsv` displays all results in a TSV table.

## Notes

If input is provided to `bwuse`, `bpwe` and `bwfle` it will use this to set the value.
