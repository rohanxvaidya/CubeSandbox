#define _GNU_SOURCE
#include <stdlib.h>
#include <stdio.h>
#include <assert.h>
#include <sched.h>
#include <sys/shm.h>
#include <errno.h>
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdint.h>
#include <signal.h>
#include <glob.h>
#include <regex.h>
#include <string.h>


//#include "cha_hash.h"
// cha_hash.h
// https://github.com/intel-innersource/applications.benchmarking.cpu-micros.contendedlocks.git
typedef unsigned long uint32;
typedef unsigned long Addr64;
struct _hash_data {
    Addr64 pa;
    uint32 H;
    uint32 P;
	uint32 max_cha;

    uint32 mod3;
    uint32 mod5;
	int mode_2lm;
	Addr64 mask_2lm;

} ;

struct _hash_data* init_hash(uint32 max_cha);
int get_cha_id(struct _hash_data*hd, unsigned long long adr);
void load_pa(struct _hash_data*hd, Addr64 a);
unsigned int compare_and_pick(struct _hash_data *hd, int base, int limit, int n);
unsigned int cbo_id(struct _hash_data *hd, int n);
Addr64 H_bit (Addr64 p, uint32 i_bit);
Addr64 P_bit (Addr64 p, uint32 i_bit);
uint32 pmod3 (Addr64 hashed_addr);
uint32 pmod5 (Addr64 hashed_addr);
//*******//

typedef long long int __int64;

// Define my own CPU_SET macros so we can workarond the max CPU_SETSIZE limit of 1024
// Systems with large number of CPUs like > 1024 cpus require this fix
// So, i had to duplicate many of the macros here (with fix) from /usr/include/bits/sched.h

/* Type for array elements in 'cpu_set'.  */
typedef unsigned long int __my_cpu_mask;

# define __MY_CPU_SETSIZE  8192
# define __MY_NCPUBITS     (8 * sizeof (__my_cpu_mask))

/* Basic access functions.  */
# define __MY_CPUELT(cpu)  ((cpu) / __MY_NCPUBITS)
# define __MY_CPUMASK(cpu) ((__my_cpu_mask) 1 << ((cpu) % __MY_NCPUBITS))

/* Data structure to describe CPU mask.  */
typedef struct
{
  __my_cpu_mask __my_bits[__MY_CPU_SETSIZE / __MY_NCPUBITS];
} my_cpu_set_t;

/* Access functions for CPU masks.  */
# define __MY_CPU_ZERO(cpusetp) \
  do {                                                                        \
    unsigned int __i;                                                         \
    my_cpu_set_t *__arr = (cpusetp);                                             \
    for (__i = 0; __i < sizeof (my_cpu_set_t) / sizeof (__my_cpu_mask); ++__i)      \
      __arr->__my_bits[__i] = 0;                                                 \
  } while (0)
# define __MY_CPU_SET(cpu, cpusetp) \
  ((cpusetp)->__my_bits[__MY_CPUELT (cpu)] |= __MY_CPUMASK (cpu))
# define __MY_CPU_CLR(cpu, cpusetp) \
  ((cpusetp)->__my_bits[__MY_CPUELT (cpu)] &= ~__MY_CPUMASK (cpu))
# define __MY_CPU_ISSET(cpu, cpusetp) \
  (((cpusetp)->__my_bits[__MY_CPUELT (cpu)] & __MY_CPUMASK (cpu)) != 0)
__int64 atomic_add(volatile __int64 *src, __int64 addend);

typedef struct cpuid_info_t {
	unsigned int eax;
	unsigned int ebx;
	unsigned int ecx;
	unsigned int edx;
} cpuid_info_t;

unsigned int get_processor_signature();
unsigned short get_processor_model_id();
int get_cluster_id (unsigned long long pa, int num_clusters);

int is_sapphire_rapids();
int is_emerald_rapids();
int is_granite_rapids();
int is_diamond_rapids();
int is_sierra_forest();
int is_skylake();
int is_icelake();
int hash_mode=-1;

