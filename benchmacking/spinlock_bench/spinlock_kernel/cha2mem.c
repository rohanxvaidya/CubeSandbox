/* cha2mem.c
 * input a cha id, and base physical address, mem range, scan between this memory address range to find
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
    printf("Usage: cha2mem -b <base_address> -s <size> -i <cha_id>\n");
    printf("  -b <base_address> : Base physical address (hex format)\n");
    printf("  -s <memory size>  : Memory range size (hex format)\n");
    printf("  -i <cha_id>       : CHA ID to calculate the corresponding address\n");
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

unsigned long mapped_physical_addr_to_specific_cha(unsigned long base_address, unsigned long size, int t_cha )
{
    unsigned long  phy_address = 0;
	struct _hash_data  *hash_obj;
	char *buf, *p;
	int cha_id_get, i, sz = 400*1024;

	int cha_per_cluster = g_max_cha / g_num_clusters;
	int cluster_id = t_cha / cha_per_cluster;	
	int target_cha = t_cha  - (cluster_id * cha_per_cluster);
	printf("clusterID=%d, targetCHA=%d, CHAperCluster=%d\n", cluster_id, target_cha, cha_per_cluster);

	hash_mode = get_hash_mode();
	
	hash_obj = init_hash(cha_per_cluster);
	if (hash_obj == NULL) {
		printf("Failed to create CHA hash object. Exiting..\n");
        return 0;
	}

	for (i=0; i < size; i+=64) {
		phy_address = base_address + i ;
		// first check whether the physical address maps to the right cluster
  		int cluster_id_get = get_cluster_id (phy_address, g_num_clusters);
        if (cluster_id_get != cluster_id )
            continue;
        else 

        //TODO: revist here, to fix issue, 
        // the cha_id_get < cha_per_cluster , the address is really mapped to CHA (cha_id_get + cha_per_cluster)
        // why?

		// phy_address is in the right cluster
        cha_id_get = get_cha_id(hash_obj, phy_address);
		if ( cha_id_get == target_cha) {
            printf("Current address [0x%lx] is on cluster [%d] with CHA [%d]\n", phy_address, cluster_id_get, cha_id_get);
			return phy_address;
        }
	}

	printf("Unable to find the mapped address with specific CHA[%d] in range of [0x%lx - 0x%lx]\n", t_cha, base_address, base_address + size - 1);

    return 0;
}

int main(int argc, char *argv[]) {
    unsigned long base_address = 0, mapped_phy_address = 0;
    unsigned long size = 0;
    int cha_id = -1;

    // Parse command line arguments
    int opt;
    while ((opt = getopt(argc, argv, "b:s:i:m:c:")) != -1) {
        switch (opt) {
            case 'b':
                base_address = strtoul(optarg, NULL, 0);
                break;
            case 's':
                size = strtoul(optarg, NULL, 0);
                break;
            case 'i':
                cha_id = atoi(optarg);
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
    if (base_address == 0 || size == 0 || cha_id < 0) {
        usage();
    }

    printf("To map the memory address with CHA [%d], based on 0x[%lx],  cha_num per NUMA is [%d], cluster per NUMA is [%d]\n", \
    cha_id, base_address, g_max_cha, g_num_clusters);

    // Print the current CPU type
    print_cpu_type();

    // Get the L3 cache size
    L3_cache_size_kib = get_l3_cache_size();
    printf("L3 Cache Size: %ld KiB\n", L3_cache_size_kib);

    //TODO: Get the MAX CHA number for sigle socket in platform.

    printf("To find the mapped address in memory range [0x%lx - 0x%lx] with CHA_ID %d ...\n", base_address, base_address + size, cha_id);
    //TODO: mapping the physical address accroding to the cha_id.
    if (g_max_cha !=0 && cha_id != -1) {
        // both max_cha and target_cha are specified
        mapped_phy_address = mapped_physical_addr_to_specific_cha(base_address, size, cha_id);
        if (! mapped_phy_address) {
            printf("Failed to map address on CHA[%d] based on address 0x%lx\n", cha_id, base_address);
        } else {
            printf("Final address for CHA ID %d: 0x%lx\n", cha_id, mapped_phy_address);
        }
    }
    // get a address mapping to the target cha.
    // char *mapped_address = get_buffer_mapped_to_specific_cha(g_max_cha, cha_id, g_num_clusters);    
    // if (mapped_address) {
    //     unsigned long final_address = base_address + (unsigned long)(mapped_address - (char *)0);
    //     printf("Final address for CHA ID %d: 0x%lx\n", cha_id, final_address);
    // } else {
    //     printf("Failed to get mapped address for CHA ID %d\n", cha_id);
    // }

    return 0;
}
