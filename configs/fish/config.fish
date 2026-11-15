if status is-interactive
    set -g fish_greeting

    if command -q mise
        mise activate fish | source
    end

    if command -q starship
        starship init fish | source
    end

    if command -q zoxide
        zoxide init fish | source
    end

    # Auto-start in standalone terminals and SSH, skipping multiplexers and VS Code.
    # Set DOTFILES_NO_ZELLIJ=1 before starting Fish to opt out.
    if not set -q DOTFILES_NO_ZELLIJ; and not set -q DOTFILES_ZELLIJ_STARTED; and not set -q ZELLIJ; and not set -q TMUX; and not set -q STY
        if test "$TERM_PROGRAM" = vscode; or not isatty stdin; or not isatty stdout; or not command -q zellij
            return
        end
        if set -q SSH_CONNECTION; or set -q WEZTERM_PANE; or set -q WT_SESSION; or contains -- "$TERM_PROGRAM" WezTerm Apple_Terminal iTerm.app
            # Let native Linux WezTerm finish its startup resize before Zellij reads the PTY.
            # Require 0.5s of stable dimensions, with a 2s total wait limit.
            if test "$TERM_PROGRAM" = WezTerm; and not set -q SSH_CONNECTION; and not set -q WSL_DISTRO_NAME; and not set -q WSL_INTEROP; and test (uname) = Linux; and command -q stty
                set -l previous_size (command stty size </dev/tty 2>/dev/null)
                set -l stable_samples 0
                for attempt in (seq 20)
                    sleep 0.1
                    set -l current_size (command stty size </dev/tty 2>/dev/null)
                    if test -z "$current_size"
                        break
                    end
                    if test "$current_size" = "$previous_size"; and test "$current_size" != "0 0"
                        set stable_samples (math $stable_samples + 1)
                    else
                        set stable_samples 0
                    end
                    if test $stable_samples -ge 5
                        break
                    end
                    set previous_size "$current_size"
                end
            end
            set -gx DOTFILES_ZELLIJ_STARTED 1
            zellij
        end
    end
end
