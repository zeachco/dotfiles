rm -rf .config/alacritty
cat >~/.alacritty.toml <<EOF
[general]
import = ["~/dotfiles/configs/alacritty.toml"]

[terminal.shell]
program = "$(which zellij)"
args = ["attach", "--create", "1"]
EOF
