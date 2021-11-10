# zsh-bitwarden
This plugin provides functions to manage a bitwarden session
This plugin provides functions to manage a [bitwarden](https://github.com/bitwarden/cli) session


## Installation

See [INSTALL.md](INSTALL.md).

## Usage

- Use `bwul` to unlock the vault, setting the env variable $BW_SESSION.
- Use `bwus SEARCH` to get a username
- Use `bwuse SEARCH` to edit a username
- Use `bwpw SEARCH` to get a password
- Use `bwpwe SEARCH` to edit a password
- Use `bwup SEARCH` to copy username then password to clipboard
- Use `bwse [OPTIONS]... JPATHS` to search

## Examples

`bwus` and `bwpw` both delegate to `bwse`. `bwse` searches over all items
letting the user select one using `fzf`. Each item has a set of fields some of
which are set to be visible in `fzf`, and some of these fields can be printed as
output. If a single search result is found its fields are output without
interactive selection.

`bwus` executes `bwse -c coc -s ARGS .name .login.username .notes `. Here `-c
COLS` determines columns that are displayed in `fzf` and those which are tab
separated and included in output. `o` and `O` are output columns and are printed
to stdout. `o` will appear in the `fzf` finder while `O` will be hidden. `c` is
not returned in stdout and is only displayed in the `fzf` finder.

If you wanted `bwpw` to display the item ids as well as the names you could
define the function

```
bwpw() {
  bw_unlock && bw_search -c cccOc -s "$*"\
  .id .name .login.username .login.password .notes
}
```

Or to output the item id as well as the password you could use
```
bwpw() {
  bw_unlock && bw_search -c occOc -s "$*"\
  .id .name .login.username .login.password .notes
}
```
This will return the item id and password in TSV format.

