# Linux OS Fundamentals Lab Series

> **Inspired by:**
> - [IITD OS NPTEL Course](https://iitd-os.github.io/os-nptel/) — Prof. Sorav Bansal, IIT Delhi
> - [CSE IITD OS Course](https://www.cse.iitd.ac.in/~sbansal/os/) — Lecture notes, assignments, and xv6 labs
>
> Labs are designed as per the **current industry paradigm shift in virtualisation, containers, and multi-core systems**.
> This course lays an excellent foundation to pursue containers, Kubernetes, and system design at scale.

**Author:** Arun Singh | arunsingh.in@gmail.com
**Based on:** Prof. Sorav Bansal, NPTEL, IIT Delhi — Operating Systems lecture series
**Kernel target:** Linux 6.x (tested on Ubuntu 22.04+, Debian 12+)

A hands-on lab pack covering all 40 topics of a complete Operating Systems course — from threads and address spaces through to GPU datacentre OS internals. Each lab is a self-contained C program you compile, run, observe, and quiz yourself on.

The same kernel subsystems you study here — virtual memory, the scheduler, VFS, locking, namespaces — are the building blocks of every container runtime (Docker, containerd), every orchestrator (Kubernetes), and every high-performance distributed system (NCCL, DPDK, io_uring). Understanding them at the source level separates engineers who configure systems from those who debug, optimise, and design them.

---

## Why This Repo

Modern Linux kernels (6.1–6.12) power everything from a Raspberry Pi to an NVIDIA DGX H100 cluster. The same subsystems — virtual memory, scheduler, VFS, locking — appear in cloud VMs, containers, and GPU training jobs. This lab series builds the mental model to read kernel source, debug production issues, and answer senior systems-engineering interview questions with confidence.

---

## Quick Start

```bash
git clone https://github.com/arunsingh/linux_page_cache-lab.git
cd linux_page_caching
./scripts/build_all.sh
./scripts/run_lab.sh          # list available labs
./scripts/run_lab.sh 8        # paging intro
./scripts/run_lab.sh 27       # demand paging (interactive — open monitor in 2nd terminal)
```

For Lab 27, open a second terminal:

```bash
./scripts/monitor.sh <PID>
```

---

## System Requirements

| | Minimum | Recommended |
|---|---|---|
| OS | Linux (any distro) | Ubuntu 22.04+ / Debian 12+ |
| Kernel | 5.15 | 6.1+ (MGLRU, io_uring v3, EEVDF scheduler) |
| RAM | 4 GB | 8 GB |
| CPU | 2 cores | 4+ cores |
| Tools | gcc, bash | gcc, gdb, strace, perf, numactl |

> **macOS note:** Labs 01, 05, 06, 11, 16, 17, 19, 25, 34, 35, 40 use Linux-only APIs (gettid, MAP_HUGETLB, cpu_set_t). All others build and run on macOS for study.

---

## Repo Layout

```
demand-paging-experiment/
├── labs/
│   ├── lab_01_threads_addr_fs.c    Labs 01–40 source
│   ├── ...
│   ├── lab_40_gpu_os.c
│   ├── demand_paging.c             Lab 27 extended interactive version
│   ├── page_cache_models.c         Page cache model comparison
│   └── process_memory_exercises.c  Deep-dive: process and memory subsystems
├── scripts/
│   ├── build_all.sh                Build all labs to bin/
│   ├── run_lab.sh                  Run lab by number
│   ├── monitor.sh                  Live /proc monitor (use alongside lab 27)
│   ├── build.sh
│   ├── run_demand_paging_lab.sh
│   ├── run_page_cache_lab.sh
│   └── setup_testdata.sh
├── steps/
├── answers/
├── scorecards/
└── assets/
```

---

## Lab Index — All 40 Topics

Each entry: topic · source file · run command · what to observe · why it matters · quiz focus

---

### Lab 01 — Threads, Address Spaces, Filesystem Devices

**File:** labs/lab_01_threads_addr_fs.c | **Run:** ./scripts/run_lab.sh 1

**What to observe:**

```
Thread 0: PID=12345, TID=12346
Thread 0: &shared_global=0x601060  (same address across all threads)
Child:  test_var=999 (modified)
Parent: test_var=500 (unchanged — COW isolation)
```

**Why:** clone(CLONE_VM) shares the mm_struct; threads see one virtual address space. fork() duplicates it with copy-on-write — child modification only affects its own physical pages.

**Exercise:**
1. Count anonymous VMAs: `cat /proc/<pid>/maps | grep -c anon` before and after spawning 4 threads. Each thread adds ~2 VMAs (stack + TLS).
2. Docker: `docker run --memory=64m` then malloc more than 64 MiB — observe cgroup OOM kill.

**Quiz focus:** thread vs process isolation, COW, [vdso] mapping, character vs block device, TLS via %fs, cgroups v2 memory.max

---

### Lab 02 — PC Architecture

**File:** labs/lab_02_pc_arch.c | **Run:** ./scripts/run_lab.sh 2

**What to observe:**

```
/proc/cpuinfo flags: sse4_2 avx2 avx512f pae lm hypervisor
/proc/iomem:
  00000000-0009ffff : System RAM
  fe000000-ffffffff : PCI Bus 0000:00   (MMIO window)
```

**Why:** MMIO regions are carved out of physical address space so device registers can be accessed with ordinary load/store instructions. On a DGX H100 node, PCIe BAR windows for 8 H100 GPUs consume ~64 GB of address space.

**Exercise:** Find the PCI MMIO window size in /proc/iomem. Compare on a VM vs bare metal — virtio devices show instead of physical PCI.

**Quiz focus:** MMIO vs port I/O, APIC, PCIe Gen5 bandwidth (128 GB/s bidirectional), NVMe multi-queue, NUMA node topology

---

### Lab 03 — x86 Instruction Set, GCC Calling Conventions

**File:** labs/lab_03_x86_calling.c | **Run:** ./scripts/run_lab.sh 3

**What to observe:**

```
Arg 1 -> rdi   Arg 2 -> rsi   Arg 3 -> rdx
Arg 4 -> rcx   Arg 5 -> r8    Arg 6 -> r9   Arg 7+ -> stack
Return value -> rax
Callee-saved: rbx, rbp, r12-r15
```

**Why:** The System V AMD64 ABI governs every Linux binary. Understanding it lets you read objdump output and interpret gdb backtraces without source code.

**Exercise:** Write a 4-argument function, compile with -O0, run `objdump -d bin/lab_03` and verify each argument in the expected register. Recompile with -O2 — frame pointer disappears.

**Quiz focus:** red zone (128 bytes below RSP), 16-byte stack alignment before call, ARM64 ABI (x0–x7), variadic args, callee vs caller-saved

---

### Lab 04 — Physical Memory Map, I/O, Segmentation

**File:** labs/lab_04_phys_mem_io.c | **Run:** ./scripts/run_lab.sh 4

**What to observe:**

```
/proc/meminfo:  MemTotal: 16384 MB   MemFree: 8192 MB   Cached: 4096 MB
/proc/zoneinfo: zones DMA / DMA32 / Normal / Movable
/proc/buddyinfo: free pages per order (4K to 4M blocks)
```

**Why:** Physical memory is split into zones because legacy devices can only DMA into addresses below 4 GB (DMA32 zone). HBM in H100 GPUs provides 3.35 TB/s bandwidth but only 80 GB capacity per card.

**Exercise:** Read /proc/buddyinfo before and after `malloc(64<<20)`. Observe which orders are consumed. Use `numactl --membind=1 ./bin/lab_04` and compare allocation latency on a NUMA machine.

**Quiz focus:** NUMA node distance, memory zones, buddy allocator fragmentation, HBM vs DDR5, DMA coherence, ZONE_MOVABLE for hotplug

---

### Lab 05 — Segmentation, Trap Handling

**File:** labs/lab_05_segmentation_traps.c | **Run:** ./scripts/run_lab.sh 5 (Linux only)

**What to observe:**

```
Signal handler caught SIGSEGV at address: 0x0000000000000000
si_addr = NULL  (null pointer dereference)
Recovered successfully.
```

**Why:** The MMU raises #PF (page fault, vector 14) when a PTE is not present or a privilege check fails. KPTI (Meltdown fix) keeps kernel mappings absent from user-mode page tables — adds ~100 ns per syscall on pre-Cascade Lake CPUs.

**Exercise:** Install a SIGSEGV handler that prints si_addr, dereference an unmapped address, recover via mprotect. Run `perf stat -e page-faults ./bin/lab_05`.

**Quiz focus:** segfault vs bus error (SIGBUS), KPTI overhead, Meltdown model, signal handler stack frame, sigreturn syscall, ulimit -c for core dumps

---

### Lab 06 — Traps, Trap Handlers

**File:** labs/lab_06_trap_handlers.c | **Run:** ./scripts/run_lab.sh 6 (Linux only)

**What to observe:**

```
strace -c ./bin/lab_06 shows syscall types and counts
Signal delivery: kernel saves user context on signal stack, jumps to handler
SA_SIGINFO gives siginfo_t with faulting address, fault code
```

**Why:** Traps are synchronous CPU exceptions (#DE divide-by-zero, #PF page fault, #BP breakpoint). The IDT maps each vector to a kernel handler. System calls use the syscall instruction for a ring 3 to ring 0 transition.

**Exercise:** `strace -e trace=signal ./bin/lab_06` to observe signal mechanics. Add `__asm__("int3")` and handle SIGTRAP — this is how gdb implements software breakpoints.

**Quiz focus:** IDT, trap vs interrupt vs exception, syscall instruction vs int 0x80, vDSO fast-path syscalls, SGX enclave exception handling

---

### Lab 07 — Kernel Data Structures, Memory Management

**File:** labs/lab_07_kernel_ds_mm.c | **Run:** ./scripts/run_lab.sh 7

**What to observe:**

```
/proc/buddyinfo: free pages per order per zone
/proc/self/status: VmPTE: 128 kB  (page table memory used)
slabtop: SLUB cache hit rates per slab type
```

**Why:** Linux uses SLUB (default since 2.6.23) for sub-page allocations — groups same-sized objects per CPU to eliminate lock contention. task_struct (~10 KB in Linux 6.x) lives in its own slab.

**Exercise:** Fork 50 children and watch `/proc/slabinfo | grep task_struct`. The active_objs count increases by 50. Each process costs ~9–10 KB for its PCB alone.

**Quiz focus:** SLUB vs SLAB vs SLOB, kmalloc vs vmalloc, task_struct size, buddy allocator fragmentation, kcompactd memory compaction

---

### Lab 08 — Segmentation Review, Introduction to Paging

**File:** labs/lab_08_paging_intro.c | **Run:** ./scripts/run_lab.sh 8

**What to observe:**

```
System page size: 4096 bytes (4 KiB)
Virtual Address layout (48-bit x86_64):
  PML4[9] | PDP[9] | PD[9] | PT[9] | Offset[12]
  512 entries per level  ->  256 TiB addressable space
sudo ./bin/lab_08: real PFNs visible in /proc/self/pagemap
```

**Why:** Paging eliminates external fragmentation by mapping fixed-size virtual pages to any physical frame. x86_64 servers with more than 128 TiB RAM use 5-level paging (LA57, Linux 4.14+): 57-bit virtual address = 128 PiB addressable.

**Exercise:** Run `sudo ./bin/lab_08` to read real PFNs. Compute physical addresses: `PFN * 4096 + offset`. Confirm stack and heap frames are non-contiguous in physical memory.

**Quiz focus:** 4-level vs 5-level page table walk, PFN, /proc/self/pagemap security, page table memory cost per process

---

### Lab 09 — Paging (Deep Dive)

**File:** labs/lab_09_paging_deep.c | **Run:** ./scripts/run_lab.sh 9

**What to observe:**

```
After mmap(16 MiB):    minor_faults=3    (metadata only)
After memset(16 MiB):  minor_faults=4096 (one per 4 KiB page)
After 2nd memset:      minor_faults=0    (pages already present)
smaps: Rss=16384 kB    Anonymous=16384 kB
```

**Why:** The first write to each anonymous page triggers a minor fault. The kernel allocates a zeroed physical frame, installs the PTE, and returns. madvise(MADV_DONTNEED) marks pages reclaimable without unmapping — used by jemalloc to return memory to the OS.

**Exercise:** After memset, call `madvise(p, sz, MADV_DONTNEED)`. Read VmRSS from /proc/self/status before and after — observe the drop without munmap.

**Quiz focus:** PTE flags (P, R/W, U/S, Accessed, Dirty, NX), COW implementation, PSS vs RSS for shared libraries, userfaultfd for live VM migration

---

### Lab 10 — Process Address Spaces Using Paging

**File:** labs/lab_10_addr_space_paging.c | **Run:** ./scripts/run_lab.sh 10

**What to observe:**

```
/proc/self/maps (typical layout):
  5555... r-xp  text (code)
  5555... r--p  rodata (read-only data)
  5555... rw-p  data + BSS
  7fff... rw-p  [stack]
  7f80... rw-p  [heap or mmap region]
```

**Why:** Each vm_area_struct covers a contiguous virtual range. Adjacent compatible VMAs are merged by vma_merge(). ML runtimes and JVMs can create thousands of VMAs — vm.max_map_count (default 65530) limits this.

**Exercise:** `dlopen()` a shared library. Count VMAs before and after with `wc -l /proc/self/maps`. Each .so adds 3–4 VMAs. Compare a Python 3 interpreter's VMA count — can exceed 500.

**Quiz focus:** vm_area_struct, VMA merging, MAP_FIXED dangers, vm.max_map_count for ML frameworks, mlock for real-time

---

### Lab 11 — TLB, Large Pages, Boot Sector

**File:** labs/lab_11_tlb_hugepages.c | **Run:** ./scripts/run_lab.sh 11 (Linux only)

**What to observe:**

```
Sequential 4K-stride (256 MiB): 0.12s   (prefetcher warm)
Random     4K-stride (256 MiB): 1.85s   (TLB thrashing — 64 dTLB entries, 65536 needed)
MAP_HUGETLB 2 MiB pages:        0.31s   (only 128 TLB entries needed)
```

**Why:** The L1 dTLB on a modern Intel core holds ~64 4K-page entries. At 4K pages, 256 MiB random access needs 65536 entries — always missing. At 2M pages, only 128 entries suffice. GPU ML frameworks use MADV_HUGEPAGE on model weight buffers.

**Exercise:** `echo madvise > /sys/kernel/mm/transparent_hugepage/enabled`. Call `madvise(ptr, sz, MADV_HUGEPAGE)` and re-run the random access benchmark. Observe the speedup.

**Quiz focus:** TLB shootdown cost (INVLPG + IPI), THP khugepaged, MAP_HUGETLB vs MADV_HUGEPAGE, iTLB vs dTLB, DPDK huge pages for packet buffers

---

### Lab 12 — Loading the Kernel, Initialising the Page Table

**File:** labs/lab_12_kernel_boot.c | **Run:** ./scripts/run_lab.sh 12

**What to observe:**

```
/proc/cmdline:  BOOT_IMAGE=/vmlinuz-6.1.0 root=/dev/sda1 quiet splash
/proc/iomem:    Kernel code: 1M-8M   Kernel data: 8M-12M
/sys/kernel/kexec_loaded: 1  (crash kernel pre-loaded — standard on servers)
dmesg | head:   KASLR offset=...  NUMA topology...
```

**Why:** UEFI loads the kernel EFI stub which builds an identity-mapped early page table, then calls start_kernel(). KASLR randomises the kernel base address on each boot. The crash kernel (kexec) is pre-loaded so that on panic, the machine boots into it and saves a vmcore dump.

**Exercise:** `dmesg | grep -E "KASLR|memory map|NUMA"` to see early boot decisions. On a cloud VM, /proc/iomem shows virtio devices instead of physical PCI controllers.

**Quiz focus:** UEFI vs BIOS, GRUB2 stages, KASLR, initrd purpose, kdump/kexec workflow, measured boot with TPM2 in AWS Nitro / Azure Confidential VMs

---

### Lab 13 — Setting Up Page Tables for User Processes

**File:** labs/lab_13_user_page_tables.c | **Run:** ./scripts/run_lab.sh 13

**What to observe:**

```
Before child write:  Shared_Clean=4096  (page shared via COW)
After  child write:  Private_Dirty=4096 (child has its own copy)
Minor faults in child: 1 per written page (COW triggered)
```

**Why:** fork() calls copy_mm() which duplicates the vm_area_struct list but marks all writable PTEs read-only. First write triggers #PF, kernel copies the physical page, marks both PTEs writable. This is how nginx prefork workers share read-only config pages efficiently.

**Exercise:** Fork 10 children each writing to a different page. Read Shared_Clean and Private_Dirty from /proc/<pid>/smaps. Total Private_Dirty should equal exactly 10 * 4096 bytes.

**Quiz focus:** KPTI page table isolation, COW PTE mechanics, vfork() optimisation (shares page table until exec), dup_mm cost

---

### Lab 14 — Processes in Action

**File:** labs/lab_14_processes_in_action.c | **Run:** ./scripts/run_lab.sh 14

**What to observe:**

```
fork() -> child PID=1002, getppid()=1001
Zombie: ps aux | grep Z -> 1002 Z  (child exited, parent not wait()ed yet)
exec(): VmPeak resets; open FDs survive unless O_CLOEXEC set
```

**Why:** do_fork() allocates a task_struct, copies FDs (dup_fd), and shares the mm_struct via COW. exec() calls load_elf_binary() which replaces code/data VMAs but keeps PID and open FDs. A zombie lingers in the process table until parent calls wait().

**Exercise:** Read /proc/<pid>/status fields VmPeak, VmRSS, Threads before and after exec. Which fields reset? Inside Docker, PID 1 (container entrypoint) must reap zombies or the pid namespace fills.

**Quiz focus:** zombie vs orphan, O_CLOEXEC, pid namespaces, task_struct fields preserved/reset by exec, wait4() options (WNOHANG, WUNTRACED)

---

### Lab 15 — Process Structure, Context Switching

**File:** labs/lab_15_context_switching.c | **Run:** ./scripts/run_lab.sh 15

**What to observe:**

```
getpid() via syscall:  ~150 ns  (ring 3 to ring 0 transition)
getpid() via vDSO:     ~8 ns    (reads cached value — no ring switch)
sched_yield() cost:    ~2 µs    (voluntary context switch)
voluntary_ctxt_switches in /proc/self/status: increments each yield
```

**Why:** A context switch saves all CPU registers including AVX-512 state (lazily on first FP use), updates CR3 to the new process's PML4, and flushes non-global TLB entries.

**Exercise:** `perf stat -e context-switches ./bin/lab_15`. Pin with `taskset -c 0 ./bin/lab_15` — context switch count drops toward zero. Measure sched_yield() latency on idle vs loaded machine.

**Quiz focus:** voluntary vs involuntary switch, FPU lazy save (FXSAVE), CR3 reload TLB flush cost, VDSO cached variables, task_struct.thread register save area

---

### Lab 16 — Kernel Stack, Scheduler, Fork, PCB, Trap Entry/Return

**File:** labs/lab_16_scheduler_pcb.c | **Run:** ./scripts/run_lab.sh 16 (Linux only)

**What to observe:**

```
/proc/self/sched:
  se.vruntime  = 14523.456789  (nanoseconds of weighted CPU time)
  nr_switches  = 42
  prio         = 120           (120 = normal, 100 = RT prio 20, 139 = nice 19)
```

**Why:** CFS picks the task with minimum vruntime from a red-black tree each tick. EEVDF (Linux 6.6+) replaces CFS's "pick minimum vruntime" with an eligible virtual deadline — better latency for interactive and mixed workloads.

**Exercise:** `cat /proc/self/sched` after 1000 sched_yield() calls. `nice -n 19 ./bin/lab_16` and compare vruntime growth rate vs nice 0.

**Quiz focus:** CFS vruntime, EEVDF (Linux 6.6), SCHED_DEADLINE parameters, kernel stack size (16 KiB default), trap frame layout on x86_64

---

### Lab 17 — Creating the First Process

**File:** labs/lab_17_first_process.c | **Run:** ./scripts/run_lab.sh 17 (Linux only)

**What to observe:**

```
/proc/1/cmdline:  /sbin/init  (or /lib/systemd/systemd)
/proc/1/status:   PPid: 0     (PID 1 has no parent)
pstree -p 1:      shows all user processes descending from PID 1
```

**Why:** After all kernel subsystems initialise, kernel_init() execs PID 1. All user processes descend from PID 1. In a container, PID 1 is the container entrypoint — it must handle SIGTERM and reap zombie children.

**Exercise:** `pstree -p 1 | wc -l`. Inside `docker run --init`, compare — tini (PID 1 shim) reaps zombies. Without --init, the container entrypoint must call waitpid(-1, ...) itself.

**Quiz focus:** kernel_init, systemd as PID 1, pid namespaces, zombie reaping, Kubernetes pod lifecycle and init containers

---

### Lab 18 — Handling User Pointers, Concurrency

**File:** labs/lab_18_concurrency.c | **Run:** ./scripts/run_lab.sh 18

**What to observe:**

```
Racy counter (4 threads x 100000 iters):  Expected: 400000  Got: 382741
Mutex counter:                              Expected: 400000  Got: 400000
ThreadSanitizer: DATA RACE on counter at 0x...
```

**Why:** `counter++` compiles to load + add + store (3 instructions). Another thread can interleave between load and store. x86_64 TSO memory model does not prevent this — you need LOCK XADD or a mutex.

**Exercise:** Compile with `-fsanitize=thread -O1`. TSan detects the race with exact stack traces. Compare throughput: mutex vs __atomic_fetch_add vs _Atomic int. The atomic wins 5–10× for simple counters.

**Quiz focus:** TSO memory model, smp_mb() in kernel, false sharing on 64-byte cache lines, __atomic builtins memory ordering, LOCK prefix on x86

---

### Lab 19 — Locking

**File:** labs/lab_19_locking.c | **Run:** ./scripts/run_lab.sh 19 (Linux only)

**What to observe:**

```
Uncontended mutex lock/unlock:  ~15 ns   (user-space CAS fast path)
Contended mutex (2 threads):    ~1.5 µs  (futex(FUTEX_WAIT) kernel path)
strace -e futex: futex syscalls appear only when contended
```

**Why:** pthread_mutex_t uses a futex word. The fast path is a single CMPXCHG — no syscall. Only when contended does it call futex(FUTEX_WAIT) to sleep.

**Exercise:** `strace -e futex ./bin/lab_19` — confirm futex syscalls appear only under contention. Measure the latency cliff: uncontended vs 2-thread contention.

**Quiz focus:** futex internals, priority inversion, PI futex (FUTEX_LOCK_PI), pthread_mutex_trylock, deadlock detection

---

### Lab 20 — Fine-Grained Locking and Its Challenges

**File:** labs/lab_20_finegrained_lock.c | **Run:** ./scripts/run_lab.sh 20

**What to observe:**

```
Global lock (16 threads):    throughput ≈ 1-thread  (full serialisation)
Per-bucket locks (16 buckets): throughput ≈ 12x single thread (near-linear)
False sharing (2 locks on same cache line): 3x throughput drop
```

**Why:** Fine-grained locks expose parallelism but require canonical acquire order (always by bucket index) to prevent deadlock. False sharing: two locks on the same 64-byte cache line cause cache-line bouncing via MESI protocol across CPUs.

**Exercise:** Hash table with per-bucket pthread_rwlock. Measure 90% reads vs 50% reads. rwlock dramatically outperforms mutex for read-heavy workloads.

**Quiz focus:** lock ordering for deadlock, false sharing (pad to CACHELINE_SIZE=64), pthread_rwlock vs RCU, Linux kernel spin_lock_irqsave

---

### Lab 21 — Locking Variations

**File:** labs/lab_21_lock_variations.c | **Run:** ./scripts/run_lab.sh 21

**What to observe:**

```
rwlock:         concurrent readers, exclusive writer
seqlock:        readers retry if write in progress (no reader blocking writer)
ticket spinlock: FIFO fairness, prevents starvation
```

**Why:** The Linux kernel uses seqlocks for jiffies and wall-clock time — read millions of times per second. Readers check a generation counter before and after; if it changed, retry. Zero blocking overhead for readers.

**Exercise:** Implement a seqlock with two unsigned counters. Benchmark reader throughput vs pthread_rwlock under a continuous writer. Observe reader starvation under high write frequency.

**Quiz focus:** seqlock for kernel timekeeping (timekeeper), reader-writer fairness, adaptive spin in glibc mutex, pthread_rwlock_prefer_writer_nonrecursive_np

---

### Lab 22 — Condition Variables

**File:** labs/lab_22_condvar.c | **Run:** ./scripts/run_lab.sh 22

**What to observe:**

```
pthread_cond_wait atomically: (1) releases mutex, (2) sleeps, (3) re-acquires on wake
Spurious wakeup: cond_wait may return without signal — ALWAYS use while(), not if()
signal wakes one; broadcast wakes all waiters
```

**Why:** A condition variable is a wait queue attached to a predicate. The mutex makes predicate-check + sleep atomic, preventing lost wakeups. Implemented via futex(FUTEX_WAIT/FUTEX_WAKE) in the kernel.

**Exercise:** Bounded buffer (capacity 8) with two condition variables: not_full and not_empty. Run 4 producers and 4 consumers. Verify no item is lost or duplicated by checksumming produced vs consumed values.

**Quiz focus:** lost wakeup problem, spurious wakeup reason, broadcast vs signal, pthread_cond_timedwait, Java monitors

---

### Lab 23 — MPMC Queue, Semaphores, Monitors

**File:** labs/lab_23_mpmc_semaphore.c | **Run:** ./scripts/run_lab.sh 23

**What to observe:**

```
sem_wait: blocks if count == 0 (via futex)
sem_post: increments count, wakes one sleeper
MPMC queue with semaphore: correct under any thread interleaving, no busy-wait
```

**Why:** io_uring (Linux 5.1+) uses lock-free submission/completion rings instead of semaphores — avoiding any syscall overhead for applications that batch I/O efficiently.

**Exercise:** Thread pool with work queue using sem_t and a circular buffer. Measure tasks/second with 1, 2, 4, 8 workers. Compare with mutex+condvar implementation.

**Quiz focus:** binary vs counting semaphore, monitor pattern, io_uring ring design, sem_getvalue, POSIX named semaphores for inter-process sync

---

### Lab 24 — Lock-Free Primitives, CAS, Read/Write Locks

**File:** labs/lab_24_lockfree.c | **Run:** ./scripts/run_lab.sh 24

**What to observe:**

```
CAS retry count under contention: 2–10 retries at 8 threads
ABA bug: CAS succeeds on A->B->A sequence incorrectly
Lock-free stack with generation-tagged pointer: zero ABA errors under ASAN
```

**Why:** Lock-free algorithms use LOCK CMPXCHG to avoid mutual exclusion. They eliminate priority inversion and deadlock. DPDK and SPDK use lock-free rings for packet and block I/O at line rate.

**Exercise:** Implement a lock-free stack. Deliberately introduce ABA. Detect with AddressSanitizer. Fix using a 128-bit tagged pointer (top 16 bits = generation counter).

**Quiz focus:** ABA problem, tagged pointers (top 16 bits in x86_64 canonical address), memory_order_acq_rel vs seq_cst, ARM LL/SC vs x86 CAS, DPDK rte_ring

---

### Lab 25 — Synchronisation: acquire/release, sleep/wakeup, exit/wait

**File:** labs/lab_25_sync_primitives.c | **Run:** ./scripts/run_lab.sh 25 (Linux only)

**What to observe:**

```
__atomic_store(RELEASE) + __atomic_load(ACQUIRE): correct lock/unlock without full fence
FUTEX_WAIT / FUTEX_WAKE: kernel-side sleep/wakeup on a single aligned word
```

**Why:** C11 memory model: acquire and release are the minimum ordering for a correct lock pair. seq_cst adds a full fence — ~3x slower on ARM. The Linux kernel uses smp_store_release / smp_load_acquire identically.

**Exercise:** Spinlock using only __atomic_test_and_set + __atomic_clear. Verify race-free with ThreadSanitizer. Add exponential backoff (pause instruction) and observe throughput improvement.

**Quiz focus:** acquire-release vs seq_cst, smp_mb(), futex word alignment, weak CAS on ARM (may spuriously fail), exit()/wait() synchronisation in xv6

---

### Lab 26 — Signals, IDE Driver, Introduction to Demand Paging

**File:** labs/lab_26_signals_demand.c | **Run:** ./scripts/run_lab.sh 26

**What to observe:**

```
SIGSEGV handler: si_addr = faulting virtual address
After mprotect in handler: page accessible, execution continues
RSS before touch: 0 KB    RSS after touch: 64 MB
Only touched pages consume physical memory
```

**Why:** The kernel delivers a signal by saving user register state on the signal stack and jumping to the handler. After the handler, sigreturn restores context. userfaultfd (Linux 4.3+) is the modern alternative for checkpoint/restore and live migration.

**Exercise:** mmap(PROT_NONE) 64 MiB. Install SIGSEGV handler that calls mprotect on the faulted page. Verify VmRSS in /proc/self/status shows only touched pages.

**Quiz focus:** SA_SIGINFO, sigaltstack, userfaultfd vs SIGSEGV for live migration, MADV_USERFAULT, sigprocmask

---

### Lab 27 — Demand Paging (Interactive)

**File:** labs/demand_paging.c | **Run:** ./scripts/run_lab.sh 27
Open a second terminal: ./scripts/monitor.sh <PID>

**What to observe:**

```
Phase 1 mmap(100 MiB):   VmSize +102400 KB    VmRSS unchanged    faults=0
Phase 2 read scan:        VmRSS +4 KB          (zero page shared — no alloc)
Phase 3 write 10 MiB/s:  VmRSS +10240 KB/s    MinFlt +2560/s
Phase 4 warm re-scan:     faults ~= 0          (pages already mapped)
Phase 5 munmap:           VmSize and VmRSS drop to baseline
```

**Why:** mmap(MAP_ANONYMOUS) reserves a vm_area_struct but allocates no frames. First reads map to the shared zero page (no physical allocation). First writes trigger copy-on-write of the zero page — each fault allocates one 4 KiB frame.

**Verification:** Expected minor faults per write phase = bytes_written / 4096. Write phase writes 10 MiB -> expect 2560 faults. Verify against MinFlt delta in monitor.

**Quiz focus:** zero page, anonymous vs file-backed pages, vm_area_struct.vm_flags, text pages loaded lazily on exec, MAP_POPULATE to bypass demand paging, /proc/vmstat pgfault vs pgmajfault

---

### Lab 28 — Page Replacement, Thrashing

**File:** labs/lab_28_page_replace.c | **Run:** ./scripts/run_lab.sh 28

**What to observe:**

```
Sequential scan 64 MiB (3 passes): 0.08s   (prefetcher + TLB warm)
Random     scan 64 MiB (3 passes): 1.20s   (15x slower — TLB + cache miss)
vmstat 1 when working set > RAM:   si/so spike -> thrashing
```

**Why:** MGLRU (Multi-Generation LRU, Linux 6.1+) tracks page age via PTE Accessed bit sweeps across generations, reducing kswapd CPU overhead 50–80% on large working sets. ML training uses mlock() to pin GPU DMA staging buffers — those pages never swap.

**Exercise:**
1. Allocate memory exceeding RAM. Watch `vmstat 1` si/so columns.
2. Toggle MGLRU: `echo 0 > /sys/kernel/mm/lru_gen/enabled` and compare (kernel 6.1+).
3. mlock() a buffer. Verify VmLck in /proc/self/status. Confirm it never appears in swap.

**Quiz focus:** MGLRU vs two-list LRU, clock algorithm, kswapd, OOM killer oom_score_adj, mlock for GPU DMA, MADV_SEQUENTIAL hint

---

### Lab 29 — Storage Devices, Filesystem Interfaces

**File:** labs/lab_29_storage_fs.c | **Run:** ./scripts/run_lab.sh 29

**What to observe:**

```
Sequential read 1st run (cold): 120 MB/s   (disk limited)
Sequential read 2nd run (warm): 4200 MB/s  (page cache — RAM speed)
Random 4K pread cold:           350 IOPS
Random 4K io_uring batch:       850000 IOPS (saturates NVMe 64K queue depth)
```

**Why:** The VFS layer intercepts every read()/write() and routes through the page cache. NVMe exposes 64K parallel queues; classic read() submits one I/O at a time — use io_uring to saturate NVMe bandwidth.

**Exercise:** Compare O_DIRECT (bypass page cache) vs cached read() for sequential reads. Benchmark io_uring batching 64 requests vs 64 individual pread() calls.

**Quiz focus:** VFS layer, page cache writeback, fsync vs fdatasync, io_uring vs epoll for async I/O, NVMe vs SATA latency, O_DIRECT alignment (512B sector)

---

### Lab 30 — File System Implementation

**File:** labs/lab_30_fs_impl.c | **Run:** ./scripts/run_lab.sh 30

**What to observe:**

```
stat(file): ino=1234567  nlink=1  blocks=8  (512B blocks = 4 KB actual)
Hard link: same inode number shared between names
df -i: IFree can reach zero before disk space (inode exhaustion)
```

**Why:** An inode stores metadata but not the filename. The dentry cache (dcache) caches name-to-inode lookups. ext4 uses extents (contiguous block ranges) for better large-file performance vs the old indirect block map.

**Exercise:** Drop caches: `echo 3 > /proc/sys/vm/drop_caches`. Measure stat() latency cold vs warm — observe 10x+ speedup from dentry caching. Create 1 million small files and check `df -i` for inode exhaustion risk.

**Quiz focus:** inode vs dentry vs superblock, ext4 extents vs block pointers, readdir in VFS, d_inode in kernel source, tmpfs inode allocation

---

### Lab 31 — File System Operations

**File:** labs/lab_31_fs_ops.c | **Run:** ./scripts/run_lab.sh 31

**What to observe:**

```
Buffered write (no fsync):  1200 MB/s  (page cache absorbs all writes)
write() + fsync():           120 MB/s  (NVMe throughput limited)
O_SYNC open:                  95 MB/s  (sync per-write, slightly slower)
strace: write -> fsync -> close (3 distinct syscalls per durable write)
```

**Why:** Without fsync, a power failure after write() but before writeback loses data. Databases use fdatasync() or O_DSYNC for durability. DAX (Direct Access) on persistent memory bypasses the page cache for sub-microsecond write latency.

**Exercise:** Benchmark: buffered write vs fsync vs O_SYNC vs O_DIRECT. Graph throughput vs durability tradeoff. This is the decision every database makes.

**Quiz focus:** write-back vs write-through, fdatasync vs fsync, DAX for PMEM, O_SYNC vs O_DSYNC, sync_file_range() for partial flush

---

### Lab 32 — Crash Recovery and Logging

**File:** labs/lab_32_crash_recovery.c | **Run:** ./scripts/run_lab.sh 32

**What to observe:**

```
Without journaling: crash between metadata and data write -> corrupt FS
With journaling (ordered mode): metadata committed only after data written
dmesg after forced reboot: EXT4-fs: recovery complete (N transactions replayed)
```

**Why:** ext4 journal modes: ordered (default), writeback (metadata only, fastest), journal (data+metadata, slowest). ZFS uses copy-on-write — never overwrites live data, no journal needed.

**Exercise:** Simulate crash: write to file, `kill -9` mid-write without fsync. Check the file. Repeat with fsync() before kill — written data survives.

**Quiz focus:** journal modes in ext4, JBD2 commit protocol, ZFS COW vs journaling, log_writes dm target for crash testing, NVDIMM crash consistency

---

### Lab 33 — Logging in Linux ext4 Filesystem

**File:** labs/lab_33_ext4_journal.c | **Run:** ./scripts/run_lab.sh 33

**What to observe:**

```
tune2fs -l /dev/sda1: Journal inode=8  Journal size=128 MB  Features: has_journal
/proc/fs/ext4/*/options: data=ordered,journal_checksum,delalloc
debugfs -R stats /dev/sda1: journal blocks=32768
```

**Why:** JBD2 implements atomic transactions: descriptor block -> data/metadata -> commit block. Recovery replays only committed transactions. Fast commit (ext4, Linux 5.10+) reduces journal overhead for rename and unlink by 30–50%.

**Exercise:** Mount with journal_async_commit and benchmark fsync-heavy workload. Read /proc/fs/ext4/*/mb_groups to observe jbd2 commit frequency.

**Quiz focus:** JBD2 commit protocol, fast commit (Linux 5.10+), ordered vs writeback mode, ext4 inline data, btrfs journal-free COW, barrier=1 mount option

---

### Lab 34 — Protection and Security

**File:** labs/lab_34_protection.c | **Run:** ./scripts/run_lab.sh 34 (Linux only)

**What to observe:**

```
DAC: open("/etc/shadow", O_RDONLY) -> EACCES (without root)
capabilities: CAP_NET_ADMIN allows non-root network config
seccomp strict mode: open() -> process killed with SIGSYS
```

**Why:** Linux capabilities split root into 38 fine-grained privileges. seccomp-bpf (used by Docker, Chrome, Firefox sandbox) compiles a BPF program that runs in the kernel on every syscall. eBPF LSM (Linux 5.7+) lets you write security policies in eBPF.

**Exercise:** `prctl(PR_SET_SECCOMP, SECCOMP_MODE_STRICT)` — attempt open(), observe SIGSYS. Write a BPF filter via libseccomp allowing only read, write, exit.

**Quiz focus:** DAC vs MAC (SELinux/AppArmor), Linux capabilities, seccomp-bpf, eBPF LSM hooks, container security model (rootless Docker, user namespaces)

---

### Lab 35 — Scheduling Policies

**File:** labs/lab_35_scheduling.c | **Run:** ./scripts/run_lab.sh 35 (Linux only)

**What to observe:**

```
SCHED_OTHER nice=0:  ~95% CPU    vruntime grows at 1x rate
SCHED_OTHER nice=19: ~5%  CPU    vruntime grows at ~20x rate
SCHED_FIFO prio=1:   monopolises core (preempts all SCHED_OTHER)
```

**Why:** CFS uses a red-black tree keyed by vruntime. EEVDF (Linux 6.6+) assigns each task a virtual deadline based on its slice — better latency for interactive tasks mixed with batch. NCCL workers are typically pinned with SCHED_FIFO on GPU training nodes.

**Exercise:** `nice -n 0` vs `nice -n 19` on CPU-bound tasks. top should show ~95%/5% split. SCHED_FIFO process: does it preempt your shell? (Yes, until it sleeps.)

**Quiz focus:** CFS vruntime, EEVDF (Linux 6.6), SCHED_DEADLINE (EDF scheduling), CPU cgroup cpu.max, sched_rt_runtime_us safety limit, NCCL thread pinning

---

### Lab 36 — Lock-Free Multiprocessor Coordination, RCU

**File:** labs/lab_36_rcu_lockfree.c | **Run:** ./scripts/run_lab.sh 36

**What to observe:**

```
RCU reader overhead:   ~2 ns   (no atomic, no lock — just memory barrier)
rwlock reader overhead: ~25 ns  (atomic increment/decrement on shared counter)
RCU writer grace period: ~5 µs  (waits for all CPU quiescent states)
Throughput (99% reads): RCU is 8x faster than rwlock at 16 threads
```

**Why:** RCU readers pay zero synchronisation cost — they rely on the guarantee that the writer waits a grace period (all CPUs pass a quiescent state) before freeing old data. Used in Linux's routing table, process list, and file descriptor table.

**Exercise:** Simulate RCU with generation counters: readers snapshot generation, do work, check generation unchanged. Writer increments and waits for all readers to exit. Compare throughput vs pthread_rwlock at 16 threads with 99% reads.

**Quiz focus:** grace period, synchronize_rcu vs call_rcu (async), rcu_dereference memory ordering, QSBR vs signal-based RCU, userspace liburcu

---

### Lab 37 — Microkernel, Exokernel, Multikernel

**File:** labs/lab_37_kernel_arch.c | **Run:** ./scripts/run_lab.sh 37

**What to observe:**

```
sysctl -a | grep kernel | head -20   live kernel tunables
/proc/sys/kernel/pid_max, randomize_va_space, perf_event_paranoid
bpftool prog list   eBPF programs currently loaded (Cilium, Falco, etc.)
```

**Why:** Monolithic kernels put all subsystems in kernel space — fast, but a bug anywhere can crash the system. Microkernels put only IPC, memory, and scheduling in kernel. eBPF makes Linux extensible like an exokernel — safe, verified user programs run at kernel speed without a kernel module.

**Exercise:** List loaded eBPF programs: `bpftool prog list`. On a Kubernetes node, Cilium loads dozens of XDP and tc programs. Try writing a minimal eBPF kprobe on do_fork to count process creation rate.

**Quiz focus:** IPC latency in microkernel (L4: 200 ns) vs monolithic (0 — in-kernel call), eBPF verifier constraints, Fuchsia OS capability-based design, Barrelfish for NUMA

---

### Lab 38 — Virtualisation

**File:** labs/lab_38_virtualization.c | **Run:** ./scripts/run_lab.sh 38

**What to observe:**

```
systemd-detect-virt: kvm  (or none on bare metal)
/proc/cpuinfo flags: hypervisor  (set inside VM by KVM)
getpid() inside VM:  ~200 ns    (+100 ns VMEXIT overhead vs bare metal)
```

**Why:** KVM turns Linux into a type-1 hypervisor using VT-x/AMD-V. Guest OS runs directly on hardware for most instructions; VMEXIT to KVM only for privileged ops. VFIO allows GPU passthrough — the H100 appears as a real PCIe device inside the VM.

**Exercise:** Compare getpid() latency inside a KVM VM vs bare metal. The VMEXIT cost is 1–5 µs. Check if VFIO is configured: `ls /sys/bus/pci/drivers/vfio-pci/`.

**Quiz focus:** trap-and-emulate vs binary translation, EPT (Extended Page Tables), virtio paravirtualisation, VFIO GPU passthrough, Firecracker microVM, AWS Nitro card offload

---

### Lab 39 — Cloud Computing

**File:** labs/lab_39_cloud_compute.c | **Run:** ./scripts/run_lab.sh 39

**What to observe:**

```
Inside Docker --memory=64m:
  /sys/fs/cgroup/memory.max:  67108864  (64 MiB)
  /sys/fs/cgroup/cpu.max:     200000 100000  (2.0 cores)
  malloc(128 MiB) -> OOM Kill  (cgroup enforces limit)
unshare --pid --fork --mount-proc bash: PID 1 inside new namespace
```

**Why:** Linux namespaces (PID, mount, net, user, IPC, UTS, cgroup, time — 8 types in Linux 6.x) provide isolation; cgroups v2 provides resource accounting. Kubernetes translates resources.limits.memory into memory.max in the pod cgroup. Firecracker uses KVM + minimal device model for less than 125 ms cold start.

**Exercise:** `cat /sys/fs/cgroup/memory.current` to see live usage. `nsenter -t <PID> --pid --mount -- ps aux` to enter a container's namespaces from the host.

**Quiz focus:** cgroups v2 vs v1 unified hierarchy, namespace types, Firecracker vs gVisor, cpu.shares vs cpu.max, eBPF for container network policy (Cilium)

---

### Lab 40 — GPU OS: Multicore, Hyperthreading, NCCL

**File:** labs/lab_40_gpu_os.c | **Run:** ./scripts/run_lab.sh 40 (Linux only)

**What to observe:**

```
nvidia-smi topo -m:
  GPU0  GPU1  CPU Affinity
  X     NV4   0-47          (NVLink 4.0 between GPUs on same NUMA node)
/sys/kernel/mm/transparent_hugepage/enabled: madvise
CPU governor: performance   (must be pinned for NCCL barrier synchronisation)
PCIe Gen5 x16 bandwidth: ~64 GB/s    NVLink 4.0: 900 GB/s
```

**Why:** An H100 DGX node has 8 GPUs across 2 NUMA domains. NCCL AllReduce uses NVLink (intra-node, 900 GB/s) and GPUDirect RDMA (inter-node — bypasses host CPU and memory entirely). OS tuning for ML: iommu=pt, THP madvise, zone_reclaim_mode=0, CPU governor performance, NUMA-pinned NCCL threads.

**Exercise:**
1. `nvidia-smi topo -m` to identify GPU pairs connected via NVLink vs PCIe.
2. `nccl-tests/build/all_reduce_perf -b 8 -e 4G -f 2 -g 8` to measure AllReduce bandwidth.
3. Compare mlock-pinned host memory vs pageable for CUDA cudaMemcpyAsync throughput.

**Quiz focus:** NVLink 4.0 vs PCIe Gen5 bandwidth, GPUDirect RDMA + IOMMU interaction, NCCL AllReduce algorithms (ring vs tree vs hierarchical), CUDA Unified Memory demand paging, ATS in PCIe 4.0, zone_reclaim_mode=0 for GPU workloads

---

## Process and Memory Subsystem Deep Dive

`labs/process_memory_exercises.c` provides a consolidated exercise covering the kernel subsystems that underpin every lab above.

| Exercise | Kernel Subsystem | Key Interface |
|---|---|---|
| task_struct tour | Process management | /proc/pid/status |
| mm_struct walk | Virtual memory | /proc/pid/maps, smaps |
| Page fault lifecycle | Demand paging | getrusage(), /proc/vmstat |
| mmap type comparison | VMA management | /proc/pid/maps |
| OOM killer | Memory reclaim | /proc/pid/oom_score |
| Huge page allocation | TLB optimisation | /proc/meminfo HugePages_* |
| /proc/meminfo tour | System memory | /proc/meminfo |
| kthread observation | Kernel threads | /proc/pid/status |

Build and run:

```bash
gcc -O0 -Wall -pthread -o bin/pm_exercises labs/process_memory_exercises.c
./bin/pm_exercises
```

---

## Self-Help Learning Guide

### Reading Order

```
Week 1-2   Foundations:         01 -> 02 -> 03 -> 04 -> 07
Week 3-4   Virtual Memory:      08 -> 09 -> 10 -> 11 -> 13 -> 27 -> 28
Week 5     Processes:           14 -> 15 -> 16 -> 17 -> 35
Week 6-7   Concurrency:         18 -> 19 -> 20 -> 21 -> 22 -> 23 -> 24 -> 25
Week 8     Storage:             29 -> 30 -> 31 -> 32 -> 33
Week 9-10  Advanced Modern:     34 -> 36 -> 37 -> 38 -> 39 -> 40
```

### The 5-Step Method for Each Lab

1. **Read the header** — topic, build command, expected output
2. **Run it first** — read output carefully before diving into the code
3. **Do the hands-on exercise** — requires Linux; use a VM if on macOS
4. **Answer quiz questions** — in your own words, no notes
5. **Check answers** — answers/answer-key.md and answers/expected-observations.md

### Key /proc and /sys Paths

```bash
# Per-process
/proc/<pid>/maps           VMA list: address range, permissions, file
/proc/<pid>/smaps          Per-VMA: RSS, PSS, Dirty, Swap
/proc/<pid>/pagemap        Virtual to physical PFN (requires root)
/proc/<pid>/status         VmPeak, VmRSS, VmSwap, Threads, ctxt_switches
/proc/<pid>/sched          CFS: vruntime, nr_switches, prio
/proc/<pid>/oom_score      OOM killer score (higher = killed first)

# System-wide
/proc/meminfo              MemTotal, Cached, SwapTotal, HugePages_*
/proc/vmstat               pgfault, pgmajfault, pswpin, pswpout
/proc/buddyinfo            Buddy allocator free list per zone per order
/proc/slabinfo             SLUB cache active_objs, object_size

# Tunables
/sys/kernel/mm/transparent_hugepage/enabled   always | madvise | never
/sys/kernel/mm/lru_gen/enabled                1 = MGLRU on (Linux 6.1+)
/sys/fs/cgroup/                               cgroups v2 hierarchy
/proc/sys/vm/swappiness                       0-200, default 60
```

### Recommended Tools

```bash
# Live memory monitoring alongside lab 27
watch -n 0.5 "grep -E 'VmRSS|VmSize|MinFlt|MajFlt' /proc/<pid>/status"

# Page fault tracing
perf stat -e major-faults,minor-faults,page-faults ./bin/lab_27

# System call tracing
strace -c ./bin/lab_08
strace -e mmap,brk ./bin/lab_09

# Scheduler statistics
watch -n 1 "cat /proc/<pid>/sched"

# System-wide memory pressure
vmstat 1

# NUMA topology
numactl --hardware
numastat -p <pid>

# eBPF programs loaded
bpftool prog list
```

---

## Building Labs

```bash
./scripts/build_all.sh

# Single lab
gcc -O0 -Wall -pthread -o bin/lab_09 labs/lab_09_paging_deep.c

# With debug symbols
gcc -O0 -g -Wall -pthread -o bin/lab_09 labs/lab_09_paging_deep.c

# ThreadSanitizer (concurrency labs 18-25)
gcc -O1 -fsanitize=thread -pthread -o bin/lab_18_tsan labs/lab_18_concurrency.c

# AddressSanitizer (memory safety)
gcc -O1 -fsanitize=address -o bin/lab_24_asan labs/lab_24_lockfree.c
```

---

## Interview Preparation

| Topic | Labs | Canonical Question |
|---|---|---|
| Virtual memory | 08-10, 27 | Walk me through a page fault, start to finish |
| Copy-on-write | 09, 13, 27 | How does fork() scale to large heap processes? |
| Concurrency | 18-25 | Design a lock-free work-stealing queue |
| Scheduling | 15, 16, 35 | How does CFS pick the next task to run? |
| Storage | 29-33 | What happens between write() and data reaching disk? |
| Containers | 01, 14, 39 | How do cgroups and namespaces work together? |
| GPU/ML OS | 11, 28, 40 | Why does NCCL use NVLink instead of PCIe for AllReduce? |
| Security | 05, 34 | How does Chrome's sandbox restrict system calls? |

### Self-Assessment Checklist

Before claiming mastery of a topic:

- Can you predict the output before running?
- Can you explain why the kernel behaves that way?
- Can you point to the relevant kernel source file?
- Can you connect it to a real production scenario?
- Can you answer all quiz questions without notes?

---

## License

Educational use. Based on Prof. Sorav Bansal's NPTEL IIT Delhi Operating Systems lecture series.
Labs written and compiled by Arun Singh — arunsingh.in@gmail.com
