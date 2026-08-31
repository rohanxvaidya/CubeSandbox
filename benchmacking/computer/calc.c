#include <stdio.h>        // for printf()
#include <sys/time.h>    // for gettimeofday()
#include <unistd.h>        // for sleep()
#include <stdlib.h>
#include<time.h> 

long long calcFunc(int t)
{
    long long v;
    int i = 0;

    v = 1;
    for (i = 0; i < t; i++) {
        v = v * 1;
        v = v + 1;
    }
    return v;
}


int main()
{
    struct timeval start, end;
    unsigned  long duration_t;
 
    gettimeofday( &start, NULL );
    printf("start : %d.%d\n", start.tv_sec, start.tv_usec);
//    sleep(5);
    calcFunc(99000000);
    gettimeofday( &end, NULL );
    printf("end   : %d.%d\n", end.tv_sec, end.tv_usec);

    duration_t = 1000000 * (end.tv_sec-start.tv_sec)+ end.tv_usec-start.tv_usec;
    printf("Process duration time(us): %ld \n", duration_t);

    // printf("call another time duration.\n");
    // time_duration2();

    return 0;
}





int time_duration2() {
	int begintime,endtime;
	int i = 0;
	int a[1002];
	begintime=clock();
	for( i = 1; i <= 1000; i++){
		a[i] = rand()%200-100;
		printf("  %d",a[i]);
	}
	endtime = clock();
	printf("\n\nRunning Time：%dms\n", endtime-begintime);
	return 0;
}