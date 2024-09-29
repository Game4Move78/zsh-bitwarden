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

bw_escape_jq() {
  sed -e 's/\t/\\t/g' -e 's/\n/\\n/g' -e 's/\r/\\r/g'
}

bw_raw_jq() {
  sed -e 's/\\t/\t/g' -e 's/\\n/\n/g' -e 's/\\r/\r/g' -e 's/\\\\/\\/g'
}

export BW_DEFAULT_HEADERS="${0:h}/default-headers.csv"

bw_default_header() {
  while IFS=$'\n' read -r line; do
    local key=$(printf "%s" "$line" | awk -F, '{print $1}' | sed 's/^"//; s/"$//')
    local value=$(printf "%s" "$line" | awk -F, '{print $2}' | sed 's/^"//; s/"$//')
    if [[ "$key" == "$1" ]]; then
      printf "%s" "$value"
      return
    fi
  done < "$BW_DEFAULT_HEADERS"
  printf "%s" "$1"
  # case "$1" in
  #   ".id") printf "%s" "Item ID" ;;
  #   ".login.username"|".username") printf "%s" "Username" ;;
  #   ".login.password"|".password") printf "%s" "Password" ;;
  #   ".name") printf "%s" "Name" ;;
  #   *) printf "%s" "$1"
  # esac
}

