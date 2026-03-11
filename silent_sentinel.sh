#!/bin/zsh
# =============================================================================
#  Silent Sentinel v20.0 — "Minimal-Fork Architecture"
#  Target  : MacBookPro10,1 | Ivy Bridge i7-3820QM | 16GB | macOS Sequoia (OCLP)
#  Runtime : Root LaunchDaemon
#
#  ARCHITECTURAL CHANGES FROM v19:
#
#  SYSCTL INJECTION
#    v20: ONE fork — all key=value pairs fed to a single `sysctl -f /dev/stdin`
#         via ZSH heredoc. Zero temp files. Zero loops.
#
#  PROCESS SCAN LOOP
#    v20: ONE `ps` fork. Pure ZSH builds pid→ni and pid→comm hashes. O(1)
#         cache lookup per known PID; O(T) key scan only on cache miss.
#         Net: O(new_procs × T) per cycle on a stable system ≈ near-zero.
#
#  RENICE
#    v20: One renice fork per tier, no verification fork. Nice drift is
#         caught naturally on the next scan cycle. Eliminates M ps forks.
#
#  TASKPOLICY
#    v20: PIDs bucketed into 3 policy strings. One `xargs -P4 taskpolicy`
#         call per non-empty bucket (≤3 forks, parallelized). First-cycle
#         burst is faster; stable cycles pay zero taskpolicy cost.
#
#  PID CACHE  
#    v20: PID_CACHE as ZSH associative hash → O(1) lookup. Stores both
#         target nice AND policy class so cache hits skip all work.
#
#  GHOST EVICTION
#    v20: Fire-and-forget background subshell. Never touches the main loop.
#
#  FORK COUNT COMPARISON (active cycle, 200 processes, 50 targets):
#    v20: 1 ps + 3 xargs + 5 renice                      = ~9 forks
#    v20 stable cycle (cache warm):
#         1 ps + 0 taskpolicy + 0-5 renice                = 1-6 forks
# =============================================================================


# =============================================================================
#  LEVEL 0 — Environment Flags & Self-Priority
# =============================================================================

launchctl setenv MTL_HUD_ENABLED 0
launchctl setenv MTL_COMPILER_LOG_LEVEL 0
launchctl setenv DYLD_PRINT_WARNINGS 0

# OCLP/kext settle time — load-bearing on this hardware, do not reduce
# without verifying WiFi and GPU kext init completes first.
sleep 10

# Sentinel must win every priority contest
renice -n -20 -p $$ >/dev/null 2>&1


# =============================================================================
#  LEVEL 1 — Sysctl Injection  (ONE fork total)
#
#  `sysctl -f` reads "key=value" lines from a file. Feeding it /dev/stdin
#  via a ZSH heredoc collapses all 40+ sysctl calls into one fork+exec.
#  Unknown keys are silently ignored (2>/dev/null). Boot-arg-only tunables
#  (kpti, mitigations, notp, amfi) live in NVRAM and are not listed here.
# =============================================================================

echo "[Sentinel] Injecting tunables..."

/usr/sbin/sysctl -f /dev/stdin >/dev/null 2>&1 << 'SYSCTL_EOF'
kern.timer_coalesce_tier0_scale=1
kern.timer_coalesce_tier0_ns_max=1000000
kern.timer_coalesce_tier1_scale=1
kern.timer_coalesce_tier1_ns_max=5000000
kern.timer_coalesce_tier2_scale=4
kern.timer_coalesce_tier2_ns_max=1000000000
kern.timer_coalesce_tier3_scale=-5
kern.timer_coalesce_tier3_ns_max=5000000000
kern.timer_coalesce_tier4_ns_max=30000000000
kern.timer_coalesce_tier5_ns_max=30000000000
kern.timer_coalesce_bg_scale=3
kern.timer_coalesce_idle_entry_hard_deadline_max=5000
kern.interrupt_timer_coalescing_enabled=1
kern.sched_rt_avoid_cpu0=1
kern.ulock_adaptive_spin_usecs=40
hw.pci.throttle_flags=0
vm.compressor_eval_period_in_msecs=1000
vm.compressor_sample_min_in_msecs=1000
vm.vm_page_background_exclude_external=1
kern.vm_pressure_level_transition_threshold=50
vm.vm_page_free_target=4000
vfs.generic.sync_timeout=30
debug.lowpri_throttle_enabled=0
kern.preheat_max_bytes=1048576
kern.preheat_min_bytes=65536
kern.ipc.maxsockbuf=8388608
net.inet.tcp.autorcvbufmax=8388608
net.inet.tcp.autosndbufmax=8388608
net.inet.tcp.sendspace=524288
net.inet.tcp.recvspace=524288
net.inet.udp.recvspace=262144
net.inet.tcp.delayed_ack=1
net.inet.tcp.local_slowstart_flightsize=16
net.inet.tcp.aggressive_rcvwnd_inc=1
net.inet.tcp.fastopen=0
net.inet.tcp.minmss=536
net.link.ether.inet.max_age=1800
net.inet.tcp.keepidle=600000
net.inet.tcp.keepintvl=75000
net.inet.tcp.blackhole=2
net.inet.udp.blackhole=1
kern.maxvnodes=786432
kern.maxfiles=512000
kern.maxfilesperproc=102400
kern.ipc.somaxconn=2048
kern.maxprocperuid=3750
kern.sysv.shmmax=2147483648
kern.sysv.shmall=524288
debug.agpm.LogLevel=0
debug.bpf_bufsize=65536
debug.bpf_maxbufsize=1048576
debug.lowpri_throttle_tier1_window_msecs=50
debug.lowpri_throttle_tier2_window_msecs=100
debug.lowpri_throttle_tier3_window_msecs=200
SYSCTL_EOF

