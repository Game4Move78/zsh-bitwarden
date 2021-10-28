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
    keys=$(
        function() {
            local IFS=,
            IFS=tmp
        } "$@"
    )
    echo $keys
    jq -r ".[] | [$keys] | @tsv" <<< $json | column -t -s $'\t'
}

function bw-user() {
    if ! username=$(bw get username $1 2> /dev/null); then
        username=$(bw list items --search $1 \
                   | bw-table .name .login.username .login.password \
                   | fzf --with-nth 1,2 | cut -f2)
    fi
    clipcopy <<< $username
}

function bw-pass() {
    if ! password=$(bw get password $1 2> /dev/null); then
        password=$(bw list items --search $1 \
                   | bw-table .name .login.username .login.password \
                   | fzf --with-nth 1,2 | cut -f3)
    fi
    clipcopy <<< $password
}

function bw-unlk() {
	  if [ -z "$BW_SESSION" ]; then
        if BW_SESSION=$(bw unlock --raw); then
		        export BW_SESSION="$BW_SESSION"
        else
            unset BW_SESSION
            return 1
        fi

    fi
}

alias bwulk='bw-unlk'
alias bwpwd='bw-unlk && bw-pass'
alias bwusr='bw-unlk && bw-user'
