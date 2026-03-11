# 🚀 macOS Sequoia "Invictus" Master Knowledge Base (v18)

* **Target:** 2012 MacBook Pro Retina 15" (MBP 10,1) | i7-3820QM | 16GB LPDDR3 RAM | Intel HD4000 iGPU/ Nvidia GT 650M dGPU
* **Hardware Specs:** 2TB mSATA SSD | 1TB SD Card | 15% Unpartitioned SSD Scratchpad
* **Toolchain:** Fish Shell • Micro Editor • Eza (ls replacement)
* **Philosophy:** Digital Silence • Silicon-Lite Architecture • Interrupt Alignment
* **Updated:** March 2026

---

### 🛠️ 1. Hardware, Thermal & Physical Architecture
- **Thermal Interface:** Honeywell PTM7950 Phase-Change on CPU/GPU and auxilliary heatsinks; verified stable thermal cycling.
- **Airflow Geometry (The "Shingling" Mod):**
    - **Sealed Pressure Tunnel:** 4-side bridge between fan housing and radiator fin-stacks using high-rigidity copper tape and sugru.
    - **Logic:** Eliminates internal chassis recirculation; forces maximum fan static pressure through the radiator fins.
    - **Result:** Sustained +200MHz clock increase at identical thermal ceiling (105°C).
- **Physical Modification (Passive Oxidation):**
        - **Target:** High-Emissivity ($\varepsilon \approx 0.70–0.75$) naturally grown Cupric Oxide ($CuO$) layer on all raw copper pipes and auxiliary sinks.
        - **Protocol:** 99% IPA de-masking followed by heat cycling to accelerate $CuO$ formation without increasing material thickness or thermal resistance ($R_{thermal}$).
        - **Logic:** Enhances radiative cooling into the aluminum chassis/top-case bridge; stabilizes 3.2GHz "Mobile" floor and reduces PECI recovery time.
- **Passive Mass:** VRM (2.0mm thick copper block grid pattern heatsinks) drilled to allow airflow through them, and bridged to bottom case via Arctic TP-3 thermal pads. Provides ~35% performance uplift during saturation.
- **Intake Optimization:** Custom drilled bottom-case intake arrays aligned with fan hubs for direct atmospheric access via IETS GT600 high-pressure docking.
- **Fan Logic (TG Pro):** 8s Polling / 16s Smoothing. Left fan leads Right by 3–5% for harmonic cancellation.
- **Acoustics:** 36 dB (Idle) / 47 dB (Internal Max) / 65 dB (GT600 Docked Max).

---

## ⚙️ 2. Core OS & Kernel Framework
- **System Integrity:**
    - **SIP Disabled:** Enforced via `<data>fwg=</data>` (0x807F) to allow Sentinel process prioritization.
    - **Security Bypass:** `amfi=0x80` (Surgical mode) maintained to reduce background verification loops while maintaining OCLP driver compatibility.
    - **Thermal Polling:** `notp` (No Thermal Pressure) boot-arg enforced. Disables high-frequency kernel polling of the SMC; eliminates constant "Thermal Level" interrupts.
    - **Performance Floor:** `mitigations=0` and `kpti=0` to eliminate Meltdown/Spectre performance tax on Ivy Bridge silicon.
    - **Background Throttling:** `dasd`, `spotlightknowledged`, and `mds` are throttled via Sentinel loop to eliminate CPU micro-spikes.
- **NVRAM Configuration:**
    - **Boot-Args:** `amfi=0x80 kpti=0 mitigations=0 ncl=131072 alcid=1 ipc_control_port_options=0 no_vhentropy=1 -lilubetaall -nokcmismatchpanic -no_auto_rebuild`
    - **Persistence:** `nvram SystemAudioVolume=%80` set to prevent NVRAM writes; `WriteFlash=False` enforced to preserve physical chip longevity and ensure a "Stateless" boot environment.
- **Memory Model:**
    - `vm.vm_page_background_exclude_external=1` to reduce vnode jitter and active page eviction.
- **Networking Logic:**
    - **TCP/IP:** Delayed ACK=1. ECN/L4S/RACK disabled for Legacy WiFi stability.
    - **Buffers:** `maxsockbuf` expanded to 8MB; auto-buffers capped to prevent memory pressure.
    - **Scaling:** `ncl=131072` (Network Cluster Limit) optimized for high-speed I/O.
