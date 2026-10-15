# config.nu
#
# See https://www.nushell.sh/book/configuration.html

const ENV_DIR = ($nu.env-path | path dirname)
use ($ENV_DIR | path join "color_config.nu") *
$env.config.color_config = (define_color_config)

$env.config.buffer_editor = "vim"
$env.config.show_banner = false

# The second keystroke of kanata's word selection (Alt+Shift+Right after Alt+Left moves to the word start) is not in reedline's default keybindings, so add it.
# The first keystroke (Alt+Left = MoveWordLeft) already works with reedline's defaults.
$env.config.keybindings ++= [
    {
        name: select_word_at_cursor
        modifier: alt_shift
        keycode: right
        mode: emacs
        event: { edit: MoveWordRight, select: true }
    }
]

def --env yz [...args] {
    let tmp = (mktemp -t "yazi-cwd.XXXXXX")
    ^yazi --remote-events=yank ...$args --cwd-file $tmp
    let cwd = (open $tmp)
    if $cwd != $env.PWD and ($cwd | path exists) {
        cd $cwd
    }
    rm -fp $tmp
}

# Write starship's init script to the autoload directory (loaded after config.nu).
mkdir ($nu.data-dir | path join "vendor/autoload")
starship init nu | save -f ($nu.data-dir | path join "vendor/autoload/starship.nu")
