/* mem2cha.c
 * input physical memory, output a cha id, and base physical address, mem range, scan between this memory address range to find
 * a chunk of memory that mapped to the correspoding cha in intel platform.
 * */

#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>
#include <string.h>
#include <unistd.h>
#include "intel_platform.h"

// Global variables
int g_num_clusters = 1; // Value for number of clusters in socket.
int g_max_cha = 40;     // Value for maximum CHA in NUMA node in one socket.
//int hash_mode=-1;

unsigned long L3_cache_size_kib = 0; // L3 cache size in KiB
char *mapped_address;

// Function prototype for the external function
char *get_buffer_mapped_to_specific_cha(int max_cha, int target_cha, int num_clusters);

// Function to display usage
void usage() {
    printf("Usage: mem2cha -b <mem_address> \n");
    printf("  -b <mem_addr>     : Base physical address (hex format)\n");
	printf("  -m <num_cha>      : Number of CHA slices in one NUMA node on a socket\n");
	printf("  -c <num_cluster>  : Number of clusters in one NUMA node on a socket\n");
    exit(1);
}

// Function to read and print the current CPU type
void print_cpu_type() {
    FILE *fp = fopen("/proc/cpuinfo", "r");
    if (fp == NULL) {
        perror("Failed to open /proc/cpuinfo");
        return;
    }

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        if (strncmp(line, "model name", 10) == 0) {
            printf("CPU Type: %s", line + 13); // Print the model name
            break;
        }
    }
    fclose(fp);
}

// Function to get and store the L3 cache size in KiB
unsigned long get_l3_cache_size() {
    unsigned long l3_cache_size;
    l3_cache_size = sysconf(_SC_LEVEL3_CACHE_SIZE);
    return l3_cache_size /1024; // Size in Kbytes

/*
    FILE *fp = fopen("/proc/cpuinfo", "r");
    if (fp == NULL) {
        perror("Failed to open /proc/cpuinfo");
        return -1;
    }

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        if (strncmp(line, "cache size", 10) == 0) {
            // Extract the cache size and convert to MiB
            // char *cache_size_str = line + 11; // Skip "cache size: "
            // unsigned long cache_size_kb = strtoul(cache_size_str, NULL, 10); // Get size in KB
            // l3_cache_size = cache_size_kb ; 
            // printf("L3 Cache Size: %lu MiB\n", l3_cache_size);
            // break;

            // Extract the cache size and convert to MiB
            char *cache_size_str = line + strcspn(line, ":") + 2; // Skip to the size value after ": "
            unsigned long cache_size_kb = strtoul(cache_size_str, NULL, 10); // Get size in KB
            l3_cache_size = cache_size_kb ; 
            printf("L3 Cache Size: %lu MiB\n", l3_cache_size);
            break;
        }
    }
    fclose(fp);
    return l3_cache_size;
*/
   
}

unsigned int map_physical_addr_to_cha(unsigned long base_address )
{
    unsigned long  phy_address = base_address;
	struct _hash_data  *hash_obj;

	int cha_per_cluster = g_max_cha / g_num_clusters;

	printf("CHAperCluster=%d\n", cha_per_cluster);

	hash_mode = get_hash_mode();
	
	hash_obj = init_hash(cha_per_cluster);
	if (hash_obj == NULL) {
		printf("Failed to create CHA hash object. Exiting..\n");
        return 0;
	}

    int cha_id_get = get_cha_id(hash_obj, phy_address);
    int cluster_id_get = get_cluster_id (phy_address, g_num_clusters);
    printf("Current address [ 0x%lx ] is on cluster %d with CHA ID %d\n", phy_address, cluster_id_get, cha_id_get);

    return cha_id_get;
}

int main(int argc, char *argv[]) {
    unsigned long base_address = 0, mapped_phy_address = 0;
    unsigned long size = 0;
    int cha_id = -1;

    // Parse command line arguments
    int opt;
    while ((opt = getopt(argc, argv, "b:m:c:")) != -1) {
        switch (opt) {
            case 'b':
                base_address = strtoul(optarg, NULL, 0);
                break;
            case 'm':
                 g_max_cha  = atoi(optarg);
                break;
            case 'c':
                g_num_clusters = atoi(optarg);
                break;
            default:
                usage();
        }
    }

    // Validate inputs
    if (base_address == 0 ) {
        usage();
    }

    printf("To map the memory address to CHA ID, based on 0x[%lx],  cha_num per NUMA is [%d], cluster per NUMA is [%d]\n", \
    base_address, g_max_cha, g_num_clusters);

    // Print the current CPU type
    print_cpu_type();

    // Get the L3 cache size
    L3_cache_size_kib = get_l3_cache_size();
    printf("L3 Cache Size: %ld KiB\n", L3_cache_size_kib);

    //TODO: Get the MAX CHA number for sigle socket in platform.

    //TODO: mapping the physical address accroding to the cha_id.
    if (g_max_cha !=0) {
        // both max_cha and target_cha are specified
        cha_id = map_physical_addr_to_cha(base_address);
        if (cha_id < 0) {
            printf("Failed to map address to CHA with address 0x%lx\n", base_address);
        } else {
            printf("CHA ID %d for address 0x%lx\n", cha_id, base_address);
        }
    }

    return 0;
}
