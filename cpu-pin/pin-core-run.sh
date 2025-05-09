#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
  echo "Must be run as root" >&2
  exit 1
fi
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <core> <program> [args...]" >&2
  exit 1
fi

ISO_CORE="$1"; shift
PROGRAM=( "$@" )
CGROOT=/sys/fs/cgroup

cleanup(){
  echo "Cleaning up cgroups…"
  for cg in iso sys; do
    if [[ -d "$CGROOT/$cg" ]]; then
      while read -r pid; do
        [[ -z "$pid" ]] && continue
        echo "$pid" > "$CGROOT"/cgroup.procs 2>/dev/null || true
      done < "$CGROOT/$cg"/cgroup.procs
      rmdir "$CGROOT/$cg" || true
    fi
  done
}
trap cleanup EXIT SIGINT SIGTERM

if ! mountpoint -q -t cgroup2 "$CGROOT"; then
  mount -t cgroup2 none "$CGROOT"
fi

echo "+cpuset +cpu" > "$CGROOT"/cgroup.subtree_control

mkdir -p "$CGROOT"/iso "$CGROOT"/sys

ROOT_MEMS=$(< "$CGROOT"/cpuset.mems)
for cg in iso sys; do
  echo "$ROOT_MEMS" > "$CGROOT/$cg"/cpuset.mems
done

TOTAL=$(nproc --all)
echo "$ISO_CORE" > "$CGROOT/iso"/cpuset.cpus
SYS_LIST=()
for ((i=0; i < TOTAL; i++)); do
  [[ $i -eq $ISO_CORE ]] && continue
  SYS_LIST+=("$i")
done
( IFS=,; echo "${SYS_LIST[*]}" ) > "$CGROOT/sys"/cpuset.cpus

SELF=$$
while read -r pid; do
  [[ $pid -eq $SELF ]] && continue
  echo "$pid" > "$CGROOT/sys"/cgroup.procs 2>/dev/null || true
done < "$CGROOT"/cgroup.procs

echo $$ > "$CGROOT/iso"/cgroup.procs

"${PROGRAM[@]}"