# Takes JSON as stdin and jq paths to extract into tsv as args
bw_table() {

  local -a harg rharg

  zparseopts -D -K -E -- \
             {h,-headers}+:=harg \
             {H,-rev-headers}+:=rharg \
    || return

  if [[ "$#" == 0 ]]; then
    echo "Usage: $0 [PATH]..."
    return 1
  fi

  local headers=()

  for (( i = 1; i <= $#; i++)); do
    local header=""
    if [ "$#harg" -ge "$(( i * 2 ))" ]; then
      header="${harg[$(( i * 2 ))]}"
    elif [ "1" -le "$(( (i - $#) * 2 + $#rharg ))" ]; then
      header="${rharg[$(( (i - $#) * 2 + $#rharg ))]}"
    else
      header=$(bw_default_header "${(P)i}")
    fi
    headers+=("$header")
  done

  local json=$(</dev/stdin)
  # Comma-join arguments
  local width="$#"
  local keys="($1)? // null"
  for key in "${@:2}"; do
    keys="$keys, ($key)? // null"
  done

  # Construct tsv with values selected using args
  local jq_output=$(
    printf "%s" "$json" \
    | jq -rceM ".[] | [$keys] | select(all(.[]; . != null) and length == $width) | @tsv" 2> /dev/null
  )

  if [[ -z "$jq_output" ]]; then
    echo "Error: No results." >&2
    return 1
  fi

  # Output arguments as tsv header
  printf "%s" "${headers[1]}"
  for arg in "${headers[@]:1}"; do
    printf "\t%s" "$arg"
  done
  printf "\n"

  printf "%s\n" "$jq_output"
}

#NOTE: bw escapes \t\n
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
  local tbl=$( \
    printf "%s" "$tsv" \
    | cut -d $'\t' -f "$cols" \
    | column -t -s $'\t' \
    | nl -n rz \
  )

  # Check if the table was generated correctly
  if [[ -z "$tbl" ]]; then
    echo "Error: Unable to generate table. Please check the column indices." >&2
    return 1
  fi

  local row=$( \
    printf "%s" "$tbl" \
    | fzf -d $'\t' --with-nth=2 --select-1 --header-lines=1 \
    | awk '{print $1}' \
  )

  if [[ "$?" -ne 0 || -z "$row" ]]; then
    echo "Couldn't return value from fzf. Is the header line missing?" >&2
    return 2
  fi

  # Output the corresponding row from the original tsv
  printf "%s" "$tsv" | sed -n "${row}p"
}

bw_search() {
  local -a carg harg # oarg Oarg

  zparseopts -D -K -E -- \
             {h,-headers}+:=harg \
             {o,c,O}+:=carg || return

  # local -a POSITIONAL_ARGS=()
  # while [[ $# -gt 0 ]]; do
  #   local old="$1"
  #   shift
  #   case $old in
  #     -c|--columns)
  #       carg="$1"
  #       shift
  #       ;;
  #     -*|--*)
  #       echo "Unknown option $old" >&2
  #       exit 1
  #       ;;
  #     *)
  #       POSITIONAL_ARGS+=("$old") # save positional arg
  #       ;;
  #   esac
  # done

  # set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

  local -a jqpaths colopts

  for (( i = 1; i <= $#carg; i+=2)); do
    colopts+=("${${carg[$i]}[-1]}")
    jqpaths+=("${carg[(($i + 1))]}")
  done
  jqpaths+=("$@")

  while [ ${#colopts} -lt $#jqpaths ]; do
    colopts+=("o")
  done

  local columns=()
  local visible=()
  local out=()
  local o search

  # local colopts=$1
  # local -a jqpaths=("${@:2}")

  # Validate remaining arguments (JQ paths)
  if [ $#jqpaths -lt 1 ]; then
    echo "Error: At least one JQ path must be provided." >&2
    return 1
  fi

  # Ensure the number of colopts matches the number of jqpaths
  if [ ${#colopts} -ne ${#jqpaths} ]; then
    echo "Error: The number of column options (${#colopts}) does not match the number of JQ paths (${#jqpaths})." >&2
    return 1
  fi

  # Process the column options
  for ((i = 1; i <= ${#colopts}; i++)); do
    local colopt="${colopts[$i]}"
    case "$colopt" in
      c)
        visible+=($i)  # Add column index to visible
        ;;
      o)
        visible+=($i)
        out+=($i)  # Visible and output
        ;;
      O)
        out+=($i)  # Output only, not visible
        ;;
      *)
        echo "Error: Invalid column option '$colopt' at position $i" >&2
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

  local noitems=$(printf "%s" "$items" | jq '. | length')

  if [ $? -ne 0 ] || [ -z "$items" ] \
       || [ "$noitems" -eq "0" ]; then
    echo "No results found. Try '' to search all items." >&2
    return 4
  fi

  local tsv=$(printf "%s" "$items" | bw_table "${harg[@]}" "${jqpaths[@]}")

  if [ $? -ne 0 ]; then
    echo "Failed to construct tsv" >&2
    return 4
  fi

  local row=$(printf "%s" "$tsv" | _bw_select "${visible[@]}")

  if [ $? -ne 0 ]; then
    echo "Failed to select row" >&2
    return 4
  fi

  local comma_out=$(IFS=, ; echo "${out[*]}")

  printf "%s" "$row" | cut -f"$comma_out" | sed -z '$ s/\n$//'

}

bw_request() {
  local method=$1 endpoint=$2
  local -a data_args
  if ! [[ -t 0 ]]; then
    data_args+=("-d" "$(</dev/stdin)")
  fi
  local res=$(curl -sX "$method" "http://localhost:8087$endpoint" -H 'accept: application/json' -H 'Content-Type: application/json' "${data_args[@]}") || return $?
  # local res=$(wget --method="$method" --header="accept: application/json" --header="Content-Type: application/json" --body-data="${data_args[@]}" -qO- "http://localhost:8087$endpoint") || return $?
  echo "$res" > /tmp/res
  printf "%s" "$res" | jq empty > /dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    printf "%s\n" "$res" >&2
    return 1
  fi
  local success=$(printf "%s" "$res" | jq -rceM .success)
  if [[ "$success" == "false" ]]; then
    printf "%s" "$res" | jq -rceM .message >&2
    return 1
  fi
  local jq_cond=$(printf "%s" "$res" | jq -ceM 'has("data")')
  if [[ "$jq_cond" == "true" ]]; then
    res=$(printf "%s" "$res" | jq -ceM .data)
  fi
  printf "%s" "$res"
}

bw_unlock() {
  if ! pgrep -f "bw serve" > /dev/null 2>&1; then
    nohup bw serve > /dev/null 2> /dev/null &
    sleep 2
  fi

  local bw_status
  if ! bw_status=$(bw_request GET '/status'); then
    return 1
  fi
  echo "$bw_status" > /tmp/debug
  bw_status=$(printf "%s" "$bw_status" | jq -rceM '.template.status')
  if [[ "$bw_status" == "unlocked" ]]; then
    return
  fi

  local pass

  echo -n "Enter your master password: " >&2

  if ! read -s pass; then
    return 1
  fi
  pass=$(printf "%s" "$pass" | awk '{print "{\"password\":\"" $0 "\"}"}')
  echo "$pass" > /tmp/debug
  if ! printf "%s" "$pass" | bw_request POST /unlock > /dev/null; then
     return 1
  fi
  printf "\nVault unlocked\n"
}

bw_template() {
  bw_request GET /object/template/item | jq -ceM ".template"
}

bw_list_cache() {

  if ! bw_unlock; then
    return 1
  fi
  bw_request GET /list/object/items | jq -ceM '.data'

}

bw_simplify() {

  jq -ceM "[.[] | {
     id: .id,
     name: .name,
     notes: .notes,
     username: .login.username,
     password: .login.password,
     fields: ((.fields | group_by(.name) | map({(.[0].name): map(.value)}) | add )? // {})
  }]"

}

bw_unsimplify() {
  local item=$(jq -ceM '{
  id: .id,
  name: .name,
  notes: .notes,
  fields: [
    .fields | to_entries[] |
    .value[] as $v |
    {name: .key, value: $v, type: 0, linkedId: null}
  ],
  login: {
    username: .username,
    password: .password
  }
  }')
  local uuid=$(printf "%s" "$item" | jq -rceM ".id")
  local old_item
  echo "$uuid" > /tmp/testme
  if [[ "$uuid" == "null" ]]; then
    old_item=$(bw_template)
  else
    old_item=$(bw_list_cache | bw_get_item "$uuid")
  fi
  printf "%s" "$old_item $item" | jq -ceMs ".[0] * .[1]"
}

bw_list() {
  local -a sarg sxarg jarg garg simplifyarg larg narg
  zparseopts -D -F -K -- \
             {s,-search-all}+:=sarg \
             {-search-name,-search-user,-search-pass,-search-note}+:=sxarg \
             {j,-search-jq}:=jarg \
             {g,-group-fields}=garg \
             -simplify=simplifyarg \
             {l,-login}=larg \
             {n,-note}=narg || return
  local items=$(bw_list_cache)
  for (( i = 2; i <= $#sarg; i+=2)); do
    items=$(printf "%s" "$items" | jq -ceM "[.[] | select(
   reduce [ .id, .name, .notes, .login.username, .login.password, (.fields[]?.value) ][] as \$field
  (false; . or (\$field // \"\" | test(\"${sarg[$i]}\";\"i\")))
    )]")
  done
  for (( i = 1; i <= $#sxarg; i+=2)); do
    local jqpath=""
    case "${sxarg[$i]}" in
      "--search-name")
        jqpath=".name"
      ;;
      "--search-user")
        jqpath=".login.username"
        ;;
      "--search-pass")
        jqpath=".login.password"
        ;;
      "--search-notes")
        jqpath=".login.notes"
        ;;
    esac
    items=$(printf "%s" "$items" | jq -ceM "[.[] | select($jqpath | test(\"${sxarg[(( $i + 1 ))]}\";\"i\")?)]")
  done
  # local items=$(bw list items --search "${sarg[-1]}")
  if (( $#larg || $#narg)); then
    local item_type
    if (( $#larg)); then
      item_type=1
    elif (( $#narg )); then
      item_type=2
    fi
    items=$(printf "%s" "$items" | jq -ceM "[.[] | select(.type == $item_type)]")
  fi
  if (( $#simplifyarg )); then
    items=$(printf "%s" "$items" | bw_simplify)
  elif (( $#garg )); then
    items=$(printf "%s" "$items" | bw_group_fields)
  fi
  for (( i = 2; i <= $#jarg; i+=2)); do
    items=$(printf "%s" "$items" | jq -ceM "[.[] | select((${jarg[$i]})? // false)]")
  done
  # Command substitution removes newline
  printf "%s\n" "$items"
}

bw_copy() {
  clipcopy
}

bw_tsv() {
  local -a \
        sarg \
        sxarg \
        jarg \
        garg \
        simplifyarg \
        larg \
        narg \
        harg \
        rarg \
        parg \
        carg \
        targ
  zparseopts -D -K -E -- \
             {s,-search-all}+:=sarg \
             {-search-name,-search-user,-search-pass,-search-note}+:=sxarg \
             {j,-search-jq}:=jarg \
             {g,-group-fields}=garg \
             -simplify=simplifyarg \
             {l,-login}=larg \
             {n,-note}=narg \
             {h,-headers}+:=harg \
             {r,-raw}=rarg \
             {p,-clipboard}=parg \
             {o,c,O}+:=carg \
             {t,-table}=targ || return

  if (( !$#parg )) && { (( $#targ )) || ! [[ -t 1 ]]; }; then
    parg+=("-p")
  fi

  local res

  local -a bw_table_args
  (( $#harg )) && bw_table_args+=("${harg[@]}")

  local items
  if [[ -t 0 ]]; then
    local -a bw_list_args
    (( $#sarg )) && bw_list_args+=("${sarg[@]}")
    (( $#sxarg )) && bw_list_args+=("${sxarg[@]}")
    (( $#jarg )) && bw_list_args+=("${jarg[@]}")
    (( $#garg )) && bw_list_args+=("${garg[@]}")
    (( $#simplifyarg )) && bw_list_args+=("${simplifyarg[@]}")
    (( $#larg )) && bw_list_args+=("${larg[@]}")
    (( $#narg )) && bw_list_args+=("${narg[@]}")
    items=$(bw_list "${bw_list_args[@]}")
  else
    items=$(</dev/stdin)
  fi

  if (( $#targ )); then
    IFS='' res=$(printf "%s" "$items" | bw_table "${bw_table_args[@]}" "$@")
  else
    local -a bw_search_args
    (( $#carg )) && bw_search_args+=("${carg[@]}")
    IFS='' res=$(printf "%s" "$items" | bw_search "${bw_table_args[@]}" "${bw_search_args[@]}" "$@")
  fi
  if (( $#rarg )); then
    res=$(printf "%s" "$res" | bw_raw_jq)
  fi
  if (( $#parg )); then
    printf "%s" "$res"
  else
    printf "%s" "$res" | bw_copy
  fi
}

bw_user_pass() {
  local -a sarg
  if ! bw_unlock; then
    return 1
  fi
  local userpass=$(bw_list -l "$@" | bw_search -c .name -o .login.username -O .login.password)
  if [[ "$?" -ne 0 ]]; then
    return 2
  fi
  echo -n "Hit enter to copy username..."
  read _ && printf "%s" "$userpass" | cut -f 1 | clipcopy
  echo -n "Hit enter to copy password..."
  read _ && printf "%s" "$userpass" | cut -f 2 | clipcopy
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

bw_field_old() {

  local -a sarg farg
  zparseopts -D -K -E -- \
             {p,-clipboard}=parg \
             {f,-field}:=farg || return

  local items=$(bw_list -g "$@")

  local name
  if (( $#farg)); then
    name="${farg[-1]}"
  else
    name=$(printf "%s" "$items" | bw_select_field)
  fi

  #local fieldpath="[.fields[] | select(.name == \"$name\") | .value] | first"
  local fieldpath=".fields.value | select(.name == \"$name\") | .value"

  local res=$(printf "%s" "$items" | bw_search \
                                       -c .name \
                                       -H "$name" -o "$fieldpath")
  if (( $#parg )); then
    printf "%s" "$res"
  else
    printf "%s" "$items" | bw_copy
  fi
}

bw_field() {

  local -a rarg parg farg choosearg
  zparseopts -D -K -E -- \
             {r,-raw}=rarg \
             {p,-clipboard}=parg \
             {f,-field}:=farg \
             -choose=choosearg || return


  local items=$(bw_list --simplify "$@")

  local res
  local item
  local name
  local uuid

  if (( $#farg || $#choosearg )); then
    if (( $#farg )); then
      name="${farg[-1]}"
    elif (( $#choosearg)); then
      name=$(printf "%s" "$items" | bw_select_values '.fields | keys_unsorted | .[]' "field")
    fi
    uuid=$(printf "%s" "$items" | bw_search \
                                   -O .id \
                                   -c .name \
                                   -H "$name" -c ".fields[\"$name\"] | select(length > 0) | join(\", \")")
    item=$(printf "%s" "$items" | bw_get_item "$uuid")
  else
    uuid=$(printf "%s" "$items" | bw_search \
                                   -O '.id' \
                                   -c .name \
                                   -H fields -c ".fields | keys_unsorted | select(length > 0) | join(\", \")" \
                                   )
    item=$(printf "%s" "$items" | bw_get_item "$uuid")
    name=$(printf "%s" "$item" | jq -ceM ".fields | to_entries" | bw_search \
                                 -h field -o '.key' \
                                 -h value -c '.value | join(", ")')
  fi

  res=$(printf "%s" "$item" | jq -ceM ".fields[\"$name\"]")
  res=$(printf "%s" "$res" | bw_search -h "$name" -o .)

  if (( $#parg )); then
    printf "%s" "$res"
  else
    printf "%s" "$res" | bw_copy
  fi

}

bw_get_item() {
  jq -ceM ".[] | select(.id == \"$1\")$2"
}

bw_edit_json() {
  local item=$(</dev/stdin)
  local uuid=$(printf "%s" "$item" | jq -rceM ".id")
  if [[ "$uuid" == "null" ]]; then
    printf "%s" "$item" | bw_request POST /object/item
  else
    printf "%s" "$item" | bw_request PUT "/object/item/$uuid"
  fi
}

bw_edit_item() {
  # bw_reset_cache_list
  jq -ceM "$2" | bw_request PUT "/object/item/$1"
}

bw_edit_item_assign() {

  bw_edit_item "$1" "$2 = \"$3\""

}

bw_edit_item_append() {

  bw_edit_item "$1" "$2 += [$3]"

}

bw_edit_field() {

  local -a narg rarg darg farg
  zparseopts -D -K -E -- \
             {n,-new}=narg \
             {r,-rename}=rarg \
             {d,-delete}=darg \
             {f,-field}:=farg || return

  if ! bw_unlock; then
    return 1
  fi
  local items=$(bw_list "$@")
  local grp_items=$(printf "%s" "$items" | bw_group_fields)
  local name
  if (( $#farg)); then
    name="${farg[-1]}"
  else
    name=$(printf "%s" "$items" | bw_select_field)
  fi
  local path_val=".fields.value | select(.name == \"$name\") | .value"
  local path_idx=".fields.key"
  local uuid val idx res
  res=$(printf "%s" "$grp_items" | bw_search \
                                     -O .id -O "$path_idx" \
                                     -o .name \
                                     -H "$name" -o "$path_val" \
                                     )
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find field $name with search args $@" >&2
    return 1
  fi
  printf "%s" "$res" | IFS=$'\t' read -r uuid idx name val
  if (( $#darg)); then
    printf "%s" "$items" | bw_get_item "$uuid" | bw_edit_item "$uuid" "del(.fields[$idx])"
    return
  fi
  if (( $#rarg)); then
    if [[ -t 0 ]]; then
      vared -p "Edit field name: " name
    else
      name=$(</dev/stdin)
    fi
  else
    if [[ -t 0 ]]; then
      vared -p "Edit field $name: " val
    else
      val=$(</dev/stdin)
    fi
  fi
  printf "%s" "$items" | bw_get_item "$uuid" | bw_edit_item "$uuid" ".fields[$idx].name=\"$name\" | .fields[$idx].value=\"$val\""
}

bw_add_field() {

  local -a farg
  zparseopts -D -K -E -- \
             {f,-field}:=farg || return
  if ! bw_unlock; then
    return 1
  fi
  local items=$(bw_list "$@")
  local name val
  if (( $#farg)); then
    name="${farg[-1]}"
  else
    name=$(printf "%s" "$items" | bw_select_field)
  fi
  local path_val="[(.fields[] | select(.name == \"$name\") | .value) // \"\"] | first"
  local res=$(printf "%s" "$items" | bw_search \
                                       -O .id -c .name \
                                       -H "$name" -o "$path_val")
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find items with search args $@" >&2
    return 1
  fi
  printf "%s" "$res" | IFS=$'\t' read -r uuid val
  if [[ -t 0 ]]; then
    vared -p "Field value: " val
  else
    val=$(</dev/stdin)
  fi
  local field_json="{\"name\": \"$name\", \"value\": \"$val\"}"
  printf "%s" "$items" | bw_get_item "$uuid" | bw_edit_item_append "$uuid" ".fields" "$field_json"
}

bw_edit_name() {
  if ! bw_unlock; then
    return 1
  fi
  local items=$(bw_list "$@")
  local uuid val res
  res=$(printf "%s" "$items" | bw_search \
                                 -o .name \
                                 -c .login.username \
                                 -O .id)
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find items with search strings $@" >&2
    return 1
  fi
  printf "%s" "$res" | IFS=$'\t' read -r val uuid
  if [[ -t 0 ]]; then
    val=$(printf "%s" "$val" | bw_raw_jq)
    vared -p "Edit name: " val
  else
    val=$(</dev/stdin)
  fi
  val=$(printf "%s" "$val" | bw_escape_jq)
  printf "%s" "$items" | bw_get_item "$uuid" | bw_edit_item_assign "$uuid" ".name" "$val"
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
  if ! bw_unlock; then
    return 1
  fi
  local items=$(bw_list -l "$@")
  local uuid val res
  res=$(printf "%s" "$items" | bw_search \
                                 -c .name \
                                 -o .login.username \
                                 -O .id)
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find items with search args $@" >&2
    return 1
  fi
  printf "%s" "$res" | IFS=$'\t' read -r val uuid
  if [[ -t 0 ]]; then
    val=$(printf "%s" "$val" | bw_raw_jq)
    vared -p "Edit username: " val
  else
    val=$(</dev/stdin)
  fi
  val=$(printf "%s" "$val" | bw_escape_jq)
  printf "%s" "$items" | bw_get_item "$uuid" | bw_edit_item_assign "$uuid" .login.username "$val"
}

bw_edit_password() {
  if ! bw_unlock; then
    return 1
  fi
  local items=$(bw_list -l "$@")
  local uuid val res
  res=$(printf "%s" "$items" | bw_search \
                                 -c .name \
                                 -c .login.username \
                                 -O .id -O .login.password)
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find items with search args $@" >&2
    return 1
  fi
  printf "%s" "$res" | IFS=$'\t' read -r uuid val
  if [[ -t 0 ]]; then
    val=$(printf "%s" "$val" | bw_raw_jq)
    echo -n "Enter password: " >&2
    read -s val
    echo
    local dup
    echo -n "Enter password again: " >&2
    read -s dup
    echo
    if [[ "$val" != "$dup" ]]; then
      echo "Passwords don't match" >&2
      return 1
    fi
    # vared -p "Edit password: " val
  else
    val=$(</dev/stdin)
  fi
  val=$(printf "%s" "$val" | bw_escape_jq)
  printf "%s" "$items" | bw_get_item "$uuid" | bw_edit_item_assign "$uuid" .login.password "$val"
}

bw_edit_note() {
  if ! bw_unlock; then
    return 1
  fi
  local items=$(bw_list -n "$@")
  local uuid val res
  res=$(printf "%s" "$items" | bw_search \
                                 -c .name \
                                 -o .notes -O .id)
  printf "%s" "$res" | IFS=$'\t' read -r uuid val
  if [[ -t 0 ]]; then
    val=$(printf "%s" "$val" | bw_raw_jq)
    vared -p $'Edit note |\n-----------\n' val
  else
    val=$(</dev/stdin)
  fi
  val=$(printf "%s" "$val" | bw_escape_jq)
  printf "%s" "$items" | bw_get_item "$uuid" | bw_edit_item_assign "$uuid" .notes "$val"
}

bw_create_login() {

  local -a narg uarg
  zparseopts -D -F -K -- \
             {n,-name}:=narg \
             {u,-username}:=uarg || return

  if ! bw_unlock; then
    return 1
  fi
  local name username uuid
  if (( $#narg)); then
    name=$(printf "%s" "$name" | bw_raw_jq)
    name="${narg[-1]}"
  else
    vared -p "Login item name: " name
  fi
  name=$(printf "%s" "$name" | bw_escape_jq)
  if (( $#uarg)); then
    username="${uarg[-1]}"
  else
    username=$(printf "%s" "$username" | bw_raw_jq)
    vared -p "Login item username: " username
  fi
  username=$(printf "%s" "$username" | bw_escape_jq)
  local pass
  if [ -t 0 ] ; then
    pass="$(bw generate -ulns --length 21)"
  else
    pass="$(</dev/stdin)"
  fi
  val=$(printf "%s" "$val" | bw_escape_jq)
  # bw_reset_cache_list
  # bw_template \
  #   | jq -ceM ".name=\"${name}\" | .login.username=\"$username\" | .login.password=\"$pass\"" \
  #   | bw encode | bw create item | jq -rceM '.login.password'
  bw_template \
      | jq -ceM ".name=\"${name}\" | .login.username=\"$username\" | .login.password=\"$pass\"" \
      | bw_request POST "/object/item" | jq -rceM '.login.password'
}

bw_create_note() {

  local -a narg
  zparseopts -D -F -K -- \
             {n,-name}:=narg || return

  if ! bw_unlock; then
    return 1
  fi
  local name val uuid
  if (( $#narg)); then
    name="${narg[-1]}"
  else
    name=$(printf "%s" "$name" | bw_raw_jq)
    vared -p "Note item name: " name
  fi
  name=$(printf "%s" "$name" | bw_escape_jq)
  if [[ -t 0 ]]; then
    val=$(printf "%s" "$val" | bw_raw_jq)
    vared -p $'Enter note |\n-----------\n' val
  else
    val=$(</dev/stdin)
  fi
  val=$(printf "%s" "$val" | bw_escape_jq)
  # bw_reset_cache_list
  # uuid=$(bw_template \
  #          | jq ".name=\"${name}\" | .notes=\"${val}\" | .type=2 | .secureNote.type = 0" \
  #          | bw encode | bw create item | jq -r '.id')
  uuid=$(bw_template \
             | jq ".name=\"${name}\" | .notes=\"${val}\" | .type=2 | .secureNote.type = 0" \
             | bw_request POST /object/item | jq -r '.id')
}

bw_json() {

  if ! bw_unlock; then
    return 1
  fi

  local items=$(bw_list "$@")

  local uuid=$(printf "%s" "$items" | bw_tsv -r -p -O '.id' -c .name)

  printf "%s" "$items" | bw_get_item "$uuid"

}

bw_init_file() {
  local itemfile=$(mktemp)
  chmod 600 "$itemfile"
  cat > "$itemfile"
  printf "%s" "$itemfile"
}

bw_edit_file() {
  local modtime_before=$(stat -c %Y "$1")
  $EDITOR "$1"
  local modtime_after=$(stat -c %Y "$1")
  if [[ "$modtime_before" -eq "$modtime_after" ]]; then
    shred -u "$itemfile"
    return 1
  fi
}

bw_json_edit() {
  if ! bw_unlock; then
    return 1
  fi
  local -a simplifyarg narg
  zparseopts -D -K -E -- \
             {n,-new}=narg \
             -simplify=simplifyarg || return

  local item

  if (( $#narg )); then
    item=$(bw_template)
    if (( $#simplifyarg )); then
      item=$(printf "%s" "$item" | jq -ceM "[.]" | bw_simplify)
    fi
  else
    item=$(bw_json "$@" "${simplifyarg[@]}")
  fi
  item=$(printf "%s" "$item" | jq -M)
  local itemfile=$(printf "%s" "$item" | bw_init_file)
  bw_edit_file "$itemfile"
  if [[ $? -ne 0 ]]; then
    return 1
  fi
  item=$(cat "$itemfile")
  shred -u "$itemfile"
  if (( $#simplifyarg )); then
    item=$(printf "%s" "$item" | bw_unsimplify)
  fi
  printf "%s" "$item" | bw_edit_json
  # bw_reset_cache_list
}

alias bwjs='bw_json'
alias bwjse='bw_json_edit'
alias bwls='bw_list'
alias bwtsv='bw_tsv'
alias bwul='bw_unlock'
alias bwn='bw_tsv -o .name'
alias bwus='bw_tsv -c .name -o .login.username'
alias bwpw='bw_tsv -c .name -c .login.username -O .login.password'
alias bwno='bw_tsv -c .name -o .notes'
alias bwfl='bw_field'
alias bwup='bw_user_pass'
alias bwne='bw_edit_name'
alias bwuse='bw_edit_username'
alias bwpwe='bw_edit_password'
alias bwnoe='bw_edit_note'
alias bwfle='bw_edit_field'
alias bwfla='bw_add_field'
# alias bwg='bw_unlock && bw generate -ulns --length 21'
# alias bwgs='bw_unlock && bw generate -uln --length 21'
alias bwg='bw_unlock && bw_request GET "/generate?length=21&uppercase=true&lowercase=true&number=true&special=true"'
alias bwgs='bw_unlock && bw_request GET "/generate?length=21&uppercase=true&lowercase=true&number=true&special=false"'
alias bwlc='bw_create_login'
alias bwnc='bw_create_note'
