#!/bin/sh

# Dependencies (Arch Linux): avahi, fzf, fd, vlc-cli,
# vlc-plugin-chromecast, vlc-plugin-ffmpeg, and vlc-plugin-x264.
# avahi-daemon must be running for Chromecast discovery.

cast() {
  if ! command -v avahi-browse >/dev/null 2>&1; then
    echo "cast: avahi-browse is required to discover Cast devices" >&2
    return 1
  fi
  if ! command -v fzf >/dev/null 2>&1; then
    echo "cast: fzf is required to select a device and file" >&2
    return 1
  fi
  if ! command -v cvlc >/dev/null 2>&1; then
    echo "cast: cvlc is required to stream media" >&2
    return 1
  fi

  local devices target media_file
  devices=$(
    avahi-browse --resolve --terminate --parsable _googlecast._tcp 2>/dev/null |
      sed 's/\\032/ /g' |
      awk -F ';' '$1 == "=" && $3 == "IPv4" && !seen[$8]++ { print $4 "\t" $8 }'
  )

  if [ -z "$devices" ]; then
    echo "cast: no Cast devices found" >&2
    return 1
  fi

  target=$(printf '%s\n' "$devices" |
    fzf --height=40% --reverse --prompt="Cast device: " --delimiter=$'\t' --with-nth=1,2) || return 1

  if [ "$#" -gt 1 ]; then
    echo "Usage: cast [file]" >&2
    return 1
  elif [ "$#" -eq 1 ]; then
    media_file=$1
  else
    if command -v fd >/dev/null 2>&1; then
      media_file=$(fd --type f --hidden --exclude .git 2>/dev/null |
        fzf --height=60% --reverse --prompt="Media file: ") || return 1
    else
      media_file=$(find . -type f -not -path '*/.git/*' 2>/dev/null |
        fzf --height=60% --reverse --prompt="Media file: ") || return 1
    fi
  fi

  if [ -z "$media_file" ] || [ ! -f "$media_file" ]; then
    echo "cast: file not found: $media_file" >&2
    return 1
  fi

  local target_ip
  target_ip=${target##*$'\t'}
  media_file=$(realpath -- "$media_file") || return 1
  echo "Casting $media_file to ${target%%$'\t'*} ($target_ip)"
  cvlc --no-spu --sout-chromecast-conversion-quality=2 \
    --sout "#chromecast{ip=$target_ip,port=8009,http-port=8011}" \
    --demux-filter=demux_chromecast --play-and-exit -- "$media_file"
}
