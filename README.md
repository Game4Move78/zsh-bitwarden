# zsh-bitwarden
This plugin provides functions to manage a bitwarden session


## Installation

See [INSTALL.md](INSTALL.md).

## Usage

- Use `bwul` to unlock the vault, setting the env variable $BW_SESSION.
- Use `bwus SEARCH` to get a username.
- Use `bwpw SEARCH` to get a password.
- Use `bwse [OPTIONS]...` to search

## Examples

`bwus` and `bwpw` are both aliases for more verbose commands using `bwse`.
`bwse` searches over all items letting the user select one using `fzf`. Each
item has a set of fields some of which are set to be visible in `fzf`, and some
of these fields can be printed as output. If a single search result is found its
fields are printed without a call to `fzf`.

`bwus` expands to `bwse -c .name -o .login.username -c .notes -s `. Here `-c`,
`-o` and `-O` determine the columns that are displayed in `fzf` and those which
are tab separated and output by `bwse`. `-o` and `-O` are output columns and are
printed to stdout. `-o` will appear in the `fzf` finder while `-O` will be
hidden. `-c` is not returned in stdout and is only displayed in the `fzf`
finder.

If you wanted `bwpw` to display the item ids as well as the names you could
change the alias from
```
alias bwpw='bwse -c .name -c .login.username -O .login.password -c .notes -s '
```
to
```
alias bwpw='bwse -c .id -c .name -c .login.username -O .login.password -c .notes -s '
```
Or to output the item id as well as the password you could use
```
alias bwpw='bwse -o .id -c .name -c .login.username -O .login.password -c .notes -s '
```
This will return the item id and password in TSV format.