int get_hash_mode()
{
	if (hash_mode == -1) { // hash mode not overriden. So need to discover
		if (is_granite_rapids() || is_sierra_forest()) hash_mode=3; 
		else if (is_emerald_rapids()) hash_mode=2;
		else if (is_skylake() || is_icelake()) hash_mode=1;
		else hash_mode=3; // assume 3 for any unknown or future processors
	}
	return hash_mode;
	
}
void cpuid(unsigned int  eax_in, unsigned int ecx_in, cpuid_info_t* info)
{
	unsigned int eax = 0;
	unsigned int ebx = 0;
	unsigned int ecx = 0;
	unsigned int edx = 0;
	asm(
	    "mov %4, %%eax;"
	    "mov %5, %%ecx;"
	    "cpuid;"
	    "mov %%eax, %0;"
	    "mov %%ebx, %1;"
	    "mov %%ecx, %2;"
	    "mov %%edx, %3;"
	    : "=r"(eax), "=r"(ebx), "=r"(ecx), "=r"(edx) // output operands
	    : "r"(eax_in), "r"(ecx_in)                   // input operands
	    : "%eax", "%ebx", "%ecx", "%edx"             // clobbered registers
	);
	info->eax = eax;
	info->ebx = ebx;
	info->ecx = ecx;
	info->edx = edx;
}

__int64 atomic_add(volatile __int64 *src, __int64 addend)
{

	asm (
		"lock add %1, (%0)\n\t"
	::"r"(src),"r"(addend));
}

unsigned long asm_tktlock (volatile __int64 *pmutex, __int64 my_token, __int64 next_token)
{
	asm (

		"mov %1, %%rax; "
		"mov %2, %%rdx\n\t"
		"lock cmpxchg %%rdx, (%0)\n\t"
		"jnz fail; "
	"success: ;"
		"mov $0, %%rax;"
		"jmp out;"
	"fail: ;"
		"mov $1, %%rax;"
	"out: ;"

	::"b"(pmutex), "r"(my_token), "r"(next_token):);
}



unsigned long asm_mutex (volatile __int64 *pmutex)
{
	asm (

		"xor %%rax, %%rax\n\t"
		"mov $1, %%rdx\n\t"
		"lock cmpxchg %%rdx, (%0)\n\t"
	::"b"(pmutex));
}

int BindToCpu(int cpu_num)
{
	long status;
	my_cpu_set_t cs;
	__MY_CPU_ZERO(&cs);
	__MY_CPU_SET(cpu_num, &cs);
	status = sched_setaffinity(0, sizeof(cs), (cpu_set_t*)&cs);

	if (status < 0) {
		printf("Error: unable to bind thread to core %d\n", cpu_num);
		exit(0);
	}
	return 1;

}	
unsigned long long get_physaddr(void *vaddr)
{
        unsigned long long addr;
        //static int idx=0;
	static int pagemap_fd=-1;
	if (pagemap_fd==-1) {
		pagemap_fd = open("/proc/self/pagemap", O_RDONLY);
	}
        int n = pread(pagemap_fd, &addr, 8, ((unsigned long long)vaddr / 4096) * 8);
        if (n != 8)
                return 0;
        if (!(addr & (1ULL<<63)))
                return 0;
        addr &= (1ULL<<54)-1;
        addr <<= 12;
        return addr + ((unsigned long long)vaddr  & (4096-1));
}

char *get_buffer_mapped_to_specific_cha(int max_cha_count, int tcha, int num_clusters)
{
	struct _hash_data  *hash_obj;
	char *buf, *p;
	int sz = 400*1024;

	int cha_per_cluster = max_cha_count / num_clusters;
	int cluster_id = tcha / cha_per_cluster;	
	int target_cha = tcha  - (cluster_id * cha_per_cluster);
	//printf("clid=%d, tarcha=%d, chapc=%d\n", cluster_id, target_cha, cha_per_cluster);

	hash_mode = get_hash_mode();	
	
	hash_obj = init_hash(cha_per_cluster);
	if (hash_obj == NULL) {
		printf("Failed to create CHA hash object. Exiting..\n");
		exit(1);
	}
	buf = (char*)malloc(sz); // allocate 400K buffer
	p = buf;
	for (int i=0; i < sz; i+=64, p+=64)
		*p = (char)i;
	p = buf;
	for (int i=0; i < sz; i+=64, p+=64) {
		unsigned long long pa;
		pa = get_physaddr((void*)p);
		// first check whether the pa maps to the right cluster
		if (get_cluster_id (pa, num_clusters) != cluster_id) continue;
		// pa is in the right cluster
		if (get_cha_id(hash_obj, pa) == target_cha)
			return p;
	}
	printf("Unable to allocate the lock variable on specific CHA\n");
	return buf;
	

}

