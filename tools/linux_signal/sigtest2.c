#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>

// Volatile flags to avoid compiler optimization
static volatile int  received_sig = 0;
static volatile int  signal_param = 0;

// ?????????SIGRTMIN/SIGRTMIN+1(??????)
// ??:SIGRTMIN?Linux????34,SIGRTMIN+1?35(???kill -l??)
#define MY_SIGRTMIN  34
#define MY_SIGRTMIN1 35

/**
 * Unified signal handler for ALL signals
 * Only set flags, DO NOT use printf here (unsafe in async context)
 */
void universal_handler(int sig, siginfo_t *info, void *ucontext) {
    // Record which signal was received
    received_sig = sig;

    // Get the integer parameter passed with the signal (if any)
    // For real-time signals: info->si_value.sival_int is the parameter
    signal_param = info->si_value.sival_int;
}

int main() {
    struct sigaction sa;

    int cpu_id = sched_getcpu();
    
    if (cpu_id < 0) {
        perror("sched_getcpu failed");
        return 1;
    }
    
    printf("On CPU core: %d\n", cpu_id);

    // Use unified handler for all signals
    sa.sa_sigaction = universal_handler;
    sa.sa_flags     = SA_SIGINFO;  // Enable signal parameter passing
    sigemptyset(&sa.sa_mask);

    // Register signals we want to handle
    sigaction(SIGUSR1,  &sa, NULL);
    sigaction(SIGUSR2,  &sa, NULL);
    sigaction(SIGRTMIN, &sa, NULL);   // ????SIGRTMIN(34)
    sigaction(MY_SIGRTMIN1, &sa, NULL); // ????SIGRTMIN+1(35)

    int pid = getpid();
    printf("=== Program running, PID = %d ===\n", pid);
    printf("You can send signal + parameter in another terminal:\n");
    printf("  ./sigsend %d SIGUSR1  1001\n", pid);
    printf("  ./sigsend %d SIGUSR2  2002\n", pid);
    printf("  ./sigsend %d SIGRTMIN 9999\n", pid);
    printf("  ./sigsend %d SIGRTMIN+1 8888\n", pid);
    printf("-------------------------------------\n\n");

    // Main loop: running forever
    while (1) {
        cpu_id = sched_getcpu();
    
        if (cpu_id < 0) {
            perror("sched_getcpu failed");
            return 1;
        }
    
        printf("Main loop running on Core %d...\n", cpu_id);
        sleep(1);

        // Check if any signal received
        if (received_sig != 0) {
            int sig   = received_sig;
            int param = signal_param;

            // Reset flags
            received_sig = 0;
            signal_param = 0;

            // Safely handle signal and parameter in main loop
            printf("\n[!] Received SIGNAL: %d\n", sig);
            printf("[!] Parameter value: %d\n", param);

            // Do different tasks based on signal type
            // ????????case??,??"?????"??
            switch (sig) {
                case SIGUSR1:  // SIGUSR1???(??10)
                    printf("? Action: Do Task A (print status)\n");
                    break;
                case SIGUSR2:  // SIGUSR2???(??12)
                    printf("? Action: Do Task B (reload config)\n");
                    break;
                case MY_SIGRTMIN:  // ??SIGRTMIN(34)
                    printf("? Action: Do Task C (clear cache)\n");
                    break;
                case MY_SIGRTMIN1: // ??SIGRTMIN+1(35)
                    printf("? Action: Do Task D (output statistics)\n");
                    break;
                default:
                    printf("? Unknown signal\n");
            }
            printf("-------------------------------------\n\n");
        }
    }

    return 0;
}
