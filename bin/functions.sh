#!/usr/bin/env bash

# BSD stat has no version argument or reliable identifier
if stat --help 2>&1 | grep "usage: stat" >/dev/null; then
  stat_format_arg="-f"
  stat_mtime_spec="%m"
  stat_size_spec="%z"
  _sha512sum="shasum -a512"
else
  # GNU_STAT
  stat_format_arg="-c"
  stat_mtime_spec="%Y"
  stat_size_spec="%s"
  _sha512sum="sha512sum"
fi

function stat_mtime () {
  stat $stat_format_arg $stat_mtime_spec "$1" 2>/dev/null
}

function stat_size () {
  stat $stat_format_arg $stat_size_spec "$1" 2>/dev/null
}

function sha512sum() {
  # Can't figure out a better way of escaping $_sha512sum for use in a call than using sh -c
  sh -c "$_sha512sum $1|cut -d' ' -f1"
}

function escape_path() {
  r=$1
  if [[ "$host" == "Win32" ]]; then
    r=${r//\\/\\\\}
  fi
  echo "$r"
}

function unix_path() {
  p="$(escape_path "$1")"
  if [[ "$host" == "Win32" ]]; then
    p="$(cygpath -u "$p")"
    # cygpath doesn't escape spaces
    echo "${p//\ /\\ }"
    return
  fi
  echo "$p"
}

function native_path() {
  if [[ "$host" == "Win32" ]]; then
    p="$(cygpath -w "$1")"
    if [[ "$p" == *"\\ "* ]]; then
      # string contains escaped space, quote it and de-escape
      p="\"${p//\\ /\ }\""
    fi
    echo "$p"
    return
  fi
  echo "$1"
}

function quiet () {
  if [ -n "$VERBOSE" ]; then
    echo "$@"
    "$@"
  else
    "$@" > /dev/null 2>&1
  fi

  return $?
}

function die {
  local status=$1
  if (( status != 0 && status != 127 )); then
    for pid in "${pids[@]}"; do
      kill TERM $pid >/dev/null 2>&1
      kill -9 $pid >/dev/null 2>&1
      wait "$pid" 2>/dev/null
    done
    echo "$2 - please report (https://discord.gg/YPV32gKCsH)"
    exit 1
  fi
}

function onsignal () {
  local status=${1:-$?}
  for pid in "${pids[@]}"; do
    kill TERM $pid >/dev/null 2>&1
    kill -9 $pid >/dev/null 2>&1
  done
  exit $status
}

function set_cpu_cores() {
  if [[ -z "$CPU_CORES" ]]; then
    if [[ "Darwin" = "$(uname -s)" ]]; then
      CPU_CORES=$(sysctl -a | grep machdep.cpu.core_count | cut -f2 -d' ')
    else
      CPU_CORES=$(grep 'processor' /proc/cpuinfo | wc -l)
    fi
  fi

  echo $CPU_CORES
}

function host_os() {
  local host=""

  if [[ -n $1 ]]; then
    host=$1
  else
    host="$(uname -s)"
  fi

  if [[ "$host" = "Linux" ]]; then
    if [ -n "$WSL_DISTRO_NAME" ] || uname -r | grep 'Microsoft'; then
    echo "WSL is not supported."
    exit 1
    fi
  elif [[ "$host" == *"MINGW64_NT"* ]]; then
    host="Win32"
  elif [[ "$host" == *"MSYS_NT"* ]]; then
    host="Win32"
  fi

  echo "$host"
}

function host_arch() {
  uname -m | sed 's/aarch64/arm64/g'
}

function build_env_data() {
  echo "ANDROID_HOME=\"$(escape_path "$ANDROID_HOME")\""
  echo "JAVA_HOME=\"$(escape_path "$JAVA_HOME")\""
  echo "ANDROID_SDK_MANAGER=\"$(escape_path "$ANDROID_SDK_MANAGER")\""
  echo "GRADLE_HOME=\"$(escape_path "$GRADLE_HOME")\""
}

declare SSC_ENV_FILENAME=".ssc.env"

function read_env_data() {
  if [[ -f "$SSC_ENV_FILENAME" ]]; then
    source "$(abs_path "$SSC_ENV_FILENAME")"
  fi
}

function write_env_data() {
  # Maintain mtime on $SSC_ENV_FILENAME, only update if changed
  temp=$(mktemp)
  build_env_data > "$temp"
  SSC_ENV_FILENAME="$(abs_path "$SSC_ENV_FILENAME")"
  if [[ ! -f "$SSC_ENV_FILENAME" ]]; then
    mv "$temp" "$SSC_ENV_FILENAME"
  else
    old_hash=$(sha512sum "$SSC_ENV_FILENAME")
    new_hash=$(sha512sum "$temp")

    if [[ "$old_hash" != "$new_hash" ]]; then
      mv "$temp" "$SSC_ENV_FILENAME"
    else
      rm "$temp"
    fi
  fi
}

function prompt() {
  echo "$1"
  local return=$2
  # effectively reads into $2 by reference, rather than using echo to return which would prevent echo "$1" going to stdout
  eval "read -rp '> ' $return"
}

function prompt_yn() {
  prompt "$1 [y/N]" r
  local return=$2

  if [[ "$(lower "$r")" == "y" ]]; then
    return 0
  fi
  return 1
}

function prompt_new_path() {
  text="$1"
  default="$2"
  local return=$3
  local exists_message=$4
  input=""
  lf=$'\n'

  if [ -n "$2" ]; then
    echo "$text"
    if prompt_yn "Use suggested default path: ""$2""?"; then
      input="$2"
    fi
  fi

  while true; do
    if [ -z "$input" ]; then
      prompt "$text (Press Enter to go back)" input
    fi
    # remove any quote characters
    input=${input//\"/}
    unix_input="$(unix_path "$input")"
    if [ -e "$unix_input" ]; then
      if [ "$exists_message" == "!CAN_EXIST!" ]; then
        input="$(native_path "$(abs_path "$unix_input")")"
        eval "$return=$(escape_path "$input")"
        return 0
      fi

      unix_input="$(abs_path "$unix_input")"
      echo "\"$input\" already exists, please choose a new path."
      if [ -n "$exists_message" ]; then
        echo "$exists_message"
      fi
      input=""
    elif [ -z "$input" ]; then
      if prompt_yn "Cancel entering new path?"; then
        return
      fi
    else
      echo "Create: $unix_input"
      if ! mkdir -p "$unix_input"; then
        echo "Create $unix_input failed."
        input=""
      else
        input="$(native_path "$(abs_path "$unix_input")")"
        eval "$return=$(escape_path "$input")"
        return 0
      fi
    fi
  done
}

function abs_path() {
  test="$1"
  basename=""
  if [ -f "$1" ]; then
    test="$(dirname "$1")"
    basename="/$(basename "$1")"
  elif [ ! -e "$1" ]; then
    return 1
  fi

  p="$(sh -c "cd '$test'; pwd")$basename"
  # mingw sh returns incorrect escape slash if path contains spaces, swap / for \
  p="${p///\ /\\ }"
  echo "$p"
}

download_to_tmp() {
  uri=$1
  tmp="$(mktemp -d)"
  output=$tmp/"$(basename "$uri")"

  if [ -n "$SSC_ANDROID_REPO" ]; then
    echo >&2 cp "$SSC_ANDROID_REPO/$(basename "$uri")" "$output"
    cp "$SSC_ANDROID_REPO/$(basename "$uri")" "$output" || return $?
  else
    http_code=$(curl -L --write-out '%{http_code}' "$uri" --output "$output")
    # DONT COMMIT
    cp "$output" ..
    if  [ "$http_code" != "200" ] ; then
      echo "$http_code"
      rm -rf "$tmp"
      return 1
    fi
  fi
  echo "$output"
}

function unpack() {
  archive=$1
  dest=$2
  command=""

  if [[ "$archive" == *".tar.gz" ]]; then
    command="tar -xf"
  elif [[ "$archive" == *".gz" ]]; then
    command="gzip -d";
  elif [[ "$archive" == *".bz2" ]]; then
    command="bzip2 -d"
  elif [[ "$archive" == *".zip" ]]; then
    command="unzip"
  fi

  if ! cd "$dest"; then
    return $?
  fi

  $command "$archive"
  return 0
}

function get_top_level_archive_dir() {
  archive=$1
  command=""

  if [[ "$archive" == *".tar.gz" ]] || [[ "$archive" == *".tgz" ]]; then
    head=$(tar -tf "$archive" | head -n1)
    while [[ "$head" == *"/"* ]]; do
      head=$(dirname "$head")
    done
    echo "$head"
  elif [[ "$archive" == *".gz" ]] || [[ "$archive" == *".bz2" ]]; then
    "$(basename "${archive%.*}")"
  elif [[ "$archive" == *".bz2" ]]; then
    "$(basename "${archive%.*}")"
  elif [[ "$archive" == *".zip" ]]; then
    head=$(unzip -Z1 "$archive" | head -n1)
    echo "${head//\//}" # remove trailing slash
  fi

  return $?
}

function lower()
{
  echo "$1"|tr '[:upper:]' '[:lower:]'
}
