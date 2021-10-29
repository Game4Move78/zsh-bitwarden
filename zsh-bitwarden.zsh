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
    echo "usage: $0 path1 path2..."
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
  jq -er ".[] | [$keys] | @tsv" <<< $json
  if [[ "$?" -ne 0 ]]; then
    echo "Unable to construct array [$keys]"
    return 1
  fi
}

# Takes tsv as stdin and columns to show in fzf as args
_bw_select() {
  if [[ "$#" -eq 0 ]]; then
    echo "usage: $0 n_column1 n_column2..."
    return 1
  fi
  local tsv=$(</dev/stdin)
  # Printable table with index field
  local tbl=$(nl <<< $tsv | column -t -s $'\t')
  local colarr=()
  local arg
  for arg in "$@"
  do
    colarr+=($(expr $arg + 1))
  done
  local cols=$(IFS=, ; echo "${colarr[*]}")
  local row=$(fzf --with-nth $cols --select-1 --header-lines=1 <<< $tbl | awk '{print $1}')
  if [[ "$?" -ne 0 ]]; then
    echo "Couldn't return value from fzf. Is the header line missing?"
    return 2
  fi
  sed -n "${row}p" <<< $tsv
}

# TODO: Make option arguments more safe
bw_search() {
  local columns=()
  local visible=()
  local out=()
  local o search
  while getopts "c:C:so:O:" o; do
    case $o in
      c) # Visible column
        columns+=($OPTARG)
        visible+=(${#columns[@]})
        ;;
      s) # Search string
        search=$OPTARG
        ;;
      o) # Output column
        columns+=($OPTARG)
        out+=(${#columns[@]})
        visible+=(${#columns[@]})
        ;;
      O) # Hidden output column
        columns+=($OPTARG)
        out+=(${#columns[@]})
        ;;
    esac
  done
  if [[ "${#visible}" -eq 0 ]]; then
    echo "No visible fields entered"
    return 1
  fi
  if [[ "${#out}" -eq 0 ]]; then
    echo "No output fields entered"
    return 2
  fi
  items=$(bw list items --search "$search")
  if [ $(jq '. | length' <<< $items) -eq 0 ]; then
    echo "No results. Try '-s .' to search through all items."
    return 4
  fi
  _bw_table ${columns[@]} <<< $items \
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

alias bwul='bw_unlock'
alias bwse='bw_unlock && bw_search'
alias bwus='bwse -c .name -o .login.username -c .notes -s '
alias bwpw='bwse -c .name -c .login.username -O .login.password -c .notes -s '
