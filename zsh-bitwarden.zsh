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
  if [ -z "$found_alias" ]; then
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
  # Comma-join arguments
  local width="$#"
  local keys="($1)? // null"
  for key in "${@:2}"; do
    keys="$keys, ($key)? // null"
  done

  # Construct tsv with values selected using args
  local jq_output=$(jq -e ".[] | [$keys] | select(all(.[]; . != null) and length == $width)" <<< "$json" 2> /dev/null | jq -r "@tsv")

  if [[ -z "$jq_output" ]]; then
    echo "Error: No results." >&2
    return 1
  fi

  # Output arguments as tsv header
  printf "%s" "$1"
  for arg in "${@:2}"; do
    printf "\t%s" "$arg"
  done
  printf "\n"

  printf "%s\n" "$jq_output"
}

# Takes tsv as stdin and columns to show in fzf as args
_bw_select() {
  if [[ "$#" == 0 ]]; then
    echo "Usage: $0 [COLUMN INDEX]..."
    return 1
  fi

  # Read input from stdin
  local tsv=$(</dev/stdin)

  # Validate that the input TSV is not empty
  if [[ -z "$tsv" ]]; then
    echo "Error: No input provided. Please provide a valid TSV input." >&2
    return 1
  fi

  # Join column indices with commas for the cut command
  local cols=$(IFS=, ; echo "$@")

  # Construct a formatted table with row indices
  local tbl=$(cut -d $'\t' -f "$cols" <<< $tsv | column -t -s $'\t' | nl -n rz)

  # Check if the table was generated correctly
  if [[ -z "$tbl" ]]; then
    echo "Error: Unable to generate table. Please check the column indices." >&2
    return 1
  fi

  local row=$(fzf -d $'\t' --with-nth 2 --select-1 --header-lines=1 <<< "$tbl"\
    | awk '{print $1}')

  if [[ "$?" -ne 0 || -z "$row" ]]; then
    echo "Couldn't return value from fzf. Is the header line missing?" >&2
    return 2
  fi

  # Output the corresponding row from the original tsv
  sed -n "${row}p" <<< "$tsv"
}

bw_search() {
  local columns=()
  local visible=()
  local out=()
  local o search colopts

  while getopts ":c:s::h" o; do
    case $o in
      h) # Help message
        cat <<EOF
Usage: $0 [options] JQPATHS

Constructs TSV from Bitwarden search items and allows selection with fzf if multiple are found.

Options:
  -c COLS    Each character in COL specifies an option for corresponding column:
               'c' = visible column, but not in the output.
               'o' = visible and output column.
               'O' = hidden but output column.
  -s SEARCH  Search string passed to 'bw list items --search'.
  -h         Display this help and exit.

Examples:
  $0 -c ccOo -s github .name .login.username .login.password .notes
  $0 -c co -s github .name .login.username | clipcopy
