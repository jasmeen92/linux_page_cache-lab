/*
 * demand_paging.c
 *
 * A program to observe demand paging on Linux.
 *
 * Behavior:
 *   1. Reserve 100 MiB of virtual memory with mmap() (no physical pages allocated).
 *   2. Write 10 MiB every second.
 *      Each write triggers page faults, causing the OS to allocate physical pages.
 *
 * Use monitor.sh in another terminal to observe memory usage.
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>

#define TOTAL_MIB   100
#define CHUNK_MIB   10
#define MIB         (1024UL * 1024UL)
#define TOTAL_BYTES (TOTAL_MIB * MIB)
#define CHUNK_BYTES (CHUNK_MIB * MIB)

int main(void)
{
    printf("=== Linux Demand Paging Experiment ===\n");
    printf("PID           : %d\n", getpid());
    printf("Virtual mem   : %d MiB to reserve\n", TOTAL_MIB);
    printf("Write chunk   : %d MiB / sec\n", CHUNK_MIB);
    printf("\nRun the following in another terminal to monitor memory usage:\n");
    printf("  ./monitor.sh\n\n");

    /* --- Step 1: Reserve virtual memory (no physical pages allocated yet) --- */
    printf("[1] Reserving %d MiB of virtual memory with mmap()... Press Enter\n", TOTAL_MIB);
    fflush(stdout);
    getchar();

    uint8_t *mem = mmap(NULL, TOTAL_BYTES,
                        PROT_READ | PROT_WRITE,
                        MAP_PRIVATE | MAP_ANONYMOUS,
                        -1, 0);
    if (mem == MAP_FAILED) {
        perror("mmap");
        return 1;
    }
    printf("    Done (virtual address: %p)\n", (void *)mem);
    printf("    NOTE: No physical pages have been allocated yet.\n\n");

    /* --- Step 2: Write 10 MiB at a time -> physical pages get allocated --- */
    printf("[2] Writing %d MiB per second... Press Enter\n", CHUNK_MIB);
    fflush(stdout);
    getchar();

    int chunks = TOTAL_MIB / CHUNK_MIB;
    for (int i = 0; i < chunks; i++) {
        sleep(1);
        size_t offset = (size_t)i * CHUNK_BYTES;
        /* write via memset -> page fault -> physical page allocation */
        memset(mem + offset, (uint8_t)(i + 1), CHUNK_BYTES);
        printf("    Written: %3d / %d MiB\n",
               (i + 1) * CHUNK_MIB, TOTAL_MIB);
        fflush(stdout);
    }

    /* --- Step 3: Cleanup --- */
    printf("[3] Releasing memory with munmap()... Press Enter\n");
    fflush(stdout);
    getchar();

    munmap(mem, TOTAL_BYTES);
    printf("    Done. Experiment complete.\n");
    return 0;
}
