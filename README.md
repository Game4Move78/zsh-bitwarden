# zsh-bitwarden
This plugin provides functions to manage a [bitwarden](https://github.com/bitwarden/cli) session


## Installation

See [INSTALL.md](INSTALL.md).

## Usage

| Command                    | Description                                                    |
|----------------------------|----------------------------------------------------------------|
| `bwul`                     | to unlock the vault, setting the env variable $BW_SESSION.     |
| `bwg`                      | to generate a complex password (alphanumeric + special)        |
| `bwgs`                     | to generate a simple password (alphanumeric)                   |
| `bwus`                     | to get a username                                              |
| `bwuse`                    | to edit a username                                             |
| `bwpw`                     | to get a password                                              |
| `bwpwe`                    | to edit a password                                             |
| `bwfl`                     | to get a field                                                 |
| `bwfle`                    | to edit a field                                                |
| `bwfle -r`                 | to rename a field                                              |
| `bwfle -d`                 | to delete a field                                              |
| `bwfla`                    | to add a field                                                 |
| `bwno`                     | to get notes                                                   |
| `bwnoe`                    | to edit notes                                                  |
| `bwne`                     | to edit an item name                                           |
| `bwup`                     | to copy username then password to clipboard                    |
| `bwlc -n NAME -u USERNAME` | to create a login and save the generated password to clipboard |
| `bwnc -n NAME -u USERNAME` | to create a login and save the generated password to clipboard |
|----------------------------|----------------------------------------------------------------|

## Examples

```
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

## Notes

COLS    Each character in COL specifies an option for corresponding column:
- 'c' = visible column, but not in the output.
- 'o' = visible and output column.
- 'O' = hidden but output column.

`bwls` lists items as a JSON array. Pipe the output to `bwse` to return the values at JQ paths. If multiple items are present, the user is prompted to select one interactively using `fzf`. The first argument configures which columns are visible in `fzf` and which are printed in tsv output. The remaining arguments correspond to jq paths, which should be equal to the number of fields. If one row is present it is printed without interactive selection.

## bwse example

```
bwul && bwls gmail | bwse cco .name .login.username '.[] | .fields | length' 
```

`bwul` unlocks the vault. `bwls gmail` searches for "gmail" and returns matching items. With `bse` each character in the first argument (`coc`) corresponds to the subsequent arguments. The use of `c` the first two paths means the name and username of each item is displayed in `fzf`. The use of `o` causes the number of fields to be displayed in `fzf`, and be printed to output when selected.

|-----------|----------------|-------------------|
| Character | Visible in fzf | Printed to output |
|-----------|----------------|-------------------|
| c         | yes            | no                |
| o         | yes            | yes               |
| O         | no             | yes               |
|-----------|----------------|-------------------|

## Notes

If input is provided to `bwuse`, `bpwe` and `bwfle` it will use this to set the value.
