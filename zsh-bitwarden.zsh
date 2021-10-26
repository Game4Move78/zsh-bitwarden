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

function bw-password() {
    if [ $# -eq 1 ]; then
        if password=$(bw get password $1 2> /dev/null); then
            echo $password
            return 0
        fi
    fi
    if [ -n "$1" ]; then
        if ! searchout=$(bw list items --search "$1"); then
            echo "$1 not found"
            echo "$1"
            return 3
        fi
        if [ -n "$2" ]; then
            username=$2
        else
            select username in $(jq -r ".[].login.username" <<< "$searchout")
            do
	              break;
            done
        fi
		    if ! echo "$searchout" | jq -re ".[].login | select(.username == \"$username\") | .password"; then
			      echo "Username $2 not found. Choices:"
			      echo "$searchout" | jq -r ".[].login.username"
			      return 2
		    fi
	  else
		    echo "Usage: bw-search [key] [value]" 
		    return 1
	  fi
}
function bw-unlock() {
	  if [ -z "$BW_SESSION" ]; then
        if BW_SESSION=$(bw unlock --raw); then
		        export BW_SESSION="$BW_SESSION"
        else
            return 1
        fi

    fi
}
function bw-user() {
    if ! username=$(bw get username $1 2> /dev/null); then
        select username in $(bw list items --search $1 | jq -r ".[].login.username")
        do
	          break;
        done
    fi
    echo $username
}
alias bwu='bw-unlock'
alias bwpwd='bwu && bw-password'
alias bwusr='bwu && bw-user'
