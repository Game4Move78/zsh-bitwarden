# zsh-bitwarden
This plugin provides functions to manage a bitwarden session


## Installation

See [INSTALL.md](INSTALL.md).

## Usage

- Use `bwul` to unlock the vault, setting the env variable $BW_SESSION.
- Use `bwus [ITEM]` to get a username.
- Use `bwpw [ITEM]` to get a password.
- Use `bwse -s [SEARCH] -o [OUTPUT COL] ...` to search

## Examples

`bwus` and `bwpw` are both aliases for more verbose commands using `bwse`.
`bwse` is a more powerful command which can be used to search over all items
letting the user select from choices using `fzf`. Each item has a set of columns
some of which are set to be visible in `fzf`, and some of these columns can be
returned on output. If a single column is returned it can be piped to `clipcopy`
for entering fields.

`bwus` expands to `bwse -c .name -o .login.username -c .notes -s `. Here `-c`,
`-o` and `-O` determine the columns that are displayed in and returned by `fzf`.
`-o` and `-O` are output columns, but only `-o` will appear in the `fzf` finder
while `-O` will be hidden, but returned in stdout. `-c` is not returned in stdout
and is simply displayed in the `fzf` finder.

If you wanted `bwpw` to display the item ids as well as the names you could
change the alias from
```
alias bwpw='bwse -c .name -c .login.username -O .login.password -c .notes -s '
```
to
```
alias bwpw='bwse -c .id -c .name -c .login.username -O .login.password -c .notes -s '
```
Or to output the id as well as the password you could use
```
alias bwpw='bwse -o .id -c .name -c .login.username -O .login.password -c .notes -s '
```
This will return the item id and password in TSV format.
