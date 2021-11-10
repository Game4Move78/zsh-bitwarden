# zsh-bitwarden -- A Bitwarden CLI wrapper for Zsh
# https://github.com/Game4Move78/zsh-bitwarden

# Copyright (c) 2021 Patrick Lenihan

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Takes JSON as stdin and jq paths to extract into tsv as args
_bw_table() {
  if [[ "$#" -eq 0 ]]; then
    echo "Usage: $0 [PATH]..."
    return 1
  fi
  local json=$(</dev/stdin)
  # Comma-join arguments
  local keys=$(IFS=, ; echo "$*")
  # Output arguments as tsv header
  echo -n $1
  for arg in "${@:2}"
  do
    echo -en "\t"
    echo -n "$arg"
  done
  echo
  # Construct tsv with values selected using args
  jq -er ".[] | [$keys] | @tsv" <<< $json 2> -
  if [[ "$?" -ne 0 ]]; then
    echo "Unable to construct array [$keys]"
    return 1
  fi
}

# Takes tsv as stdin and columns to show in fzf as args
_bw_select() {
  if [[ "$#" -eq 0 ]]; then
    echo "Usage: $0 [COLUMN INDEX]..."
    return 1
  fi
  local tsv=$(</dev/stdin)
  local cols=$(IFS=, ; echo "$@")
  # Printable table with index field
  local tbl=$(echo $tsv | cut -d $'\t' -f "$cols" | column -t -s $'\t' | nl -n rz)
  local row=$(fzf -d $'\t' --with-nth 2 --select-1 --header-lines=1 <<< $tbl\
    | awk '{print $1}')
  if [[ "$?" -ne 0 ]]; then
    echo "Couldn't return value from fzf. Is the header line missing?" >&2
    return 2
  fi
  sed -n "${row}p" <<< $tsv
}

bw_search() {
  local columns=()
  local visible=()
  local out=()
  local o search colopts
  while getopts ":c:s:" o; do
    case $o in
      h) # Help message
        echo "Usage: $0 [options] JQPATHS"
        echo "Construct tsv of bitwarden search items results and select with"\
             "fzf if multiple\nare found."
        echo
        echo "-c COLS    Each character of COL specifies option for"\
             "corresponding column."
        echo "-s ID      Search string passed to bw --search [ID]"
        echo "-h         Display this help and exit"
        echo
        echo "Examples:"
        echo "  \$ $0 -c ccOc -s github .name .login.username .login.password .notes"\
             "\\ \n      | clipcopy"
        echo "  \$ $0 -c co -s github .name .login.username | clipcopy"
        return 0
        ;;
      s) # Search string
        search=$OPTARG
        ;;
      c) # Column options
        colopts=$OPTARG
        ;;
    esac
  done
  shift $(($OPTIND - 1))
  # Process remaining args
  if [ ${#colopts} -lt $# ]; then
    # Extend $colopts with defaults to have an option for each column
    local remaining=$(printf 'o%.0s' {${#colopts}..$(($# - 1))})
    colopts="$colopts$remaining"
  fi
  # Process the column options
  for (( i=1; i<=${#colopts}; i++)); do
    case "${colopts[i]}" in
      c)
        visible+=($i)
        ;;
      o)
        visible+=($i)
        out+=($i)
        ;;
      O)
        out+=($i)
        ;;
    esac
  done
  if [[ "${#visible}" -eq 0 ]]; then
      echo "No visible fields entered" >&2
    return 1
  fi
  if [[ "${#out}" -eq 0 ]]; then
    echo "No output fields entered" >&2
    return 2
  fi
  items=$(bw list items --search "$search")
  if [ $(jq '. | length' <<< $items) -eq 0 ]; then
    echo "No results. Try '-s .' to search through all items." >&2
    return 4
  fi
  _bw_table $@ <<< $items \
    | _bw_select ${visible[@]} \
    | cut -f$(IFS=, ; echo "${out[*]}")
}

bw_unlock() {
  if [ "$(bw status | jq -r '.status')" = "locked" ]; then
    if BW_SESSION=$(bw unlock --raw); then
      export BW_SESSION="$BW_SESSION"
    else
      return 1
    fi
  fi
}

bw_user_pass() {
  if ! bw_unlock; then
    return 1
  fi
  local userpass=$(bw_search -c coO -s "$*" .name .login.username .login.password)
  if [[ "$?" -ne 0 ]]; then
    return 2
  fi
  echo -n "Hit enter to copy username..."
  read _ && cut -f 1 <<< $userpass | clipcopy
  echo -n "Hit enter to copy password..."
  read _ && cut -f 2 <<< $userpass | clipcopy
}

bw_username() {
  bw_unlock && bw_search -c co -s "$*" .name .login.username
}

bw_password() {
  bw_unlock && bw_search -c ccO -s "$*" .name .login.username .login.password
}

bw_edit_item() {
  local uuid=$(</dev/stdin)
  local field
  local hidden=false
  while getopts ":f:h" o; do
    case $o in
      f)
        field=$OPTARG
        ;;
      h)
        hidden=true
        ;;
    esac
  done

  local item=$(bw get item $uuid)
  local fval=$(jq -r "$field" <<< $item)
  local fprompt="Enter new value for $field: "
  if [ "$hidden" = true ]; then
    IFS= read -rs "fval?$fprompt"
  else
    vared -p "$fprompt" -c fval
  fi
  jq "$field=\"$fval\"" <<< $item | bw encode | bw edit item $uuid > /dev/null
  echo "Field updated"
}


alias bwul='bw_unlock'
alias bwse='bw_unlock && bw_search'
alias bwus='bw_username'
alias bwpw='bw_password'
alias bwup='bw_user_pass'