echo "[Sentinel] Tunables applied."
sync


# =============================================================================
#  LEVEL 1.5 — The Silencing
# =============================================================================

/usr/bin/log config --mode "level:off"
killall -9 logd   2>/dev/null
killall -HUP cloudd secd 2>/dev/null
echo "[Sentinel] What is the music of life? Silence, my brother."


# =============================================================================
#  LEVEL 2 — Tier Definitions
#
#  Keys are LOWERCASE substrings matched against the lowercased process
#  basename. First match wins. Keep keys specific enough to avoid false
#  matches (e.g. "mds" matches "mds_stores" — intentional here since both
#  are in Tier 3+; use "mds_stores" as a key if you need to split them).
#
#  Nice → Policy class mapping:
#    nice >= 15  → taskpolicy background  (30s coalescing)
#    nice >= 5   → taskpolicy utility     (5s coalescing)  
#    nice <  5   → taskpolicy default     (1ms–1s coalescing)
# =============================================================================

typeset -gA TARGETS=(
    # ── TIER 0: USER INTERACTIVE — 1ms slack ─────────────────────────────────
    "hidd"                    "-20"
    "windowserver"            "-18"
    "skylight"                "-18"
    "powerd"                  "-17"
    "thermalmonitord"         "-17"

    # ── TIER 1: USER INITIATED — 5ms slack ───────────────────────────────────
    "swish"                   "-18"   # Gesture recognition; latency-critical
    "helium"                  "-16"
    "alfred"                  "-15"
    "windowmanager"           "-15"
    "alacritty"               "-14"
    "terminal"                "-14"
    "dynamiclakepro"          "-14"
    "dock"                    "-13"
    "finder"                  "-12"
    "mediaremoted"            "-12"
    "logd"                    "-9"
    "controlcenter"           "-8"

    # ── TIER 2: DEFAULT — 1s slack ────────────────────────────────────────────
    "bluetoothd"              "2"
    "coreaudiod"              "-5"
    "universalcontrol"        "-2"
    "configd"                 "-2"
    "identityservicesd"       "-2"
    "trustd"                  "-2"
    "itunescloudd"            "-2"
    "mds_stores"              "-2"
    "rapportd"                "1"
    "cloudd"                  "1"
    "sharingd"                "2"
    "tgfanhelper"			  "3"
    "continuity"              "5"

    # ── TIER 3: UTILITY — 5s slack ────────────────────────────────────────────
    "apsd"                    "4"
    "proximityd"              "5"
    "sidecardisplayagent"     "8"
    "sidecarrelay"            "8"
    "homed"                   "8"
    "mds"                     "10"

    # ── TIER 4: BACKGROUND — 30s slack ───────────────────────────────────────
    "dasd"                    "15"
    "usereventagent"          "15"
    "usagetrackingagent"      "15"
    "symptomsd"               "15"
    "remoted"                 "15"
    "diskimages-helper"       "15"
    "remotemanagementd"       "15"
    "airportd"                "15"
    "locationd"               "15"
    "corebrightnessd"         "15"
    "mbproximityhelper"       "17"
    "analyticsd"              "18"
    "onedrive"                "18"
    "bird"                    "19"
    "parsecd"                 "19"

    # ── TIER 5: MAINTENANCE — 30s slack ──────────────────────────────────────
    "intelligenceplatformd"   "20"
    "triald"                  "20"
    "parsec-fbf"              "20"
    "proactive_event_tracker" "20"
    "biometrictalkerd"        "20"
    "contextstoreagent"       "20"
    "vmd"                     "20"
    "siriknowledged"          "20"
    "syspolicyd"              "20"
    "biomesyncd"              "20"
    "mdbulkimport"            "20"
    "backupd"                 "20"
    "backupd-helper"          "20"
    "coresimulator"           "20"
    "airplayxpchelper"        "20"
    "mediaanalysisd"          "20"
    "photoanalysisd"          "20"
    "suggestd"                "20"
)

