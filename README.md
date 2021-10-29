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
while `-O` will be hidden, but returned in stdout. `c` is not returend in stdout
and is used to identify items in `fzf`.


