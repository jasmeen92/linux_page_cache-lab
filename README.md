# Demand Paging Experiment

A hands-on experiment to observe **demand paging** — Linux's mechanism of deferring physical memory allocation until the moment a virtual page is actually accessed.

## Background

When a process calls `mmap()` with `MAP_PRIVATE | MAP_ANONYMOUS`, the kernel reserves a range in the process's **virtual address space** but does **not** allocate any physical memory. Physical pages are allocated lazily, one page at a time, only when the process reads from or writes to each page for the first time. This lazy allocation is called *demand paging*.

```
Virtual address space               Physical memory
┌──────────────────────┐            ┌──────────────┐
│  mmap() reserved     │  ←(no      │              │
│  (100 MiB)           │   mapping) │              │
│                      │            │              │
└──────────────────────┘            └──────────────┘

         ↓ first write to a page (page fault)

┌──────────────────────┐            ┌──────────────┐
│  mmap() reserved     │────────────▶  physical    │
│  (first page only)   │            │  page        │
└──────────────────────┘            └──────────────┘
```

This experiment makes the process visible step by step using a separate monitoring script.

## Files

| File | Description |
|---|---|
| `demand_paging.c` | Experiment program (reserve virtual memory, then write in chunks) |
| `monitor.sh` | Monitoring script that prints virtual/physical memory usage every second |

## How It Works

### `demand_paging.c`

1. **Step 1** — Calls `mmap()` to reserve 100 MiB of virtual address space.  
   Physical memory is **not** consumed at this point.
2. **Step 2** — Writes 10 MiB per second using `memset()`.  
   Each write triggers a **page fault**, and the OS maps a physical page to the corresponding virtual page.
3. **Step 3** — Calls `munmap()` to release all reserved memory.

Each step waits for the user to press **Enter**, allowing the monitor to capture the memory state before and after each transition.

### `monitor.sh`

- Reads `VmSize` (virtual memory size) and `VmRSS` (resident set size = physical memory in use) from `/proc/<PID>/status` once per second.
- Reads **minor and major page fault counts** from `/proc/<PID>/stat` and shows per-second delta (`MinFlt/s`) alongside running totals.
- If no PID is given, it searches for the `demand_paging` process automatically and waits until it appears.

| Column | Source | Description |
|---|---|---|
| `Virtual (MB)` | `VmSize` in `/proc/<PID>/status` | Total reserved virtual address space |
| `Physical (MB)` | `VmRSS` in `/proc/<PID>/status` | Physical pages currently resident in RAM |
| `MinFlt/s` | `minflt` in `/proc/<PID>/stat` | Minor page faults in the last second (no disk I/O) |
| `MinFlt(tot)` | `minflt` in `/proc/<PID>/stat` | Cumulative minor page faults since process start |
| `MajFlt(tot)` | `majflt` in `/proc/<PID>/stat` | Cumulative major page faults (disk I/O; normally 0) |

## Build

```bash
gcc -O0 -Wall -o demand_paging demand_paging.c
chmod +x monitor.sh
```

## Usage

Open **two terminals** in the same directory.

### Terminal 1 — Start the experiment

```bash
./demand_paging
```

The program prints its PID and waits at Step 1:

```
=== Linux Demand Paging Experiment ===
PID           : 12345
Virtual mem   : 100 MiB to reserve
Write chunk   : 10 MiB / sec

Run the following in another terminal to monitor memory usage:
  ./monitor.sh

[1] Reserving 100 MiB of virtual memory with mmap()... Press Enter
```

### Terminal 2 — Start monitoring

```bash
./monitor.sh
```

The script waits for the process to appear, then begins printing:

```
Sec     Virtual (MB)  Physical (MB)    MinFlt/s   MinFlt(tot)   MajFlt(tot)
------  ------------  ------------  ----------  ------------  ------------
0               4.28          0.86           8           312             0
```

### Step through the experiment

Press **Enter** in Terminal 1 to advance through each step and watch the monitor output change:

| Event | Virtual (MB) | Physical (MB) | MinFlt/s |
|---|---|---|---|
| Before `mmap()` | ~4 | ~0.9 | ~0 |
| After `mmap()` (before any write) | ~108 | ~0.9 ← no change | ~0 |
| After writing 10 MiB | ~108 | ~10.9 | ~2560 |
| After writing 20 MiB | ~108 | ~20.9 | ~2560 |
| … | … | … | … |
| After writing 100 MiB | ~108 | ~100.9 | ~2560 |
| After `munmap()` | ~4 | ~0.9 | ~0 |

 > **Why ~2560 faults per chunk?** Each chunk is 10 MiB = 10 × 1024 × 1024 bytes. With a 4096-byte page size, that is 10 × 1024 × 1024 / 4096 = **2560 pages**, each triggering one minor page fault.

**Key observation:** Virtual memory jumps immediately after `mmap()`, but physical memory and page fault counts only grow as data is written — one 10 MiB chunk at a time.

## Expected Output (Terminal 2)

```
Detected PID 12345. Starting monitoring.
Sec     Virtual (MB)  Physical (MB)    MinFlt/s   MinFlt(tot)   MajFlt(tot)
------  ------------  ------------  ----------  ------------  ------------
0               4.28          0.86           8           312             0  ← initial state
1               4.28          0.86           0           312             0
2             108.57          0.90          12           324             0  ← mmap() done, virtual +100 MB
3             108.57          0.90           0           324             0  ← physical unchanged, no faults
4             108.57         10.58        2560          2884             0  ← 10 MiB written, 2560 faults
5             108.57         20.90        2560          5444             0  ← 20 MiB written
6             108.57         31.22        2560          8004             0
...
14            108.57        100.90        2560         25604             0  ← all 100 MiB written
15            108.57        100.90           0         25604             0
16              4.28          0.90           0         25604             0  ← munmap() done, both drop
Process 12345 has exited. Stopping monitoring.
```

## Concepts Illustrated

| Concept | Where observed |
|---|---|
| **Demand paging** | Physical memory stays flat after `mmap()` until writes begin |
| **Minor page fault** | Each `memset()` causes ~2560 minor faults (one per 4 KiB page); visible in `MinFlt/s` |
| **Major page fault** | `MajFlt(tot)` stays 0 — no disk I/O needed for anonymous memory |
| **VmSize vs VmRSS** | VmSize = reserved virtual space; VmRSS = actually resident physical pages |
| **`munmap()` reclaim** | Both virtual and physical memory return to baseline after release |
