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

_bw_get_alias() {
  local found_alias=$(alias | grep -E "=\W*$1\W*$" | cut -d'=' -f1)
  if [ -z $found_alias ]; then
    echo "$1"
  else
    echo "$found_alias"
  fi
}

_bw_test_subshell() {
  local pid=$(exec sh -c 'echo $PPID')
  if [[ "$$" == "$pid" ]]; then
    return 0
  else
    return 1
  fi
}

# Takes JSON as stdin and jq paths to extract into tsv as args
_bw_table() {
  if [[ "$#" == 0 ]]; then
    echo "Usage: $0 [PATH]..."
    return 1
  fi
  local json=$(</dev/stdin)
  # Output arguments as tsv header
  echo -n $1
  for arg in "${@:2}"
  do
    echo -en "\t"
    echo -n "$arg"
  done
  echo
  local width="$#"
  # Comma-join arguments
  keys="($1)"
  shift 1
  for key in "$@"; do
    keys="$keys,($key)"
  done
  # Construct tsv with values selected using args
  (jq -e ".[] | [$keys] | select( length == $width)" | jq -r "@tsv") <<< $json 2> /dev/null
  if [[ "$?" -ne 0 ]]; then
    echo "Unable to construct array [$keys]"
    return 1
  fi
}

# Takes tsv as stdin and columns to show in fzf as args
_bw_select() {
  if [[ "$#" == 0 ]]; then
    echo "Usage: $0 [COLUMN INDEX]..."
    return 1
  fi
  local tsv=$(</dev/stdin)
  local cols=$(IFS=, ; echo "$@")
  # Printable table with index field
  local tbl=$(cut -d $'\t' -f "$cols" <<< $tsv | column -t -s $'\t' | nl -n rz)
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
  if [[ "${#visible}" == 0 ]]; then
      echo "No visible fields entered" >&2
    return 1
  fi
  if [[ "${#out}" == 0 ]]; then
    echo "No output fields entered" >&2
    return 2
  fi
  items=$(bw list items --search "$search")
  if [[ $(jq '. | length' <<< $items) == 0 ]]; then
    echo "No results. Try '-s .' to search through all items." >&2
    return 4
  fi
  _bw_table $@ <<< $items \
    | _bw_select ${visible[@]} \
    | cut -f$(IFS=, ; echo "${out[*]}") \
    | sed -z '$ s/\n$//'
}

bw_unlock() {
  #TODO Substitute obscure "mac failed" message with "please sync vault"
  if [ -z $BW_SESSION ] || [ "$(bw status | jq -r '.status')" = "locked" ]; then
    if ! _bw_test_subshell; then
      local bwul_alias=$(_bw_get_alias bw_unlock)
      echo "Can't export session key in forked process. Try \`$bwul_alias\` before piping." >&2
      return 1
    fi
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

bw_notes() {
  # The only way I knew how to convert escaped sequences to literals
  bw_unlock && echo "$(bw_search -c co -s "$*" .name .notes)"
}

bw_field() {
  local fieldpath=".fields[]? | select(.name == \"$2\") | .value"
  bw_unlock && bw_search -c co -s "$1" .name "$fieldpath"
}

bw_edit_item() {
  local field
  local hidden=false
  while getopts ":f:i:" o; do
    case $o in
      i)
        uuid=$OPTARG
        ;;
      f)
        field=$OPTARG
        ;;
    esac
  done

  local item=$(bw get item $uuid)
  local fnew=$(cat)
  jq "$field=\"$fnew\"" <<< $item | bw encode | bw edit item $uuid > /dev/null
}

bw_edit_field() {
  if ! bw_unlock; then
    return 1
  fi
  local fieldpath=".fields[]? | select(.name == \"$2\") | .value"
  local uuid=$(bw_search -c Occ -s "$1" .id .name "$fieldpath")
  local item=$(bw get item $uuid)
  local fval=$(jq -r "$fieldpath" <<< $item)
  local fvalindex=$(jq -r '.fields | map(.name == "Email") | index(true)' <<< $item)
  local fvalabspath=".fields[$fvalindex].value"
  vared -p "Edit $2 > " fval
  bw_edit_item -f "$fvalabspath" -i $uuid <<< $fval
}

bw_edit_name() {
  if ! bw_unlock; then
    return 1
  fi
  local uuid=$(bw_search -c Occ -s "$*" .id .name .login.username)
  local fval=$(bw get item $uuid | jq -r '.name')
  vared -p "Edit name > " fval
  bw_edit_item -f .name -i $uuid <<< $fval
}

bw_edit_username() {
  if ! bw_unlock; then
    return 1
  fi
  local uuid=$(bw_search -c Occ -s "$*" .id .name .login.username)
  local fval=$(bw get item $uuid | jq -r '.login.username')
  vared -p "Edit username > " fval
  bw_edit_item -f .login.username -i $uuid <<< $fval
}

bw_edit_password() {
  if ! bw_unlock; then
    return 1
  fi
  local uuid=$(bw_search -c Occ -s "$*" .id .name .login.username)
  local fval=$(bw get item $uuid | jq -r '.login.password')
  bw_edit_item -f .login.password -i $uuid
  echo $fval
}

bw_edit_notes() {
  if ! bw_unlock; then
    return 1
  fi
  local uuid=$(bw_search -c Occ -s "$*" .id .name .notes)
  local fval=$(bw get item $uuid | jq -r '.notes')
  bw_edit_item -f .notes -i $uuid
  echo $fval
}

bw_create_login() {
  if ! bw_unlock; then
    return 1
  fi
  local name username password
  if [[ "$#" -lt 1 ]]; then
    vared -p "Login item name > " name
  else
    name="$1"
  fi
  if [[ "$#" -lt 2 ]]; then
    vared -p "Login item username > " username
  else
    username="$2"
  fi
  uuid=$(bw get template item \
  | jq ".name=\"${name}\" | .login={\"username\":\"${username}\"}" \
  | bw encode | bw create item | jq -r '.id')
  if [ -t 0 ] ; then
    { bwg | bwpwe $uuid > /dev/null; }
    echo "Created item $uuid. To change password use"
    echo "bwpwe $uuid"
  else
    { bwpwe $uuid > /dev/null; }
  fi
}

bw_create_note() {
  if ! bw_unlock; then
    return 1
  fi
  local name
  if [[ "$#" -lt 1 ]]; then
    vared -p "Note item name > " name
  else
    name="$1"
  fi
  uuid=$(bw get template item \
           | jq ".name=\"${name}\"" \
           | bw encode | bw create item | jq -r '.id')
}

alias bwul='bw_unlock'
alias bwse='bw_unlock && bw_search'
alias bwus='bw_username'
alias bwpw='bw_password'
alias bwno='bw_notes'
alias bwfl='bw_field'
alias bwup='bw_user_pass'
alias bwne='bw_edit_name'
alias bwuse='bw_edit_username'
alias bwpwe='bw_edit_password'
alias bwnoe='bw_edit_notes'
alias bwfle='bw_edit_field'
alias bwg='bw generate -ulns --length 20'
alias bwgs='bw generate -uln --length 20'
alias bwlc='bw_create_login'
alias bwln='bw_create_note'
