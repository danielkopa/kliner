# bash completion for nimo
#
#   source /path/to/nimo/completions/min.bash
#
# zsh users need `autoload -U bashcompinit && bashcompinit` first.

# COMPREPLY is filled the classic way on purpose: mapfile does not exist
# in the bash 3.2 that ships with macOS.
# shellcheck disable=SC2207
_min_complete() {
    local cur prev cmds opts ids groups
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    cmds="tidy desktop dock wallpaper clean preview top doctor setup update help version"
    opts="--dry-run --yes --only --days --limit --json --undo --restore --random --list --no-color --quiet --help --version"
    ids="user-caches logs crash-reports trash quicklook mail-downloads xcode homebrew node python downloads ios-backups xcode-archives device-support node-modules big-files"
    groups="finder dock screenshots keyboard dialogs"

    case "$prev" in
        --only)
            case " ${COMP_WORDS[*]} " in
                *" setup "*) COMPREPLY=( $(compgen -W "$groups" -- "$cur") ) ;;
                *)           COMPREPLY=( $(compgen -W "$ids" -- "$cur") ) ;;
            esac
            return 0
            ;;
        --days|--limit)
            return 0
            ;;
    esac

    case "$cur" in
        -*) COMPREPLY=( $(compgen -W "$opts" -- "$cur") ) ;;
        *)  COMPREPLY=( $(compgen -W "$cmds" -- "$cur") ) ;;
    esac
    return 0
}

complete -F _min_complete min