unsigned int get_processor_signature()
{
	cpuid_info_t info;
	cpuid(0x1, 0, &info);
	return info.eax;
}

unsigned short get_processor_model_id()
{
	uint64_t processor_signature;
	unsigned short cpu_model_id;
	processor_signature = get_processor_signature();
	//printf("Processor signature is %x\n",processor_signature);
	// the following line are from Intel Performance Counter Monitor
	cpu_model_id = ((processor_signature & 0xf0) >> 4) | (processor_signature & 0xf0000) >> 12;
	return cpu_model_id;
}

int is_skylake()
{
	unsigned short cpu_model_id = get_processor_model_id();

	return (cpu_model_id == 55); 

}

int is_icelake()
{
	unsigned short cpu_model_id = get_processor_model_id();

	return (cpu_model_id == 0x6A); 

}

int is_sapphire_rapids()
{
	unsigned short cpu_model_id = get_processor_model_id();

	return (cpu_model_id == 0x8F); // SPR

}
int is_emerald_rapids()
{
	unsigned short cpu_model_id = get_processor_model_id();

	return (cpu_model_id == 0xCF ); 
}

int is_granite_rapids()
{
	unsigned short cpu_model_id = get_processor_model_id();

	return (cpu_model_id == 0xAD ||  cpu_model_id == 0xAE); 
}

int is_diamond_rapids()
{
	unsigned short cpu_model_id = get_processor_model_id();

	return (cpu_model_id == 0xD5 ||  cpu_model_id == 0xD6); 
}

int is_sierra_forest()
{
	unsigned short cpu_model_id = get_processor_model_id();

	return (cpu_model_id == 0xAF || cpu_model_id == 0xB6); 

}

int get_cluster_id (unsigned long long pa, int num_clusters)
{
	int clid=0, clid_lo=0, clid_hi=0, clid_hex=0;
	if (num_clusters <= 1) return 0;
	if (hash_mode==3)
	{
		clid_lo = ((pa >> 22) ^ (pa >> 18) ^ (pa >> 11) ^ (pa >> 8))&1;
		if (num_clusters == 2) { // HEMI
			return clid_lo;
		} else if (num_clusters == 4) { //QUAD
			clid_hi = ((pa >> 23) ^ (pa >> 19) ^ (pa >> 12) ^ (pa >> 10) ^ (pa >> 9))&1;
			clid = (clid_lo) | (clid_hi<<1);
			return clid;
		}
		else if (num_clusters == 6) { //HEX
			unsigned long long pa2=0;
			pa2 = (pa >> 10) & (unsigned long long)0x3ffffffffffLL;
			clid_hex = pa2 % 3;
			clid_hi = ((pa >> 23) ^ (pa >> 19) ^ (pa >> 12) ^ (pa >> 10) ^ (pa >> 9))&1;
			clid = (clid_hex<<1) | (clid_hi);
			if (clid <0 || clid >=6) { printf("invalid clid %d\n", clid); exit(1); }
			return clid;
		}
	}
	else {
		clid_lo = ((pa >> 25) ^ (pa >> 17) ^ (pa >> 11) ^ (pa >> 8))&1;
		if (num_clusters == 2) { // HEMI
			return clid_lo;
		} else if (num_clusters == 4) { //QUAD
			if (hash_mode == 2)
				clid_hi = ((pa >> 26) ^ (pa >> 18) ^ (pa >> 12) ^ (pa >> 10) ^ (pa >> 9))&1;
			else
				clid_hi = ((pa >> 26) ^ (pa >> 18) ^ (pa >> 12) ^ (pa >> 9))&1;
			clid = (clid_lo) | (clid_hi<<1);
			return clid;
		}
	}
	return clid;

}