- **Interrupt Coalescing:**
    - **Tier 0 (Interactive):** 5ms ($5\times 10^6\text{ns}$) slack for UI tasks (Scale: 1).
    - **Tier 1 (Active):** 5ms ($5\times 10^6\text{ns}$) slack, aligned with Tier 0 (Scale: 1).
    - **Tier 2 (Default):** 100ms ($100\times 10^6\text{ns}$) slack, moderate batching (Scale: 4).
    - **Tier 3 (Background):** 250ms ($250\times 10^6\text{ns}$) slack for suppression (Scale: -5).
    - **Tier 4/5 (Maintenance):** 30s ($30\times 10^9\text{ns}$) slack for extreme batching (Scale: -15).
- **I/O Latency:**
    - `vfs.generic.sync_timeout=20`: Extended 20s Write-Back delay for SSD longevity.
    - `debug.lowpri_throttle_enabled=0`: Disables default background task choking.
    - **I/O Throttle Windows:**
        - `Tier 1`: 5ms ($15\text{ms}$ SSD) window for active I/O.
        - `Tier 2`: 85ms ($15\text{ms}$ SSD) window for default I/O.
        - `Tier 3`: 200ms ($25\text{ms}$ SSD) window for background I/O.
- **Process Management:**
    - PID-specific `taskpolicy` enforcement on all Tier 4 & 5 processes to mimic Efficiency Core behavior on the i7-3820QM.

---

## 🧠 3. Priority & Interrupt Engine
### The Silent Sentinel (`silent_sentinel.sh`)
- **Logic:** Atomic Zsh-native engine, combining Sysctl injection, and Adaptive Process Watchdog. Runs itself at Nice -20 with `renice` batching.
- **Tier 1 (Hardware/UI Critical):** `hidd` (-20), `WindowServer` (-18), `SkyLight` (-17), `bluetoothd` (-19), `coreaudiod` (-16), `powerd` (-16).
- **Tier 2 (Interactive User):** `WindowManager` (-18), `Alfred` (-15), `Terminal` (-14), `DynamicLakePro` (-14), `logd` (-9), `Dock` (-13), `Finder` (-12).
- **Tier 4 (Throttle):** `mds`, `backupd`, `cloudd`, `intelligenceplatformd`, `siriknowledged`, `syspolicyd`.
- **Tier 5 (Background Leeches):** `triald`, `parsec-fbf`, `analyticsd`, `biometrictalkerd`, `vmd`, `symptomsd`, `remoted`, `parsecd`, `biomesyncd`.
    - **Action:** `renice` batching + `taskpolicy -c background`. Persistent RAM blacklists (`STUBBORN_NI`/`TP`) prevent redundant syscalls to SIP-protected processes.
- **Ghost Mitigation:** Automatic `bootout` of UID `16908544` after initial stability check.
- **Adaptive Interval:** 15s (Active Shift) / 90s (Stable State) / 2.5hr (Cache Flush).

---

## 🛡️ 4. Silicon-Lite & "Ghost" Suppression
- **Intelligence & Proactive (Disabled):**
    - `intelligenceplatformd`, `intelligencecontextd`, `knowledge-agent`, `knowledgeconstructiond`.
    - `proactived`, `proactiveeventtrackerd`, `siriinferenced`, `siriknowledged`.
    - `suggestd`, `ospredictiond`, `biomesyncd`, `BiomeAgent`.
- **Hardware Ghosts & Apple Silicon Cruft (Disabled):**
    - **Camera Stubbing:** `appleh13` through `appleh16camerad` (Removes driver polling for non-existent T2/M-series ISP).
    - **Mobile/Biometric:** `nfcd`, `biometrickitd`, `touchbarserver`, `geod`, `geoanalyticsd`, `mbproximityhelper`.
    - **Translation Layer:** `oahd` (Rosetta 2 background daemon—unnecessary on native Intel).
- **Telemetry & Logging (Hard-Disabled):**
    - `analyticsd`, `osanalyticshelper`, `symptomsd` (Network/GUI).
    - `tailspind`, `spindump`, `systemstatsd`, `powerlogHelperd`.
    - `ReportCrash`, `ReportCrash.Root`, `diagnosed`.
