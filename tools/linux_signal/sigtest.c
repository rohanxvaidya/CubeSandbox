#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>

// Volatile flags to avoid compiler optimization
static volatile int  received_sig = 0;
static volatile int  signal_param = 0;

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

    // Use unified handler for all signals
    sa.sa_sigaction = universal_handler;
    sa.sa_flags     = SA_SIGINFO;  // Enable signal parameter passing
    sigemptyset(&sa.sa_mask);

    // Register signals we want to handle
    sigaction(SIGUSR1,  &sa, NULL);
    sigaction(SIGUSR2,  &sa, NULL);
    sigaction(SIGRTMIN, &sa, NULL);
    sigaction(SIGRTMIN+1,&sa,NULL);

    int pid = getpid();
    printf("=== Program running, PID = %d ===\n", pid);
    printf("You can send signal + parameter in another terminal:\n");
    printf("Example (send value 123 with SIGUSR1):\n");
    printf("  ./sigsend %d SIGUSR1 123\n", pid);
    printf("Example (send value 456 with SIGRTMIN):\n");
    printf("  ./sigsend %d SIGRTMIN 456\n", pid);
    printf("-------------------------------------\n\n");

    // Main loop: running forever
    while (1) {
        printf("Main loop running...\n");
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
            switch (sig) {
                case SIGUSR1:
                    printf("? Action: Do Task A (print status)\n");
                    break;
                case SIGUSR2:
                    printf("? Action: Do Task B (reload config)\n");
                    break;
                case SIGRTMIN:
                    printf("? Action: Do Task C (clear cache)\n");
                    break;
                case SIGRTMIN+1:
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
