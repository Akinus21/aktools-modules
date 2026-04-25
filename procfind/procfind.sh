#!/bin/bash

set -euo pipefail

# --- Color setup ---
RED=$(printf '\033[0;31m')
NC=$(printf '\033[0m')

# --- Script and install path ---
SCRIPT_NAME="procfind"
REAL_PATH="$(realpath "$0")"

# --- Parse options ---
FOLLOW=false
KILL_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f) FOLLOW=true; shift ;;
        -k|--kill) KILL_MODE=true; shift ;;
        -*) echo "❌ Invalid option: $1" >&2; exit 1 ;;
        *) PROCESS_NAME="$1"; shift; break ;;
    esac
done

# --- Require process name ---
if [ -z "${PROCESS_NAME:-}" ]; then
    echo "Usage: $SCRIPT_NAME [-f] [-k|--kill] <process-name>"
    exit 1
fi

# --- Function to collect process list ---
get_processes() {
    ps -eo pid,pcpu,pmem,comm,args |
    awk -v name="$PROCESS_NAME" '
        BEGIN { IGNORECASE=1 }
        NR==1 || ($0 ~ name && $0 !~ /awk/ && $0 !~ /procfind/ && $0 !~ /sed/)
    '
}

# --- Function to display filtered and highlighted processes ---
display_matches() {
    get_processes | sed -E "s/($PROCESS_NAME)/${RED}\1${NC}/Ig"
}

# --- Kill mode logic ---
if $KILL_MODE; then
    # Collect process list (skip header for numbering)
    mapfile -t PROCESSES < <(get_processes | tail -n +2)

    if [[ ${#PROCESSES[@]} -eq 0 ]]; then
        echo "No processes found for: $PROCESS_NAME"
        exit 0
    fi

    # Print numbered list with header
    HEADER=$(get_processes | head -n 1)
    echo "Processes matching \"$PROCESS_NAME\":"
    printf "%-4s %s\n" "#" "$HEADER"
    i=1
    for proc in "${PROCESSES[@]}"; do
        printf "%-4s %s\n" "$i" "$(echo "$proc" | sed -E "s/($PROCESS_NAME)/${RED}\1${NC}/Ig")"
        ((i++))
    done

    echo
    read -rp "Enter process number to kill (or 'A' to kill all): " choice

    if [[ "$choice" =~ ^[Aa]$ ]]; then
        echo "Killing all matching processes..."
        for proc in "${PROCESSES[@]}"; do
            PID=$(echo "$proc" | awk '{print $1}')
            kill "$PID" && echo "Killed PID $PID"
        done
    elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#PROCESSES[@]} )); then
        PID=$(echo "${PROCESSES[$((choice-1))]}" | awk '{print $1}')
        echo "Killing PID $PID..."
        kill "$PID" && echo "Killed PID $PID"
    else
        echo "Invalid choice."
        exit 1
    fi
    exit 0
fi

# --- Follow mode ---
if $FOLLOW; then
    while true; do
        clear
        echo "🔍 Monitoring process: $PROCESS_NAME"
        echo
        display_matches
        sleep 2
    done
else
    display_matches
fi
