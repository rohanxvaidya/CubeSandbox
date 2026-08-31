// sigsend.c: send signal + integer parameter to a process
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 4) {
        fprintf(stderr, "Usage: %s <pid> <signame> <value>\n", argv[0]);
        return 1;
    }

    int pid = atoi(argv[1]);
    int val = atoi(argv[3]);
    int sig = 0;

    if (strcmp(argv[2], "SIGUSR1") == 0) sig = SIGUSR1;
    else if (strcmp(argv[2], "SIGUSR2") == 0) sig = SIGUSR2;
    else if (strcmp(argv[2], "SIGRTMIN") == 0) sig = SIGRTMIN;
    else if (strcmp(argv[2], "SIGRTMIN+1") == 0) sig = SIGRTMIN+1;
    else {
        fprintf(stderr, "Unsupported signal\n");
        return 1;
    }

    union sigval sv;
    sv.sival_int = val;
    sigqueue(pid, sig, sv);

    printf("Sent signal %d with value %d to pid %d\n", sig, val, pid);
    return 0;
}