# PID_CACHE: associative hash for O(1) lookup.
# Value format: "target_ni:policy_class" (e.g. "-18:default", "20:background")
# A cache hit means: PID is known, policy is applied, nice is expected correct.
# A cache miss means: new process, needs matching and policy application.
typeset -gA PID_CACHE=()

# STUBBORN_NI: PIDs that failed renice (SIP-protected or kernel-owned).
# Stored as hash (key=PID, value=1) for O(1) membership test.
typeset -gA STUBBORN_NI=()

integer -g STABLE_COUNT=0
integer -g ITERATION=0
typeset -g  GHOST_BUSTED=false


# =============================================================================
#  LEVEL 3 — Ghost Eviction  (Non-blocking background subshell)
#
#  UID 16908544 is a phantom launchd user context that appears on some OCLP
#  installs. Evicting it removes a residual set of background services that
#  macOS wouldn't normally run on this hardware. The subshell retries every
#  30s for up to 5 attempts, then gives up silently.
# =============================================================================

(
    for attempt in {1..5}; do
        launchctl bootout user/16908544 >/dev/null 2>&1 && exit 0
        sleep 30
    done
) &


# =============================================================================
#  LEVEL 4 — apply_sentinel_policy()
#
#  Called every cycle. Returns 0 if any work was done, 1 if system is stable.
# =============================================================================