- **ACPI "INVICTUS" Architecture:**
    - **SSDT-INVICTUS.aml:** Custom address-space targeting for Ivy Bridge mobile platform (MBP 10,1).
    - **Host Bridge:** `MCHC` (00:00.0) forced to 32-bit addressing cap via `_DSM` to reduce bus-mastering discovery overhead.
    - **Ghost Bridges:** Suppression of `00:01.1` and `00:01.2` (unused PCIe bridges) via `_STA=0` to prevent redundant kernel probing.
- **Interrupt Alignment:**
    - **SMC (Vector 0x46):** Reduced to ~13.8 interrupts/sec via `notp` (Previously ~25+).
    - **IGPU (Vector 0x7b):** Primary remaining wake-source (~64 interrupts/sec); mitigated by static UI and 50% brightness floor.
    - **Bluetooth Noise:** `bluetoothd` identified as high-WPS "leech" (19–25 WPS). Recommend hardware-toggle **OFF** when not in active use to achieve sub-4.3W floor.
- **Sleep Integrity:** "Wake for Network Access" set to NEVER (Prevents OCLP WiFi DarkWakes).
- **AirPlay XPCHelper:** Forced `bootout` from system domain; eliminates constant encoder-ready polling.
- **Battery Monitoring:**
    - **App:** `Stats` (Open Source)
    - **Logic:** Configured for extreme efficiency (1-minute polling interval).
    - **Exclusion:** Added to `silent_sentinel.sh` watchdog exception list to prevent `renice` loops from affecting the UI thread.

---

## 🖥️ 5. Visual Efficiency — “Digital Silence”
- **UI Redraws:** Static wallpaper, Reduced Transparency, Zero widgets, Shadows disabled.
- **DynamicLakePro Muting:** `muiscWavemodeKey=0`, `showSecondesDefKey=0` (Eliminates 1Hz wake).
- **Sensor Muting:** `dAuto=0`, `kAuto=0` (Stops `AppleLMUController` polling; forces static brightness).
- **Widget Suppression:** `com.apple.widgets.extension-vending` disabled via `launchctl` (removes all widget-related process forks).
- **Sidecar/Continuity:** `sidecardisplayagent` and `sidecarrelay` disabled via `launchctl` (cuts networking/encoder polling).

---

## 🚀 6. Boot Automation (`launchd`)
- **Master Sentinel Service:** `/Library/LaunchDaemons/com.invictus.sentinel.plist`
    - **Logic:** Runs a single, consolidated script (`silent_sentinel.sh`) at boot.
    - **Persistent Phase:** `KeepAlive` ensures the script restarts if killed, maintaining the adaptive process watchdog loop indefinitely.
    - **Logging:** Standard out/error redirected to `/var/log/sentinel.log` for debugging watchdog behavior.

---

### 📊 7. Performance Benchmarks
| Metric | Target | Observed | Notes |
| :--- | :--- | :--- | :--- |
| **Heaven 4.0 (Mobile)**| > 750 | **945** | 720p Basic. 60 Min Heat Soak baseline. 66°C GPU temp |
| **Cinebench R23 (Mobile)** | > 3,000 | **3,3385** | Sustained 3.2–3.3GHz on battery. |
| **Cinebench R23 (Docked)** | > 3,400 | **3,539** | With GT600 Fan (3.4-3.5GHz). |
| **3DMark Fire Strike (Docked)** | > 1800 | **2,085** | Verified World Record (MBP 10,1). |
| **GPU Temp (Peak Load)** | < 75°C | **66°C** | 15°C reduction vs. original heatsink. |
| **CPU Idle (PECI)** | < 50°C | **40°C** | Sub-5W floor reached consistently. |
| **Idle Package Power** | < 4.5W | 4.03–5.23W | 4.31W Avg. |
| **C7 Residency** | > 90% | 95.51% | Idle state efficiency. |
| **Wakes Per Second** | < 190 | 179.8 – 184.6 | System interrupt suppression check. |
| **Idle Load** | < 0.70 | 0.53 | `top` command metric. |
| **Speedometer 3.0** | > 11.0 | 12.3 | Browser performance. |
