# bash completion for nimo
#
#   source /path/to/nimo/completions/min.bash
#
# zsh can run bash completions, but only once bashcompinit is loaded — and if
# it is not, sourcing this used to greet you with "command not found: complete"
# every time you opened a terminal. So it loads what it needs, and if the shell
# still cannot do completions it quietly does nothing instead.

if [ -n "${ZSH_VERSION:-}" ]; then
    autoload -U +X compinit 2>/dev/null && compinit -u -C 2>/dev/null
    autoload -U +X bashcompinit 2>/dev/null && bashcompinit 2>/dev/null
fi

if ! type complete >/dev/null 2>&1; then
    # sourced: stop here. run directly: stop there too.
    return 0 2>/dev/null || exit 0
fi

# COMPREPLY is filled the classic way on purpose: mapfile does not exist
# in the bash 3.2 that ships with macOS.
# shellcheck disable=SC2207
_min_complete() {
    local cur prev cmds opts ids groups
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    cmds="clear tidy dark light hide empty blank apps startup duplicates desktop downloads screenshots zen dock wallpaper undo menu clean preview top doctor setup update help version"
    opts="--dry-run --yes --auto --only --days --by --limit --json --undo --restore --random --menu --fast --list --color --no-color --no-animation --quiet --help --version"
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
        --by)
            COMPREPLY=( $(compgen -W "kind letter date" -- "$cur") )
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
