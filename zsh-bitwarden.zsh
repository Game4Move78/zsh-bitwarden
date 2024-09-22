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
bw_table() {
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
  local jq_output=$(jq -ceM ".[] | [$keys] | select(all(.[]; . != null) and length == $width)" <<< "$json" 2> /dev/null | jq -r "@tsv")

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

  local row=$(fzf -d $'\t' --with-nth=2 --select-1 --header-lines=1 <<< "$tbl"\
    | awk '{print $1}')

  if [[ "$?" -ne 0 || -z "$row" ]]; then
    echo "Couldn't return value from fzf. Is the header line missing?" >&2
    return 2
  fi

  # Output the corresponding row from the original tsv
  sed -n "${row}p" <<< "$tsv"
}

bw_search() {
  local -a carg
  zparseopts -D -F -K -- \
             {c,-columns}:=carg || return

  local colopts=""

  if (( $#carg )); then
    colopts="${carg[-1]}"
  else
    for ((i=0; i < $#; i++)); do
      colopts="${colopts}o"
    done
  fi

  local columns=()
  local visible=()
  local out=()
  local o search

  # local colopts=$1
  # local -a jqpaths=("${@:2}")
  local -a jqpaths=("$@")

  # Validate remaining arguments (JQ paths)
  if [ $# -lt 1 ]; then
    echo "Error: At least one JQ path must be provided." >&2
    return 1
  fi

  # Ensure the number of colopts matches the number of paths
  if [ ${#colopts} -ne $# ]; then
    echo "Error: The number of column options (${#colopts}) does not match the number of JQ paths ($# - 1)." >&2
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
  local items=$(</dev/stdin)

  if [ $? -ne 0 ] || [ -z "$items" ] || [ $(jq '. | length' <<< "$items") -eq 0 ]; then
    echo "No results found. Try '' to search all items." >&2
    return 4
  fi

  local tsv=$(bw_table "${jqpaths[@]}" <<< "$items")

  if [ $? -ne 0 ]; then
    echo "Failed to construct tsv" >&2
    return 4
  fi

  local row=$(_bw_select "${visible[@]}" <<< "$tsv")

  if [ $? -ne 0 ]; then
    echo "Failed to select row" >&2
    return 4
  fi

  local comma_out=$(IFS=, ; echo "${out[*]}")

  cut -f"$comma_out" <<< "$row" | sed -z '$ s/\n$//'

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

bw_list() {
  local -a sarg larg narg farg
  zparseopts -D -F -K -- \
             {s,-search}:=sarg \
             {f,-fields}=farg \
             {l,-login}=larg \
             {n,-note}=narg || return
  local items=$(bw list items --search "${sarg[-1]}")
  if (( $#larg || $#narg)); then
    local item_type
    if (( $#larg)); then
      item_type=1
    elif (( $#narg )); then
      item_type=2
    fi
    items=$(jq -ceM "[.[] | select(.type == $item_type)]" <<< "$items")
  fi
  if (( $#farg)); then
    items=$(bw_group_fields <<< "$items")
  fi
  # Command substitution removes newline
  printf "%s\n" "$items"
}

bw_copy() {
  clipcopy
}

bw_tsv() {
  local -a pedit parg carg sarg rarg farg larg narg bw_list_args
  zparseopts -D -F -K -- \
             {e,-e}=pedit \
             {p,-clipboard}=parg \
             {c,-columns}:=carg \
             {s,-search}:=sarg \
             {r,-row}=rarg \
             {f,-fields}=farg \
             {l,-login}=larg \
             {n,-note}=narg || return
  if [[ "$#" == 0 ]]; then
    echo "Usage: $0 [PATH]..."
    return 1
  fi
  if ! bw_unlock; then
    return 1
  fi
  (( $#sarg)) && bw_list_args+=("-s" "${sarg[-1]}")
  (( $#farg)) && bw_list_args+=("-f")
  (( $#larg)) && bw_list_args+=("-l")
  (( $#narg)) && bw_list_args+=("-n")
  local res
  if (( $#rarg )); then
    local -a bw_search_args
    (( $#carg)) && bw_search_args+=("-c" "${carg[-1]}")
    #TODO: fill out repeated `o` when $1 is different
    IFS='' res=$(bw_list "${bw_list_args[@]}" | bw_search "${bw_search_args[@]}" "$@")
  else
    IFS='' res=$(bw_list "${bw_list_args[@]}" | bw_table $@)
  fi
  if (( $#parg )); then
    bw_copy <<< "$res"
  else
    printf "%s" "$res"
  fi
}

bw_user_pass() {
  local -a sarg
  zparseopts -D -F -K -- \
             {s,-search}:=sarg || return
  if ! bw_unlock; then
    return 1
  fi
  local userpass=$(bw_list -l -s "${sarg[-1]}" | bw_search -c coO .name .login.username .login.password)
  if [[ "$?" -ne 0 ]]; then
    return 2
  fi
  echo -n "Hit enter to copy username..."
  read _ && cut -f 1 <<< $userpass | clipcopy
  echo -n "Hit enter to copy password..."
  read _ && cut -f 2 <<< $userpass | clipcopy
}

bw_name() {
  local -a sarg
  zparseopts -D -F -K -- \
             {s,-search}:=sarg || return
  bw_unlock && bw_list -s "${sarg[-1]}" | bw_search -c oc .name .login.username
}

bw_username() {
  local -a sarg
  zparseopts -D -F -K -- \
             {s,-search}:=sarg || return
  bw_unlock && bw_list -l -s "${sarg[-1]}" | bw_search -c co .name .login.username
}

bw_password() {
  local -a sarg
  zparseopts -D -F -K -- \
             {s,-search}:=sarg || return
  bw_unlock && bw_list -l -s "${sarg[-1]}" | bw_search -c ccO .name .login.username .login.password
}

bw_note() {
  local -a sarg
  zparseopts -D -F -K -- \
             {s,-search}:=sarg || return
  bw_unlock && bw_list -n -s "${sarg[-1]}" | bw_search -c co .name .notes
}

bw_select_values() {
  jq -rceM "[.[] | $1] | unique | .[]" \
    | fzf --header="$2" --print-query \
    | awk 'NR == 1 && $0 != "" { print $0; exit } NR == 2 { print $0; exit }'
}

bw_select_field() {
  bw_select_values '.fields[]?.name?' "field"
}

bw_group_fields() {
  jq -ceM '[.[] | . as $item | .fields? | to_entries? | .[] as $field | $item | .fields=$field]'
}

bw_field() {

  local -a sarg farg
  zparseopts -D -F -K -- \
             {s,-search}:=sarg \
             {f,-field}:=farg || return

  if ! bw_unlock; then
    return 1
  fi

  local items=$(bw_list -s "${sarg[-1]}" | bw_group_fields)

  local name
  if (( $#farg)); then
    name="${farg[-1]}"
  else
    name=$(bw_select_field <<< "$items")
  fi

  #local fieldpath="[.fields[] | select(.name == \"$name\") | .value] | first"
  local fieldpath=".fields.value | select(.name == \"$name\") | .value"

  bw_search -c co .name "$fieldpath" <<< "$items"
}

bw_get_item() {
  jq -ceM ".[] | select(.id == \"$1\")"
}

bw_edit_item() {
  jq -ceM "$2" | bw encode | bw edit item "$1" > /dev/null
}

bw_edit_item_assign() {

  bw_edit_item "$1" "$2 = \"$3\""

}

bw_edit_item_append() {

  bw_edit_item "$1" "$2 += [$3]"

}

bw_edit_field() {

  local -a sarg farg rarg darg
  zparseopts -D -F -K -- \
             {n,-new}=narg \
             {r,-rename}=rarg \
             {d,-delete}=darg \
             {s,-search}:=sarg \
             {f,-field}:=farg || return

  if ! bw_unlock; then
    return 1
  fi
  local items=$(bw_list -s "${sarg[-1]}")
  local grp_items=$(bw_group_fields <<< "$items")
  local name
  if (( $#farg)); then
    name="${farg[-1]}"
  else
    name=$(bw_select_field <<< "$items")
  fi
  #local path_val="[.fields[] | select(.name == \"$name\") | .value] | first"
  #local path_idx=".fields | map(.name) | index(\"$name\")"
  local path_val=".fields.value | select(.name == \"$name\") | .value"
  local path_idx=".fields.key"
  local uuid val idx res
  res=$(bw_search -c OcoO .id .name "$path_val" "$path_idx" <<< "$grp_items")
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find field $name with search string ${sarg[-1]}"
    return 1
  fi
  IFS=$'\t' read -r uuid val idx <<< "$res"
  if (( $#darg)); then
    bw_get_item "$uuid" <<< "$items" | bw_edit_item "$uuid" "del(.fields[$idx])"
    return
  fi
  if [[ -t 0 ]]; then
    if (( $#rarg)); then
      vared -p "Edit $name > " name
    else
      vared -p "Edit $name > " val
    fi
  else
    val=$(</dev/stdin)
  fi
  bw_get_item "$uuid" <<< "$items" | bw_edit_item "$uuid" ".fields[$idx].name=\"$name\" | .fields[$idx].value=\"$val\""
}

bw_add_field() {

  local -a sarg farg
  zparseopts -D -F -K -- \
             {s,-search}:=sarg \
             {f,-field}:=farg || return
  if ! bw_unlock; then
    return 1
  fi
  local items=$(bw_list -s "${sarg[-1]}")
  local name val
  if (( $#farg)); then
    name="${farg[-1]}"
  else
    name=$(bw_select_field <<< "$items")
  fi
  local path_val="[(.fields[] | select(.name == \"$name\") | .value) // \"\"] | first"
  local res=$(bw_search -c Oco .id .name "$path_val" <<< "$items")
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find items with search string ${sarg[-1]}"
    return 1
  fi
  IFS=$'\t' read -r uuid val <<< "$res"
  if [[ -t 0 ]]; then
    vared -p "Field value > " val
  else
    val=$(</dev/stdin)
  fi
  local field_json="{\"name\": \"$name\", \"value\": \"$val\"}"
  bw_get_item "$uuid" <<< "$items" | bw_edit_item_append "$uuid" ".fields" "$field_json"
}

bw_edit_name() {
  local -a sarg
  zparseopts -D -F -K -- \
             {s,-search}:=sarg || return
  if ! bw_unlock; then
    return 1
  fi
  local items=$(bw_list -s "${sarg[-1]}")
  local uuid val res
  res=$(bw_search -c Ooc .id .name .login.username <<< "$items")
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find items with search string ${sarg[-1]}"
    return 1
  fi
  IFS=$'\t' read -r uuid val <<< "$res"
  if [[ -t 0 ]]; then
    vared -p "Edit name > " val
  else
    val=$(</dev/stdin)
  fi
  bw_edit_item_assign "$uuid" ".name" "$val"
}

bw_filter_type() {
  local -a larg narg
  zparseopts -D -F -K -- \
             {l,-login}=larg \
             {n,-note}=narg || return
  local item_type
  if (( $#larg)); then
    item_type=1
  elif (( $#narg )); then
    item_type=2
  else
    return 1
  fi
  jq -ceM "[.[] | select(.type == $item_type)]"
}

bw_edit_username() {
  zparseopts -D -F -K -- \
             {s,-search}:=sarg || return
  if ! bw_unlock; then
    return 1
  fi
  local items=$(bw_list -l -s "${sarg[-1]}")
  local uuid val res
  res=$(bw_search -c Oco .id .name .login.username <<< "$items")
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
  bw_edit_item_assign "$uuid" .login.username "$val"
}

bw_edit_password() {
  local -a sarg
  zparseopts -D -F -K -- \
             {s,-search}:=sarg || return
  if ! bw_unlock; then
    return 1
  fi
  local items=$(bw_list -l -s "${sarg[-1]}")
  local uuid val res
  res=$(bw_search -c OccO .id .name .login.username .login.password <<< "$items")
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find items with search string $1"
    return 1
  fi
  IFS=$'\t' read -r uuid val <<< "$res"
  if [[ -t 0 ]]; then
    vared -p "Edit password > " val
  else
    val=$(</dev/stdin)
  fi
  bw_edit_item_assign "$uuid" .login.password "$val"
}

bw_edit_note() {
  local -a sarg
  zparseopts -D -F -K -- \
             {s,-search}:=sarg || return
  if ! bw_unlock; then
    return 1
  fi
  local items=$(bw_list -n -s "${sarg[-1]}")
  local uuid val res
  res=$(bw_search -c Oco .id .name .notes <<< "$items")
  IFS=$'\t' read -r uuid val <<< "$res"
  if [[ -t 0 ]]; then
    vared -p $'Edit note |\n-----------\n' val
  else
    val=$(</dev/stdin)
  fi
  bw_edit_item_assign "$uuid" .notes "$val"
}

bw_create_login() {

  local -a sarg narg uarg
  zparseopts -D -F -K -- \
             {s,-search}:=sarg \
             {n,-name}:=narg \
             {u,-username}:=uarg || return

  if ! bw_unlock; then
    return 1
  fi
  local name username uuid
  if (( $#narg)); then
    name="${narg[-1]}"
  else
    vared -p "Login item name > " name
  fi
  if (( $#uarg)); then
    username="${uarg[-1]}"
  else
    vared -p "Login item username > " username
  fi
  local pass
  if [ -t 0 ] ; then
    pass="$(bw generate -ulns --length 21)"
  else
    pass="$(</dev/stdin)"
  fi
  bw get template item \
    | jq ".name=\"${name}\" | .login={\"username\":\"${username}\", \"password\": \"$pass\"}" \
    | bw encode | bw create item | jq -r '.login.password'
}

bw_create_note() {

  local -a sarg narg uarg
  zparseopts -D -F -K -- \
             {s,-search}:=sarg \
             {n,-name}:=narg || return

  if ! bw_unlock; then
    return 1
  fi
  local name val uuid
  if (( $#narg)); then
    name="${narg[-1]}"
  else
    vared -p "Note item name > " name
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

alias bwls='bw_list'
alias bwtsv='bw_tsv'
alias bwul='bw_unlock'
alias bwn='bw_name'
alias bwus='bw_username'
alias bwpw='bw_password'
alias bwno='bw_note'
alias bwfl='bw_field'
alias bwup='bw_user_pass'
alias bwne='bw_edit_name'
alias bwuse='bw_edit_username'
alias bwpwe='bw_edit_password'
alias bwnoe='bw_edit_note'
alias bwfle='bw_edit_field'
alias bwfla='bw_add_field'
alias bwg='bw_unlock && bw generate -ulns --length 21'
alias bwgs='bw_unlock && bw generate -uln --length 21'
alias bwlc='bw_create_login'
alias bwnc='bw_create_note'
