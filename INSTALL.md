
# Installation

## Oh My Zsh

1. Install [jq](https://github.com/stedolan/jq) dependency

2. Clone this repository into `$ZSH_CUSTOM/plugins` (by default `~/.oh-my-zsh/custom/plugins`)

    ```sh
    git clone https://github.com/Game4Move78/zsh-bitwarden ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-bitwarden
    ```

3. Add the plugin to the list of plugins for Oh My Zsh to load (inside `~/.zshrc`):

    ```sh
    plugins=( 
        # other plugins...
        zsh-bitwarden
    )
    ```