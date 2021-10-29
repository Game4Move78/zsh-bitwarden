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

function bw-table() {
    read json
    keys=$(IFS=, ; echo "$*")
    echo -n $1
    for arg in "${@:2}"
    do
        echo -en "\t"
        echo -n "$arg"
    done
    echo
    jq -r "(.[] | [$keys]) | @tsv" <<< $json
}

function bw-select() {
    tsv=$(</dev/stdin)
    tbl=$(nl <<< $tsv | column -t -s $'\t')
    colarr=()
    for arg in "$@"
    do
        colarr+=($(expr $arg + 1))
    done
    cols=$(IFS=, ; echo "${colarr[*]}")
    row=$(fzf --with-nth $cols --select-1 --header-lines=1 <<< $tbl | awk '{print $1}')
    sed -n "${row}p" <<< $tsv
}

# TODO: Make option arguments more safe
function bw-search() {
    columns=()
    visible=()
    out=()
    while getopts "c:C:s:o:O:" o; do
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
    bw list items --search "$search" \
        | bw-table ${columns[@]} \
        | bw-select ${visible[@]} \
        | cut -f$(IFS=, ; echo "${out[*]}")
}

function bw-unlock() {
	  if [ -z "$BW_SESSION" ]; then
        if BW_SESSION=$(bw unlock --raw); then
		        export BW_SESSION="$BW_SESSION"
        else
            unset BW_SESSION
            return 1
        fi

    fi
}

alias bwul='bw-unlock'
alias bwse='bw-unlock && bw-search'
alias bwus='bwse -c .name -o .login.username -c .notes -s '
alias bwpw='bwse -c .name -c .login.username -O .login.password -c .notes -s '
