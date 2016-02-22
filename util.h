#ifndef _UTIL_H
#define _UTIL_H

static __inline__ uint64_t getticks(void)
{
     unsigned int x, x0, x1;
     do {
	  __asm__ __volatile__ ("mftbu %0" : "=r"(x0));
	  __asm__ __volatile__ ("mftb %0" : "=r"(x));
	  __asm__ __volatile__ ("mftbu %0" : "=r"(x1));
     } while (x0 != x1);

     return (((uint64_t)x0) << 32) | x;
}

static __inline__ double elapsed(uint64_t t1, uint64_t t0)			
{									
  return (double)t1 - (double)t0;					
}

double time_diff(struct timeval x , struct timeval y);
double time_per_tick(int n, int del);

#endif