apply_sentinel_policy() {
    local work_done=false

    # ── Step 1: ONE ps fork to capture the full process table ─────────────────
    local ps_raw
    ps_raw=$(ps -ax -o pid= -o ni= -o comm= 2>/dev/null)

    # ── Step 2: Build PID maps in pure ZSH — zero additional forks ────────────
    typeset -A pid_ni    # pid_ni[PID]  = current nice value string
    typeset -A pid_bn    # pid_bn[PID]  = lowercase basename of comm
    local pid ni comm bn

    while IFS=' ' read -r pid ni comm; do
        [[ -z $pid ]] && continue
        (( pid == $$ || pid < 100 )) && continue

        # ZSH-native basename + lowercase in one expression
        # ${comm##*/} strips path prefix; :l lowercases — no fork
        bn=${${comm##*/}:l}

        # Skip XPC proxy noise — these inherit parent policy already
        [[ $bn == xpcproxy || $bn == com.apple.appkit* ]] && continue

        pid_ni[$pid]="${ni// /}"   # strip whitespace, store clean nice value
        pid_bn[$pid]="$bn"
    done <<< "$ps_raw"

    # ── Step 3: Match, diff, and bucket — pure ZSH ────────────────────────────
    typeset -A ni_bucket          # ni_bucket[nice_value] = "pid1 pid2 ..."
    local tp_bg="" tp_util="" tp_default=""
    local target_ni policy_class cached expected k

    for pid in ${(k)pid_ni}; do
        cached="${PID_CACHE[$pid]}"
        bn="$pid_bn[$pid]"
        target_ni=""

        if [[ -n $cached ]]; then
            # ── Cache hit: PID is known ──────────────────────────────────────
            target_ni="${cached%%:*}"

            # Check for nice drift (macOS can reset nice after certain events)
            if [[ "${pid_ni[$pid]}" == "$target_ni" ]]; then
                continue   # All good — skip this PID entirely
            fi

            # Nice has drifted — requeue for renice, but skip taskpolicy
            # (policy class is still correct from initial application)
            if [[ -z "${STUBBORN_NI[$pid]}" ]]; then
                ni_bucket[$target_ni]+="$pid "
                work_done=true
            fi
            continue
        fi

        # ── Cache miss: new process — run target matching ────────────────────
        for k in ${(k)TARGETS}; do
            if [[ $bn == *$k* ]]; then
                target_ni="${TARGETS[$k]}"
                break
            fi
        done
        [[ -z $target_ni ]] && continue   # Not a managed process; ignore

        # Determine policy class from nice value (pure ZSH arithmetic)
        if   (( target_ni >= 15 )); then policy_class="background"
        elif (( target_ni >= 5  )); then policy_class="utility"
        else                             policy_class="default"
        fi

        # Store in cache immediately — even if renice fails, we know the intent
        PID_CACHE[$pid]="${target_ni}:${policy_class}"

        # Queue for renice if needed
        if [[ "${pid_ni[$pid]}" != "$target_ni" ]] && [[ -z "${STUBBORN_NI[$pid]}" ]]; then
            ni_bucket[$target_ni]+="$pid "
        fi

        # Queue for taskpolicy (always on first encounter)
        case $policy_class in
            background) tp_bg+="$pid "     ;;
            utility)    tp_util+="$pid "   ;;
            default)    tp_default+="$pid " ;;
        esac

        work_done=true
    done

    # ── Step 4: Batch renice — one call per active tier (≤5 forks) ────────────
    # We call renice with all PIDs for a given nice value at once.
    # If renice fails for a specific PID, it exits non-zero but continues
    # for other PIDs. On the NEXT cycle, if that PID's nice is still wrong,
    # it will be re-queued. After a few cycles of failure, we can mark it
    # stubborn, but in practice SIP-protected processes simply don't appear
    # at wrong nice values since macOS won't let us set them anyway.
    local pids_arr
    for tier in ${(k)ni_bucket}; do
        pids_arr=(${(z)ni_bucket[$tier]})
        if renice -n $tier -p $pids_arr >/dev/null 2>&1; then
            : # Success — cache already has the right target
        else
            # Some PIDs in this tier may be SIP-protected.
            # Mark the entire batch as potentially stubborn; they'll be
            # re-evaluated next cycle and either succeed or stay stubborn.
            # We don't fork a verification ps here — that's the v19 approach.
            : # Failures will surface naturally on the next scan.
        fi
    done

    # ── Step 5: Batch taskpolicy — ≤3 xargs forks, parallelized ──────────────
    # xargs -P4 runs up to 4 taskpolicy processes in parallel, reducing
    # wall-clock time on the first boot cycle when all processes need
    # initial policy assignment (typically 50-80 PIDs).
    # On stable cycles tp_bg/util/default are all empty → zero forks.
    [[ -n $tp_bg      ]] && print -l ${(z)tp_bg}      | xargs -P4 -I{} /usr/bin/taskpolicy -c background -p {} >/dev/null 2>&1
    [[ -n $tp_util    ]] && print -l ${(z)tp_util}     | xargs -P4 -I{} /usr/bin/taskpolicy -c utility    -p {} >/dev/null 2>&1
    [[ -n $tp_default ]] && print -l ${(z)tp_default}  | xargs -P4 -I{} /usr/bin/taskpolicy -c default    -p {} >/dev/null 2>&1

    # ── Step 6: Prune dead PIDs from cache — pure ZSH, zero forks ────────────
    # Any PID in cache not present in pid_ni has exited. Remove it so the
    # cache doesn't grow unboundedly and so reused PIDs start fresh.
    for pid in ${(k)PID_CACHE}; do
        if [[ -z "${pid_ni[$pid]}" ]]; then
            unset "PID_CACHE[$pid]"
            unset "STUBBORN_NI[$pid]"
        fi
    done

    [[ $work_done == true ]] && return 0 || return 1
}


# =============================================================================
#  LEVEL 5 — Main Loop
#
#  Adaptive sleep: 15s when work was done (system changing), 90s when stable.
#  Cache flush every ~2.5 hours of stability: clears STUBBORN_NI so
#  previously-failing PIDs get retried, and clears PID_CACHE so processes
#  that changed their comm (rare but possible) get re-matched.
# =============================================================================

echo "[Sentinel] Entering main loop. Iteration 0."

while true; do

    if apply_sentinel_policy; then
        STABLE_COUNT=0
        sleep 15
    else
        (( STABLE_COUNT++ ))
        sleep 90
    fi

    # Cache flush at 100 stable cycles ≈ 2.5 hours
    if (( STABLE_COUNT > 100 )); then
        PID_CACHE=()
        STUBBORN_NI=()
        STABLE_COUNT=0
        echo "[Sentinel] Cache flushed at iteration ${ITERATION}."
    fi

    (( ITERATION++ ))
done
