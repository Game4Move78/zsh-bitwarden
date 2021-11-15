# zsh-bitwarden
This plugin provides functions to manage a [bitwarden](https://github.com/bitwarden/cli) session


## Installation

See [INSTALL.md](INSTALL.md).

## Usage

- Use `bwul` to unlock the vault, setting the env variable $BW_SESSION.
- Use `bwus SEARCH` to get a username
- Use `bwuse SEARCH` to edit a username
- Use `bwpw SEARCH` to get a password
- Use `bwpwe SEARCH` to edit a password
- Use `bwfl SEARCH FLDNAME` to get a field 
- Use `bwfle SEARCH FLDNAME` to edit a field 
- Use `bwno SEARCH` to get notes
- Use `bwnoe SEARCH` to edit notes
- Use `bwne SEARCH` to edit an item name
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

While `bwuse` and `bwne` accept interactive input using `vared`, `bwpwe` must
have the password provided in standard input. An example of this would be `bwg
-ulns --length 20 | bwpwe SEARCH` which will generate a new random password for
`SEARCH` and output the old password. Use of `bwg` is described in the [bw-cli
manual](https://bitwarden.com/help/article/cli/#generate).

For fun if `sshd` is running in Termux, then to store the latest SMS DUOSEC codes in `bw`
```
bw-new-codes() {
  local codes=$(ssh $DEVICE_IP -p 8022 "termux-sms-list | jq -r '.[]"\
                    "| select(.number==\"DUOSEC\") | .body' | cut -d' ' -f3- "\
                    "| tail -1")
  bwnoe DUOSEC <<< "$codes"
}

bw-pop-duocode() {
  bwno DUOSEC | awk '{$1=""; print $0}' | bwnoe DUOSEC | awk '{print $1}'
}

bw-duocode() {
  local code=$(bw-pop-duocode)
  echo $code
  if grep '^\W*5' <<< $code; then
    echo -n "Last duosec code. Loading new codes in... "
    sleep 1
    echo -n "1... "
    sleep 1
    echo -n "2... "
    sleep 1
    echo -n "3 "
    bw-new-codes
  fi
}
```
