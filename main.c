#define _GNU_SOURCE

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

off_t device_size = 0;
int blk_size = 4096;
int n_blk;
int r_ratio = 100;
int sequential = 1;
char *fname = NULL;
int running = 1;
uint64_t start_ticks, cur_ticks, prev_ticks;
double ns_per_tick;
uint64_t rcnt = 0, wcnt = 0, prev_rcnt = 0, prev_wcnt = 0;
struct timespec start_tp;

static void sig_handler(int sig){
	if(sig == SIGINT || sig == SIGTERM){
		running = 0;
		printf("SIGINT\n");
	}
}

static void timer_handler(union sigval arg){
	uint64_t elapsed_ticks, diff_ticks, elapsed_ns, diff_ns;
	double total_rbw, total_riops, rbw, riops;
	double total_wbw, total_wiops, wbw, wiops;
	uint64_t cur_rcnt, cur_wcnt;

	prev_ticks = cur_ticks;
	cur_ticks = getticks();
	cur_rcnt = rcnt;
	cur_wcnt = wcnt;

	elapsed_ticks = cur_ticks - start_ticks;
	elapsed_ns = elapsed_ticks * ns_per_tick;
	diff_ticks = cur_ticks - prev_ticks;
	diff_ns = diff_ticks * ns_per_tick;

	total_riops = (double)(cur_rcnt) / ((double)elapsed_ns * 1e-9);
	total_rbw = total_riops * blk_size * 1e-6;
	total_wiops = (double)(cur_wcnt) / ((double)elapsed_ns * 1e-9);
	total_wbw = total_wiops * blk_size * 1e-6;

	riops = (double)(cur_rcnt - prev_rcnt) / ((double)diff_ns * 1e-9);
	rbw = riops * blk_size * 1e-6;
	wiops = (double)(cur_wcnt - prev_wcnt) / ((double)diff_ns * 1e-9);
	wbw = wiops * blk_size * 1e-6;

	printf("[%lu]\t%g ops\t%g ops\t%g MB/s\t%g MB/s\t%g ops\t%g ops\t%g MB/s\t%g MB/s\n",
		(unsigned long)(elapsed_ns * 1e-9) + start_tp.tv_sec, total_riops, total_wiops, total_rbw, total_wbw, riops, wiops, rbw, wbw);	

	prev_rcnt = cur_rcnt;
	prev_wcnt = cur_wcnt;

}

void run(void){
	int fd, ret;
	struct stat stat_buf;
	char *buf = NULL;

	fd = open(fname, O_DIRECT | O_RDWR | O_LARGEFILE);
	if(fd < 0){
		perror("open failed.");
		goto err;
	}

	if(posix_memalign((void**)&buf, 65536, blk_size)){
		fprintf(stderr, "buf allocation failed.\n");
		goto err1;
	}

	if(device_size == 0){
		if(fstat(fd, &stat_buf)){
			perror("fstat failed.");
			goto err2;
		}
		device_size = stat_buf.st_size;
	}
	n_blk = device_size / blk_size;
	rcnt = wcnt = 0;

	printf("fname: %s device_size: %ld blk_size: %d n_blk: %d\n", fname, device_size, blk_size, n_blk);

	start_ticks = cur_ticks = getticks();
	if(clock_gettime(CLOCK_REALTIME, &start_tp)){
		fprintf(stderr, "clock_gettime failed.\n");
		goto err2;
	}

	while(running){
		if(sequential){
			if(lseek(fd, 0, SEEK_CUR) + blk_size > device_size)
				if(lseek(fd, 0, SEEK_SET)){
					perror("lseek failed\n");
					goto err2;
				}
		} else{
			if(lseek(fd, (lrand48() % n_blk) * blk_size, SEEK_SET) < 0){
				perror("lseek failed\n");
				goto err2;
			}
		}

		if(lrand48() % 100 < r_ratio){
			ret = read(fd, buf, blk_size);
			if(ret != blk_size){
				perror("read failed\n");
				fprintf(stderr, "fd: %d ret: %d\n", fd, ret);
				goto err2;
			}
			rcnt++;
		} else {
			ret = write(fd, buf, blk_size);
			if(blk_size != ret){
				perror("write failed\n");
				fprintf(stderr, "ret: %d\n", ret);
				goto err2;
			}
			wcnt++;
		}
	}

err2:
	free(buf);
err1:
	close(fd);
err:
	return;
}

int main(int argc, char *argv[]){
	int opt;
	struct sigevent sev;
	timer_t timerid;
	struct itimerspec its;

	while((opt = getopt(argc, argv, "b:r:s:d:B:")) != -1){
		switch(opt){
			case 'b':
				blk_size = atoi(optarg) * 1024;
				break;
			case 'r':
				r_ratio = atoi(optarg);
				break;
			case 's':
				sequential = atoi(optarg) ? : 0;
				break;
			case 'd':
				fname = strdup(optarg);
				break;
			case 'B':
				device_size = atol(optarg);
				break;
		}
	}

	if(fname == NULL || r_ratio < 0 || r_ratio > 100){
		fprintf(stderr, "usage: %s [-B devicesize(bytes)] [-b blocksize(K)] [-r read ratio] [-s 0:random/1:seq] [-d device file]\n", argv[0]);
		return -1;
	}

	printf("Establishing a SIGINT/SIGTERM handler\n");
	if(signal(SIGINT, sig_handler) == SIG_ERR){
		perror("failed to establish SIGINT handler");
		goto err;
	}
	if(signal(SIGTERM, sig_handler) == SIG_ERR){
		perror("failed to establish SIGINT handler");
		goto err;
	}

	sev.sigev_notify = SIGEV_THREAD;
	sev.sigev_notify_function = timer_handler;
	sev.sigev_notify_attributes = NULL;
	sev.sigev_value.sival_ptr = NULL;
	if(timer_create(CLOCK_REALTIME, &sev, &timerid) == -1){
		fprintf(stderr, "failed to create a timer\n");
		goto err;
	}

	printf("timer ID is 0x%lx\n", (long) timerid);

	its.it_value.tv_sec = 1;
	its.it_value.tv_nsec = 0;
	its.it_interval.tv_sec = 1;
	its.it_interval.tv_nsec = 0;

	if(timer_settime(timerid, 0, &its, NULL) == -1){
		fprintf(stderr, "timer_settime failed\n");
		goto err;
	}

	ns_per_tick = time_per_tick(1000, 100);
	run();

err:
	free(fname);
	return 0;
}


