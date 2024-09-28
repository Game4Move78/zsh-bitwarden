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
  sed -e 's/\\t/\t/g' -e 's/\\n/\n/g' -e 's/\\r/\r/g'
}

# Takes JSON as stdin and jq paths to extract into tsv as args
bw_table() {

  local -a harg

  zparseopts -D -K -E -- \
             {h,-headers}+:=harg || return

  if [[ "$#" == 0 ]]; then
    echo "Usage: $0 [PATH]..."
    return 1
  fi

  local headers=()

  for (( i = 1; i <= $#; i++)); do
    if [ "$#harg" -ge "$(( i * 2 ))" ]; then
      headers+=("${harg[$(( i * 2 ))]}")
    else
      headers+=("${(P)i}")
    fi
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
    | jq -ceM ".[] | [$keys] | select(all(.[]; . != null) and length == $width)" 2> /dev/null \
    | jq -r "@tsv" \
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

  if [ $? -ne 0 ] || [ -z "$items" ] \
       || [ $(printf "%s" "$items" | jq '. | length') -eq 0 ]; then
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

bw_enable_cache() {
  export ZSH_BW_CACHE="/run/user/$UID/zsh-bitwarden"
  export ZSH_BW_CACHE_LIST="$ZSH_BW_CACHE/bw-list-cache.gpg"
  export ZSH_BW_CACHE_SESSION="$ZSH_BW_CACHE/bw-session.gpg"
  mkdir -p "$ZSH_BW_CACHE"
  chmod 700 "$ZSH_BW_CACHE"
}

bw_disable_cache() {
  rm -rf "$ZSH_BW_CACHE"
  unset ZSH_BW_CACHE
  unset ZSH_BW_CACHE_LIST
  unset ZSH_BW_CACHE_SESSION
}

bw_reset_cache_list() {
  if [[ -n "ZSH_BW_CACHE_LIST" ]]; then
    rm -f "$ZSH_BW_CACHE_LIST"
  fi
}

bw_unlock() {
  if [[ -n "$ZSH_BW_CACHE" ]] && [[ -e "$ZSH_BW_CACHE_SESSION" ]] && BW_SESSION=$(gpg --quiet --decrypt "$ZSH_BW_CACHE_SESSION" 2> /dev/null); then
    export BW_SESSION="$BW_SESSION"
    return
  fi
  if [ -z "$BW_SESSION" ] || [ "$(bw status 2> /dev/null | jq -r '.status')" = "locked" ]; then
    unset BW_SESSION #
    if ! _bw_test_subshell; then
      local bwul_alias=$(_bw_get_alias bw_unlock)
      echo "Can't export session key in forked process. Try \`$bwul_alias\` before piping." >&2
      return 1
    fi
    if BW_SESSION=$(bw unlock --raw); then
      export BW_SESSION="$BW_SESSION"
      if [[ -n "$ZSH_BW_CACHE" ]]; then
        printf "%s" "$ZSH_BW_CACHE_SESSION" | gpg --yes --encrypt --default-recipient-self --output "$ZSH_BW_CACHE_SESSION"
      fi
    else
      return 1
    fi
  fi
}

bw_list_cache() {

  if [[ -n "$ZSH_BW_CACHE" ]] && [[ -e "$ZSH_BW_CACHE_LIST" ]] && gpg --quiet --decrypt "$ZSH_BW_CACHE_LIST" 2> /dev/null; then
    return
  fi
  if ! bw_unlock; then
    return 1
  fi
  local items=$(bw list items)
  if [[ -n "$ZSH_BW_CACHE" ]]; then
    printf "%s" "$items" | gpg --yes --encrypt --default-recipient-self --output "$ZSH_BW_CACHE_LIST"
  fi
  printf "%s" "$items"
}

bw_simplify() {

  jq "[.[] | {
     id: .id,
     name: .name,
     notes: .notes,
     username: .login.username,
     password: .login.password,
     fields: ((.fields | group_by(.name) | map({(.[0].name): map(.value)}) | add )? // {})
  }]"

}

bw_list() {
  local -a sarg sxarg jarg larg narg garg simplifyarg
  zparseopts -D -F -K -- \
             {s,-search-all}+:=sarg \
             {-search-name,-search-user,u,-search-pass,p,-search-notes}+:=sxarg \
             {j,-jq-filter}:=jarg \
             {g,-group-fields}=garg \
             -simplify=simplifyarg \
             {l,-login}=larg \
             {n,-note}=narg || return
  local items=$(bw_list_cache)
  for (( i = 2; i <= $#sarg; i+=2)); do
    items=$(printf "%s" "$items" | jq "[.[] | select(
   reduce [ .id, .name, .notes, .login.username, .login.password, (.fields[]?.value) ][] as \$field
  (false; . or (\$field // \"\" | test(\"${sarg[$i]}\";\"i\")))
    )]")
  done
  echo "$@" > /tmp/args
  for (( i = 1; i <= $#sxarg; i+=2)); do
    local jqpath=""
    case "${sxarg[$i]}" in
      "--search-name")
        jqpath=".name"
      ;;
      "--search-user"|"-u")
        jqpath=".login.username"
        ;;
      "--search-pass"|"-p")
        jqpath=".login.password"
        ;;
      "--search-notes")
        jqpath=".login.notes"
        ;;
    esac
    echo "$jqpath" > /tmp/jqpath
    echo jq "[.[] | select($jqpath | test(\"${sxarg[(( $i + 1 ))]}\";\"i\")?)]" > /tmp/items
    items=$(printf "%s" "$items" | jq "[.[] | select($jqpath | test(\"${sxarg[(( $i + 1 ))]}\";\"i\")?)]")
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
    items=$(printf "%s" "$items" | jq -ceM "[.[] | select(${jarg[$i]})]")
  done
  # Command substitution removes newline
  printf "%s\n" "$items"
}

bw_copy() {
  clipcopy
}

bw_tsv() {
  local -a \
        harg \
        parg \
        carg \
        sarg \
        targ \
        garg \
        cflarg \
        larg \
        narg
  zparseopts -D -K -E -- \
             {h,-headers}+:=harg \
             {p,-clipboard}=parg \
             {o,c,O}+:=carg \
             {t,-table}=targ || return
  # if ! bw_unlock; then
  #   return 1
  # fi
  echo "$sarg" > /tmp/sarg

  if (( !$#parg )) && (( $#targ )); then
    parg+=("-p")
  fi

  local res

  local -a bw_table_args
  (( $#harg )) && bw_table_args+=("${harg[@]}")

  if (( $#targ )); then
    IFS='' res=$(bw_list "$@" | bw_table "${bw_table_args[@]}")
  else
    local -a bw_search_args
    (( $#carg )) && bw_search_args+=("${carg[@]}")
    IFS='' res=$(bw_list "$@" | bw_search "${bw_table_args[@]}" "${bw_search_args[@]}")
  fi
  if (( $#parg )); then
    printf "%s" "$res"
  else
    printf "%s" "$res" | bw_copy
  fi
}

bw_tsv_helper() {
  local -a jpathsarg colsarg
  zparseopts -D -K -E -- \
             {o,c,O}:=colsarg \
             {j,-jpaths}+:=jpathsarg || return
  echo "${colsarg[@]}"
  jpaths=()
  for (( i = 2; i <= $#jpathsarg; i+=2)); do
    jpaths+=("${jpathsarg[$i]}")
  done
  echo "${jpaths[@]}"
  echo $@
}

# bw_tsv() {
#   local -a pedit parg carg sarg rarg farg larg narg bw_list_args
#   zparseopts -D -F -K -- \
#              {e,-e}=earg \
#              {p,-clipboard}=parg \
#              {c,-columns}:=carg \
#              {s,-search}:=sarg \
#              {r,-row}=rarg \
#              {f,-fields}=farg \
#              {l,-login}=larg \
#              {n,-note}=narg || return
#   if [[ "$#" == 0 ]]; then
#     echo "Usage: $0 [PATH]..."
#     return 1
#   fi
#   if ! bw_unlock; then
#     return 1
#   fi
#   (( $#sarg)) && bw_list_args+=("-s" "${sarg[-1]}")
#   (( $#farg)) && bw_list_args+=("-f")
#   (( $#larg)) && bw_list_args+=("-l")
#   (( $#narg)) && bw_list_args+=("-n")
#   local res

#   local colopts=""

#   if (( $#carg )); then
#     colopts="${carg[-1]}"
#   fi
#   while [ ${#colopts} -lt $# ]; do
#     colopts="${colopts}o"
#   done

#   local outpaths=()
#   for ((i = 1; i <= $#; i++)); do
#     if [[ "${colopts[i]}" != "c" ]]; then
#       outpaths+=("${(P)i}")
#     fi
#   done

#   if (( $#rarg || $#earg )); then
#     local -a bw_search_args
#     bw_search_args+=("-c" "O${colopts}")
#     #TODO: fill out repeated `o` when $1 is different
#     IFS='' res=$(bw_list "${bw_list_args[@]}" | bw_search "${bw_search_args[@]}" .id "$@")
#   else
#     IFS='' res=$(bw_list "${bw_list_args[@]}" | bw_table $@)
#   fi
#   local -a parts=("${(@s:	:)res}")
#   local uuid="${parts[1]}"
#   parts=("${parts[@]:1}")
#   res="${(j:\t:)parts[@]}"
#   #TODO  assignment
#   # START assignment
#   if (( $#earg )); then
#     local -a new
#     if [[ -t 0 ]]; then
#       for (( i = 1; i <= $#parts; i++)); do
#         local val=$(bw_raw_jq <<< "${parts[$i]}")
#         vared -p "Edit ${outpaths[$i]} > " val
#         new[$i]="$val"
#       done
#     else
#       local new_res=$(</dev/stdin)
#       new=("${(@s:	:)inp}")
#       # for ((i = 1; i <= $#; i++)); do
#       #   new[$i]=new[$i]
#       # done
#     fi
#     local filter=""
#     filter="${outpaths[1]} = \"${new[1]}\""
#     for (( i = 2; i <= $#parts; i++)); do
#       filter="| ${outpaths[1]} = \"${new[1]}\""
#     done
#     echo "$filter"
#     bw_get_item "$uuid" <<< "$items" | bw_edit_item "$uuid" "$filter"
#   # END assignment
#   elif (( $#parg )); then
#     bw_copy <<< "$res"
#   else
#     printf "%s" "$res"
#   fi
# }

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

# bw_name() {
#   local -a sarg
#   zparseopts -D -F -K -- \
#              {s,-search}:=sarg || return
#   bw_unlock && bw_list -s "${sarg[-1]}" | bw_search -c oc .name .login.username
# }

# bw_username() {
#   local -a sarg
#   zparseopts -D -F -K -- \
#              {s,-search}:=sarg || return
#   bw_unlock && bw_list -l -s "${sarg[-1]}" | bw_search -c co .name .login.username
# }

# bw_password() {
#   local -a sarg
#   zparseopts -D -F -K -- \
#              {s,-search}:=sarg || return
#   bw_tsv -ls "${sarg[-1]}" -c ccO .name .login.username .login.password
#   bw_unlock && bw_list -l -s "${sarg[-1]}" | bw_search -c ccO .name .login.username .login.password
# }

# bw_note() {
#   local -a sarg
#   zparseopts -D -F -K -- \
#              {s,-search}:=sarg || return
#   bw_unlock && bw_list -n -s "${sarg[-1]}" | bw_search -c co .name .notes
# }

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
                                       -h name -c .name \
                                       -h "$name" -o "$fieldpath")
  if (( $#parg )); then
    printf "%s" "$res"
  else
    printf "%s" "$items" | bw_copy
  fi
}

bw_field() {

  local -a sarg farg choosearg
  zparseopts -D -K -E -- \
             {p,-clipboard}=parg \
             {f,-field}:=farg \
             -choose=choosearg || return


  local items=$(bw_list --simplify "$@")

  local res
  local name

  if (( $#farg || $#choosearg )); then
    if (( $#farg )); then
      name="${farg[-1]}"
    elif (( $#choosearg)); then
      name=$(printf "%s" "$items" | bw_select_values '.fields | keys_unsorted | .[]' "field")
    fi
    res=$(printf "%s" "$items" | bw_search \
                                   -h name -c .name \
                                   -h "$name" -o ".fields[\"$name\"] | select(length > 0) | tostring")
  else
    res=$(printf "%s" "$items" | bw_search \
                                   -h name -c .name \
                                   -h fields -c '.fields | keys_unsorted | select(length > 0) | tostring' \
                                   -O '.fields | to_entries | tostring')
    res=$(printf "%s" "$res" | bw_search \
                                 -h field -o '.key' \
                                 -h value -o '.value | tostring')
    printf "%s" "$res" | IFS=$'\t' read -r name res
  fi



  res=$(printf "%s" "$res" | bw_search -h "$name" -o .)

  if (( $#parg )); then
    printf "%s" "$res"
  else
    printf "%s" "$res" | bw_copy
  fi

}

bw_get_item() {
  jq -ceM ".[] | select(.id == \"$1\")"
}

bw_edit_item() {
  bw_reset_cache_list
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
    name=$(printf "%s" "$items" | bw_select_field <<< "$items")
  fi
  #local path_val="[.fields[] | select(.name == \"$name\") | .value] | first"
  #local path_idx=".fields | map(.name) | index(\"$name\")"
  local path_val=".fields.value | select(.name == \"$name\") | .value"
  local path_idx=".fields.key"
  local uuid val idx res
  res=$(printf "%s" "$grp_items" | bw_search \
                                     -h name -o .name \
                                     -h "$name" -o "$path_val" \
                                     -O .id -O "$path_idx")
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find field $name with search args $@"
    return 1
  fi
  printf "%s" "$res" | IFS=$'\t' read -r name val uuid idx
  if (( $#darg)); then
    printf "%s" "$items" | bw_get_item "$uuid" | bw_edit_item "$uuid" "del(.fields[$idx])"
    return
  fi
  if (( $#rarg)); then
    if [[ -t 0 ]]; then
      vared -p "Edit field name > " name
    else
      name=$(</dev/stdin)
    fi
  else
    if [[ -t 0 ]]; then
      vared -p "Edit field $name > " val
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
                                       -h name -c .name \
                                       -h "$name" -o "$path_val" -O .id)
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find items with search args $@"
    return 1
  fi
  printf "%s" "$res" | IFS=$'\t' read -r val uuid
  if [[ -t 0 ]]; then
    vared -p "Field value > " val
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
                                 -h name -o .name \
                                 -h username -c .login.username \
                                 -O .id)
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find items with search strings $@"
    return 1
  fi
  printf "%s" "$res" | IFS=$'\t' read -r val uuid
  if [[ -t 0 ]]; then
    val=$(printf "%s" "$val" | bw_raw_jq)
    vared -p "Edit name > " val
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
                                 -h name -c .name \
                                 -h username -o .login.username \
                                 -O .id)
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find items with search args $@"
    return 1
  fi
  printf "%s" "$res" | IFS=$'\t' read -r val uuid
  if [[ -t 0 ]]; then
    val=$(printf "%s" "$val" | bw_raw_jq)
    vared -p "Edit username > " val
  else
    val=$(</dev/stdin)
  fi
  val=$(printf "%s" "$val" | bw_escape_jq)
  printf "%s" "$items" | bw_get_item "$uuid" | bw_edit_item_assign "$uuid" .login.username "$val"
}

bw_edit_password() {
  local -a sarg
  if ! bw_unlock; then
    return 1
  fi
  local items=$(bw_list -l "$@")
  local uuid val res
  res=$(printf "%s" "$items" | bw_search \
                                 -h name -c .name \
                                 -h username -c .login.username \
                                 -O .id -O .login.password <<< "$items")
  if [[ $? -ne 0 ]]; then
    echo "Couldn't find items with search args $@"
    return 1
  fi
  printf "%s" "$res" | IFS=$'\t' read -r uuid val
  if [[ -t 0 ]]; then
    val=$(printf "%s" "$val" | bw_raw_jq)
    vared -p "Edit password > " val
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
                                 -h name -c .name \
                                 -h notes -o .notes -O .id <<< "$items")
  printf "%s" "$res" | IFS=$'\t' read -r uuid val
  if [[ -t 0 ]]; then
    val=$(printf "%s" "$val" | bw_raw_jq)
    vared -p $'Edit note |\n-----------\n' val
  else
    val=$(</dev/stdin)
  fi
  val=$(printf "%s" "$val" | bw_escape_jq)
  bw_get_item "$uuid" <<< "$items" | bw_edit_item_assign "$uuid" .notes "$val"
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
    vared -p "Login item name > " name
  fi
  name=$(printf "%s" "$name" | bw_escape_jq)
  if (( $#uarg)); then
    username="${uarg[-1]}"
  else
    username=$(printf "%s" "$username" | bw_raw_jq)
    vared -p "Login item username > " username
  fi
  username=$(printf "%s" "$username" | bw_escape_jq)
  local pass
  if [ -t 0 ] ; then
    pass="$(bw generate -ulns --length 21)"
  else
    pass="$(</dev/stdin)"
  fi
  val=$(printf "%s" "$val" | bw_escape_jq)
  bw_reset_cache_list
  bw get template item \
    | jq ".name=\"${name}\" | .login={\"username\":\"${username}\", \"password\": \"$pass\"}" \
    | bw encode | bw create item | jq -r '.login.password'
}

bw_create_note() {

  local -a sarg narg uarg
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
    vared -p "Note item name > " name
  fi
  name=$(printf "%s" "$name" | bw_escape_jq)
  if [[ -t 0 ]]; then
    val=$(printf "%s" "$val" | bw_raw_jq)
    vared -p $'Enter note |\n-----------\n' val
  else
    val=$(</dev/stdin)
  fi
  val=$(printf "%s" "$val" | bw_escape_jq)
  bw_reset_cache_list
  uuid=$(bw get template item \
           | jq ".name=\"${name}\" | .notes=\"${val}\" | .type=2 | .secureNote.type = 0" \
           | bw encode | bw create item | jq -r '.id')
}

alias bwls='bw_list'
alias bwtsv='bw_tsv'
alias bwul='bw_unlock'
alias bwn='bw_tsv -h name -h username -o .name -c .login.username'
alias bwus='bw_tsv -h name -h username -c .name -o .login.username'
alias bwpw='bw_tsv -h name -h username -h password -c .name -c .login.username -O .login.password'
alias bwno='bw_tsv -c .name -o .notes'
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
