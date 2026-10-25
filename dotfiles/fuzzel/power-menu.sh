# Power menu. Opened from Ctrl+Alt+Delete in niri and from the power box in waybar.
# home/alin.nix turns this into the power-menu command

# Let the user pick one in fuzzel's dmenu mode and print the chosen line. Prints nothing when closed with Esc
pick() {
  local placeholder=$1
  shift
  printf '%s\n' "$@" | fuzzel --dmenu --only-match --placeholder="$placeholder" \
    --lines=$# --width=24 || true
}

# Logging out, rebooting, and shutting down lose unsaved work, so ask again
confirm() {
  [ "$(pick "$1?" "󰄬  Yes" "󰜺  No")" = "󰄬  Yes" ]
}

choice=$(pick Power "󰌾  Lock" "󰤄  Suspend" "󰍃  Logout" "󰜉  Reboot" "󰐥  Shutdown")

case $choice in
  # Go through swayidle's lock so it is not started twice (swayidle in home/alin.nix)
  *Lock) loginctl lock-session ;;
  # swayidle locks before sleeping
  *Suspend) systemctl suspend ;;
  *Logout) confirm Logout && niri msg action quit --skip-confirmation ;;
  *Reboot) confirm Reboot && systemctl reboot ;;
  *Shutdown) confirm Shutdown && systemctl poweroff ;;
esac
