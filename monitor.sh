#!/bin/bash
#
# monitor.sh  [PID]
#
# Print the virtual and physical memory usage of the demand_paging process every second.
# If PID is omitted, the script searches for the demand_paging process automatically
# and waits until it starts.
# Reads VmSize (virtual) and VmRSS (physical) from /proc/<PID>/status.
# Reads minor/major page fault counts from /proc/<PID>/stat.
#

set -euo pipefail

PROCESS_NAME="demand_paging"

if [[ $# -ge 1 ]]; then
    # PID explicitly provided
    PID=$1
    if [[ ! -r "/proc/${PID}/status" ]]; then
        echo "Error: process with PID ${PID} not found." >&2
        exit 1
    fi
    echo "Using PID ${PID}."
else
    # No PID given: search for demand_paging and wait until it appears
    echo "Searching for '${PROCESS_NAME}' process..."
    while true; do
        PID=$(pgrep -x "$PROCESS_NAME" | head -n1 || true)
        if [[ -n "$PID" ]]; then
            echo "Detected PID ${PID}. Starting monitoring."
            break
        fi
        printf "\rWaiting... (not running yet - start ./demand_paging in another terminal)"
        sleep 1
    done
    echo ""
fi

STATUS="/proc/${PID}/status"
STAT="/proc/${PID}/stat"

# Read minflt and majflt from /proc/<PID>/stat.
# The stat file format is: pid (comm) state ... minflt(10) cminflt(11) majflt(12) ...
# The (comm) field may contain spaces, so we replace it before splitting.
get_page_faults() {
    awk '{
        gsub(/\([^)]*\)/, "X")   # replace (comm) with a single token
        print $10, $12            # minflt, majflt
    }' "$STAT"
}

# Print header
printf "%-6s  %12s  %12s  %10s  %12s  %12s\n" \
    "Sec" "Virtual (MB)" "Physical (MB)" "MinFlt/s" "MinFlt(tot)" "MajFlt(tot)"
printf "%-6s  %12s  %12s  %10s  %12s  %12s\n" \
    "------" "------------" "------------" "----------" "------------" "------------"

elapsed=0
prev_minflt=0
prev_majflt=0

while [[ -r "$STATUS" ]]; do
    vm_size=$(grep -m1 '^VmSize:' "$STATUS" | awk '{printf "%.2f", $2/1024}')
    vm_rss=$(grep  -m1 '^VmRSS:'  "$STATUS" | awk '{printf "%.2f", $2/1024}')

    read -r cur_minflt cur_majflt <<< "$(get_page_faults)"
    delta_min=$(( cur_minflt - prev_minflt ))
    delta_maj=$(( cur_majflt - prev_majflt ))
    prev_minflt=$cur_minflt
    prev_majflt=$cur_majflt

    printf "%-6d  %12s  %12s  %10d  %12d  %12d\n" \
        "$elapsed" "$vm_size" "$vm_rss" "$delta_min" "$cur_minflt" "$cur_majflt"

    sleep 1
    (( elapsed++ )) || true
done

echo ""
echo "Process ${PID} has exited. Stopping monitoring."