EOF
        return 0
        ;;
      s) # Search string
        search=$OPTARG
        ;;
      c) # Column options
        colopts=$OPTARG
        ;;
      *) # Invalid option
        echo "Invalid option: -$OPTARG" >&2
        return 1
        ;;
    esac
  done
  shift $(($OPTIND - 1))

  # Validate remaining arguments (JQ paths)
  if [ $# -lt 1 ]; then
    echo "Error: At least one JQ path must be provided." >&2
    return 1
  fi

  # Ensure the number of colopts matches the number of paths
  if [ ${#colopts} -ne $# ]; then
    echo "Error: The number of column options (${#colopts}) does not match the number of JQ paths ($#)." >&2
    return 1
  fi

  # Process the column options
  for ((i = 0; i < ${#colopts}; i++)); do
    local colopt="${colopts:$i:1}"
    case "$colopt" in
      c)
        visible+=($((i + 1)))  # Add column index to visible
        ;;
      o)
        visible+=($((i + 1)))
        out+=($((i + 1)))  # Visible and output
        ;;
      O)
        out+=($((i + 1)))  # Output only, not visible
        ;;
      *)
        echo "Error: Invalid column option '$colopt' at position $((i + 1))" >&2
        return 1
        ;;
    esac
  done

  # Ensure there are visible and output fields
  if [[ "${#visible}" == 0 ]]; then
      echo "No visible fields entered" >&2
    return 1
  fi
  if [[ "${#out}" == 0 ]]; then
    echo "No output fields entered" >&2
    return 2
  fi

  # Search using bitwarden
  local items=$(bw list items --search "$search" 2>/dev/null)

  if [ $? -ne 0 ] || [ -z "$items" ] || [ $(jq '. | length' <<< "$items") -eq 0 ]; then
    echo "No results found. Try '' to search all items." >&2
    return 4
  fi

  # Use _bw_table to create TSV, pipe it through _bw_select to fzf, then cut the output fields
  { _bw_table "$@" <<< "$items" \
    | _bw_select "${visible[@]}" \
    | cut -f$(IFS=, ; echo "${out[*]}") \
    | sed -z '$ s/\n$//' } 2>/dev/null

  local codes=("${pipestatus[@]}")

  for i in "${codes[@]}"; do
    if [[ $i -ne 0 ]]; then
      return $i
    fi
  done

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
  local userpass=$(bw_search -c coO -s "$1" .name .login.username .login.password)
  if [[ "$?" -ne 0 ]]; then
    return 2
  fi
  echo -n "Hit enter to copy username..."
  read _ && cut -f 1 <<< $userpass | clipcopy
  echo -n "Hit enter to copy password..."
  read _ && cut -f 2 <<< $userpass | clipcopy
}

bw_name() {
  bw_unlock && bw_search -c oc -s "$1" .name .login.username
}

bw_username() {
  bw_unlock && bw_search -c co -s "$1" .name .login.username
}

bw_password() {
  bw_unlock && bw_search -c ccO -s "$1" .name .login.username .login.password
}

bw_notes() {
  bw_unlock && bw_search -c co -s "$1" .name .notes
}

bw_field() {
  local fieldpath=".fields[]? | select(.name == \"$1\") | .value"

  bw_unlock && bw_search -c co -s "$2" .name "$fieldpath"
}

bw_edit_item() {
  local field
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
  local fnew=$(</dev/stdin)

  jq "$field=\"$fnew\"" <<< $item | bw encode | bw edit item $uuid > /dev/null
}

bw_edit_field() {
  if ! bw_unlock; then
    return 1
  fi
  local path_val=".fields[] | select(.name == \"$1\") | .value"
  local path_idx=".fields | map(.name) | index(\"$1\")"
  local uuid val idx res
  res=$(bw_search -c OcoO -s "$2" .id .name "$path_val" "$path_idx")
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find field $1 with search string $2"
    return 1
  fi
  IFS=$'\t' read -r uuid val idx <<< "$res"
  vared -p "Edit $1 > " val
  bw_edit_item -f ".fields[$idx].value" -i "$uuid" <<< "$val"
}

bw_edit_name() {
  if ! bw_unlock; then
    return 1
  fi
  local uuid val res
  res=$(bw_search -c Ooc -s "$1" .id .name .login.username)
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find items with search string $1"
    return 1
  fi
  IFS=$'\t' read -r uuid val <<< "$res"
  if [[ -t 0 ]]; then
    vared -p "Edit name > " val
  else
    val=$(</dev/stdin)
  fi
  bw_edit_item -f .name -i $uuid <<< "$val"
}

bw_edit_username() {
  if ! bw_unlock; then
    return 1
  fi
  local uuid val res
  res=$(bw_search -c Oco -s "$1" .id .name .login.username)
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find items with search string $1"
    return 1
  fi
  IFS=$'\t' read -r uuid val <<< "$res"
  if [[ -t 0 ]]; then
    vared -p "Edit username > " val
  else
    val=$(</dev/stdin)
  fi
  bw_edit_item -f .login.username -i $uuid <<< "$val"
}

bw_edit_password() {
  if ! bw_unlock; then
    return 1
  fi
  local uuid val res
  res=$(bw_search -c OccO -s "$1" .id .name .login.username .login.password)
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find items with search string $1"
    return 1
  fi
  IFS=$'\t' read -r uuid val <<< "$res"
  bw_edit_item -f .login.password -i $uuid
}

bw_edit_notes() {
  if ! bw_unlock; then
    return 1
  fi
  local uuid val res
  res=$(bw_search -c Oco -s "$1" .id .name .notes)
  IFS=$'\t' read -r uuid val <<< "$res"
  if [[ -t 0 ]]; then
    vared -p $'Edit note |\n-----------\n' val
  else
    val=$(</dev/stdin)
  fi
  bw_edit_item -f .notes -i $uuid <<< "$val"
}

bw_create_login() {
  if ! bw_unlock; then
    return 1
  fi
  local name username uuid
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
  local pass
  if [ -t 0 ] ; then
    pass="$(bwg)"
  else
    pass="$(</dev/stdin)"
  fi
  bw get template item \
    | jq ".name=\"${name}\" | .login={\"username\":\"${username}\", \"password\": \"$pass\"}" \
    | bw encode | bw create item | jq -r '.login.password'
}

bw_create_note() {
  if ! bw_unlock; then
    return 1
  fi
  local name val uuid
  if [[ "$#" -lt 1 ]]; then
    vared -p "Note item name > " name
  else
    name="$1"
  fi
  if [[ -t 0 ]]; then
    vared -p $'Enter note |\n-----------\n' val
  else
    val=$(</dev/stdin)
  fi
  uuid=$(bw get template item \
           | jq ".name=\"${name}\" | .notes=\"${val}\" | .type=2 | .secureNote.type = 0" \
           | bw encode | bw create item | jq -r '.id')
}

alias bwul='bw_unlock'
alias bwse='bw_unlock && bw_search'
alias bwn='bw_name'
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
alias bwg='bw generate -ulns --length 21'
alias bwgs='bw generate -uln --length 21'
alias bwlc='bw_create_login'
alias bwnc='bw_create_note'
