function fish_user_key_bindings
    fish_default_key_bindings

    bind \e\[1\;5D backward-word
    bind \e\[1\;5C forward-word
end
