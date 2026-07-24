tmux_call() {
  local tmux_command="$1" server="$2"
  shift 2

  if [ -n "$server" ]; then
    "$tmux_command" -L "$server" "$@"
  else
    "$tmux_command" "$@"
  fi
}

tmux_create_window() {
  local tmux_command="$1" server="$2" session="$3" name="$4" directory="$5"

  if tmux_call "$tmux_command" "$server" has-session -t "=$session" 2>/dev/null; then
    tmux_call "$tmux_command" "$server" new-window \
      -t "=$session" -n "$name" -c "$directory" -P -F '#{pane_id}'
  else
    tmux_call "$tmux_command" "$server" new-session \
      -d -x 240 -y 80 -s "$session" -n "$name" -c "$directory"
    tmux_call "$tmux_command" "$server" display-message \
      -t "$session:$name" -p '#{pane_id}'
  fi
}

tmux_make_quad_window() {
  local command="$1" server="$2" session="$3" name="$4" directory="$5"
  local top_left top_right bottom_left bottom_right pane title

  top_left="$(
    tmux_create_window "$command" "$server" "$session" "$name" "$directory"
  )"
  top_right="$(
    tmux_call "$command" "$server" split-window \
      -h -t "$top_left" -c "$directory" -P -F '#{pane_id}'
  )"
  bottom_left="$(
    tmux_call "$command" "$server" split-window \
      -v -t "$top_left" -c "$directory" -P -F '#{pane_id}'
  )"
  bottom_right="$(
    tmux_call "$command" "$server" split-window \
      -v -t "$top_right" -c "$directory" -P -F '#{pane_id}'
  )"

  title="${directory##*/}"
  for pane in "$top_left" "$top_right" "$bottom_left" "$bottom_right"; do
    tmux_call "$command" "$server" select-pane -t "$pane" -T "$title"
  done
  tmux_call "$command" "$server" \
    select-layout -t "$session:$name" tiled >/dev/null
}

tmux_make_grid_window() {
  local command="$1" server="$2" session="$3" name="$4" directory="$5"
  local left middle right bottom_left bottom_middle bottom_right pane title

  left="$(
    tmux_create_window "$command" "$server" "$session" "$name" "$directory"
  )"
  middle="$(
    tmux_call "$command" "$server" split-window \
      -h -p 66 -t "$left" -c "$directory" -P -F '#{pane_id}'
  )"
  right="$(
    tmux_call "$command" "$server" split-window \
      -h -p 50 -t "$middle" -c "$directory" -P -F '#{pane_id}'
  )"
  bottom_left="$(
    tmux_call "$command" "$server" split-window \
      -v -p 50 -t "$left" -c "$directory" -P -F '#{pane_id}'
  )"
  bottom_middle="$(
    tmux_call "$command" "$server" split-window \
      -v -p 50 -t "$middle" -c "$directory" -P -F '#{pane_id}'
  )"
  bottom_right="$(
    tmux_call "$command" "$server" split-window \
      -v -p 50 -t "$right" -c "$directory" -P -F '#{pane_id}'
  )"

  title="${directory##*/}"
  for pane in \
    "$left" \
    "$middle" \
    "$right" \
    "$bottom_left" \
    "$bottom_middle" \
    "$bottom_right"
  do
    tmux_call "$command" "$server" select-pane -t "$pane" -T "$title"
  done
}

tmux_make_mixed_quad_window() {
  local command="$1" server="$2" session="$3" name="$4"
  shift 4
  local directories=("$@")
  local top_left top_right bottom_left bottom_right
  local panes pane index

  [ "${#directories[@]}" -eq 4 ] || return 1

  top_left="$(
    tmux_create_window \
      "$command" "$server" "$session" "$name" "${directories[0]}"
  )"
  top_right="$(
    tmux_call "$command" "$server" split-window \
      -h -t "$top_left" -c "${directories[1]}" -P -F '#{pane_id}'
  )"
  bottom_left="$(
    tmux_call "$command" "$server" split-window \
      -v -t "$top_left" -c "${directories[2]}" -P -F '#{pane_id}'
  )"
  bottom_right="$(
    tmux_call "$command" "$server" split-window \
      -v -t "$top_right" -c "${directories[3]}" -P -F '#{pane_id}'
  )"

  panes=("$top_left" "$top_right" "$bottom_left" "$bottom_right")
  for index in 0 1 2 3; do
    pane="${panes[$index]}"
    tmux_call "$command" "$server" \
      select-pane -t "$pane" -T "${directories[$index]##*/}"
  done
  tmux_call "$command" "$server" \
    select-layout -t "$session:$name" tiled >/dev/null
}
