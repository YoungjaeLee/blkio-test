#include <sys/types.h>
#include <sys/stat.h>
#include <pthread.h>
#include <sys/time.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <linux/aio_abi.h>
#include <fcntl.h>
#include <string.h>
#include <inttypes.h>
#include <sched.h>
#include <signal.h>
#include <time.h>

#include "util.h"

double time_diff(struct timeval x , struct timeval y)
{
    double x_ms , y_ms , diff;
     
    x_ms = (double)x.tv_sec*1000000 + (double)x.tv_usec;
    y_ms = (double)y.tv_sec*1000000 + (double)y.tv_usec;
     
    diff = (double)y_ms - (double)x_ms;
     
    return diff;
}

double time_per_tick(int n, int del) {
  int i;

  double *td = (double*)malloc(n * sizeof(double));
  double *tv = (double*)malloc(n * sizeof(double));

  struct timeval tvs;
  struct timeval tve;

  uint64_t  ts;
  uint64_t te;

  for (i=0; i<n; i++) {

    gettimeofday(&tvs, NULL);
    ts = getticks();

    usleep(del);

    te = getticks();
    gettimeofday(&tve, NULL);

    td[i] = elapsed(te,ts);
    tv[i] = time_diff(tvs,tve);
  }

  double sum = 0.0;

  for(i=0; i<n; i++) {

    sum +=  1000.0 * tv[i] / td[i];

    //printf("ticks, %15g, time, %15g, ticks/usec, %15g, nsec/tick, %15g\n", td[i], tv[i], td[i] / tv[i], 1000.0 * tv[i] / td[i]);
    
  }
  return sum / n ;

}  


