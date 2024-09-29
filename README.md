# zsh-bitwarden
This plugin provides functions to manage a [bitwarden](https://github.com/bitwarden/cli) session


## Installation

See [INSTALL.md](INSTALL.md).

## Usage

| Command    | Description                 |
|------------|-----------------------------|
| `bwul`     | unlock the vault            |
| `bwjs`     | print item json             |
| `bwjse`    | edit item json in $EDITOR   |
| `bwtsv -t` | print tsv table             |
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
bwtsv --simplify -s gmail -lc -c .name -c .username -o '.[] | .fields | length'
```

This command searches for "gmail" (`-s gmail`) and returns matching logins (`-l`). The use of `-c` along with argument `.name` causes the name of each item to be displayed in `fzf`. The use of `-o` along with `'.[] | .fields | length'` causes the number of fields to be displayed in `fzf` and also printed to output when selected. 

| Character | Visible in fzf | Printed to output |
|-----------|----------------|-------------------|
| c         | yes            | no                |
| o         | yes            | yes               |
| O         | no             | yes               |

```zsh
local fieldname="email"
local fieldpath=".fields[\"$fieldname\"][0]"
bwtsv --simplify -ls wikipedia -c .name -c .username -H "$fieldname" -o "$fieldpath"
```
By using the JQ path `$fieldpath` that selects the field named "email", this example lets you copy one of the emails associated with the search string `wikipedia`. Any item not containing this field will not be displayed.

```zsh
local fieldname="email"
local fieldpath=".fields[\"$fieldname\"] | select(length > 0) | join(\", \")"
bwtsv --simplify -pls wikipedia -c .name -c .username -H "$fieldname" -o "$fieldpath" | bw_tsv -h "$fieldname" -o '.'
```

Equivalent code but using piped bw_tsv to select from duplicates.

### TSV Table

```zsh
bwtsv --simplify -tls wikipedia .name .username -H 'num fields' '.fields | keys | length'
```

When using `-t`, instead of fzf selection, `bwtsv` displays all results in a TSV table.

### JQ search

```
bwtsv --simplify -o .password ---search-pass dog --search-user frog
```

This command finds items with both a username containing "frog" AND password containing "dog" and copies the password to clipboard.

```
bwtsv --simplify -o .password -j '(.password | test("dog")) or (.username | test("frog"))'
```

This command finds items with either a username containing "frog" OR password containing "dog" and copies the password to clipboard.

`--search-name`, `{--search-user, -u}`, `--search-pass`, `--search-note` apply a filter to search items using case insensitive regex. `{-j,--search-jq}` allows a custom filter.

`--simplify` restructuring the items for concise queries.
- `.login.username` becomes `.username` 
- `[.fields[] | select(.name == "email") | .value] | first` becomes `.fields.email[0]`

### Default header names

If you don't like the default header names displayed in fzf, then either edit `default-headers.csv` or export `BW_DEFAULT_HEADERS` to your file.

