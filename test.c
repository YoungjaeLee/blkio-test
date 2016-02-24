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
#include <pthread.h>

#include "util.h"

#define MAX_IO_DEPTH (512)

int measure_time = 60;
timer_t timerid;
struct sigevent sev;
int running = 0;
int n_thread = 1;
struct itimerspec its;

struct thread_args {
	int rcnt;
	int wcnt;
	char *device;
	int blk_size;
	int blk_cnt; 
	int r_ratio;
	int iodepth;
};

int io_setup(unsigned nr, aio_context_t *ctxp){
	return syscall(__NR_io_setup, nr, ctxp);
}

int io_destroy(aio_context_t ctx){
	return syscall(__NR_io_destroy, ctx);
}

int io_submit(aio_context_t ctx, long nr, struct iocb **iocbpp){
	return syscall(__NR_io_submit, ctx, nr, iocbpp);
}

int io_getevents(aio_context_t ctx, long min_nr, long max_nr, 
				struct io_event *events, struct timespec *timeout){
	return syscall(__NR_io_getevents, ctx, min_nr, max_nr, events, timeout);
}

void *do_measure_aio(void *__arg){
	int fd, blk_cnt, blk_size, ret, i;
	int rcnt, wcnt, r_ratio, iodepth;

	aio_context_t ctx;
	int complete[MAX_IO_DEPTH];
	int r[MAX_IO_DEPTH];
	struct iocb cb[MAX_IO_DEPTH];
	struct iocb *cbs[MAX_IO_DEPTH];
	char *buf[MAX_IO_DEPTH];
	struct io_event events[MAX_IO_DEPTH];
	int op_inflight;
	int op_issued;

	struct thread_args *arg = (struct thread_args *)__arg;

	blk_cnt = arg->blk_cnt;
	blk_size = arg->blk_size;
	r_ratio = arg->r_ratio;
	iodepth = arg->iodepth;
	ctx = 0;

	fd = open(arg->device, O_DIRECT | O_RDWR | O_LARGEFILE);
	if(fd < 0){
		perror("open failed.");
		goto err;
	}

	ret = io_setup(iodepth, &ctx);
	if(ret < 0){
		perror("io_setup error");
		pthread_exit(NULL);
	}

	for(i = 0; i< MAX_IO_DEPTH; i++){
		complete[i] = 1;
		memset(&cb[i], 0, sizeof(struct iocb));
		if(posix_memalign((void**)&buf[i], 65536, blk_size)){
			fprintf(stderr, "buf allocation failed.\n");
			goto err1;
		}
		cb[i].aio_data = i;
		cb[i].aio_fildes = fd;
		cb[i].aio_buf = (uint64_t)buf[i];
		cb[i].aio_nbytes = blk_size;
	}
	op_inflight = 0;

	rcnt = wcnt = 0;
	while(running){
		op_issued = 0;
		for(i = 0; (i < MAX_IO_DEPTH) && running; i++){
			if(complete[i] == 0) continue;

			complete[i] = 0;
			memset(&cb[i], 0, sizeof(struct iocb));
			cb[i].aio_data = i;
			cb[i].aio_fildes = fd;
			if(lrand48() % 100 < r_ratio){
				cb[i].aio_lio_opcode = IOCB_CMD_PREAD;
				r[i] = 1;
			} else {
				cb[i].aio_lio_opcode = IOCB_CMD_PWRITE;
				r[i] = 0;
			}

			cb[i].aio_buf = (uint64_t)buf[i];
			cb[i].aio_offset = (lrand48() % blk_cnt) * blk_size;
			cb[i].aio_nbytes = blk_size;

			cbs[op_issued] = &cb[i];
			op_issued++;

			if(op_inflight + op_issued == iodepth) break;
		}
		ret = io_submit(ctx, op_issued, cbs);
		if(ret != op_issued){
			if(ret < 0)
				perror("io_submit error");
			else
				fprintf(stderr, "cound not submit IOs");
			pthread_exit(NULL);
		}

		op_inflight += op_issued;

		ret = io_getevents(ctx, 1, iodepth, events, NULL);
		if(ret < 1){
			fprintf(stderr, "io_getevents error %d\n", ret);
			pthread_exit(NULL);
		}
		op_inflight -= ret;

		for(i = 0; i < ret; i++){
			if(events[i].res != blk_size){
				printf("io error: %ld %ld\n", events[i].res, events[i].res2);
				pthread_exit(NULL);
			}
			complete[events[i].data] = 1;
			if(r[events[i].data]){
				rcnt++;
			} else {
				wcnt++;
			}
		}
	}

	arg->rcnt = rcnt;
	arg->wcnt = wcnt;

	ret = io_destroy(ctx);
	if(ret < 0){
		perror("io_destroy error");
		pthread_exit(NULL);
	}

	for(i = 0; i< MAX_IO_DEPTH; i++)
		free(buf[i]);
err1:
	close(fd);
err:
	pthread_exit(0);
}



void *do_measure(void *__arg){
	int fd, blk_cnt, blk_size, ret;
	int rcnt, wcnt, r_ratio;
	char *buf;
	struct thread_args *arg = (struct thread_args *)__arg;

	blk_cnt = arg->blk_cnt;
	blk_size = arg->blk_size;
	r_ratio = arg->r_ratio;

	fd = open(arg->device, O_DIRECT | O_RDWR | O_LARGEFILE);
	if(fd < 0){
		perror("open failed.");
		goto err;
	}

	if(posix_memalign((void**)&buf, 65536, blk_size)){
		fprintf(stderr, "buf allocation failed.\n");
		goto err1;
	}

	rcnt = wcnt = 0;
	while(running){
		if(lseek(fd, (lrand48() % blk_cnt) * blk_size, SEEK_SET) < 0){
			perror("lseek failed\n");
			goto err2;
		}
		if(lrand48() % 100 < r_ratio){
			ret = read(fd, buf, blk_size);
			if(ret != blk_size){
				perror("read failed\n");
				goto err2;
			}
			rcnt++;
		} else {
			ret = write(fd, buf, blk_size);
			if(ret != blk_size){
				perror("write failed\n");
				goto err2;
			}
			wcnt++;
		}
	}

	arg->rcnt = rcnt;
	arg->wcnt = wcnt;

err2:
	free(buf);
err1:
	close(fd);
err:
	pthread_exit(0);
}

int measure_random_iops(char *device, off_t device_size, int blk_size, int r_ratio, int iodepth, int aio){
	int blk_cnt,  i;
	int rcnt, wcnt;
	uint64_t start_ticks, end_ticks;
	double ns_per_tick, riops, wiops;
	struct thread_args *args;
	pthread_t *tid;

	ns_per_tick = time_per_tick(1000, 100);
	blk_cnt = device_size / blk_size;
	rcnt = wcnt = 0;

	tid = (pthread_t *)malloc(sizeof(pthread_t) * n_thread); args = (struct thread_args *)malloc(sizeof(struct thread_args) * n_thread);
	for(i = 0; i < n_thread; i++){
		args[i].device = device;
		args[i].blk_size = blk_size;
		args[i].blk_cnt = blk_cnt;
		args[i].r_ratio = r_ratio;
		args[i].iodepth = iodepth;
	}

	its.it_value.tv_sec = measure_time;
	its.it_value.tv_nsec = 0;
	its.it_interval.tv_sec = 0;
	its.it_interval.tv_nsec = 0;
	if(timer_settime(timerid, 0, &its, NULL) == -1){
		fprintf(stderr, "timer_settime failed.\n");
		goto err;
	}

	running = 1;
	start_ticks = getticks();

	for(i = 0; i < n_thread; i++){
		if(aio == 1){
			if(pthread_create(&tid[i], NULL, do_measure_aio, &args[i])){
				perror("pthread_create failed.");
				goto err;
			}
		} else {
			if(pthread_create(&tid[i], NULL, do_measure, &args[i])){
				perror("pthread_create failed.");
				goto err;
			}
		}
	}

	for(i = 0; i < n_thread; i++){
		pthread_join(tid[i], NULL);
		rcnt += args[i].rcnt;
		wcnt += args[i].wcnt;
	}

	end_ticks = getticks();

	riops = 1e9 * rcnt / (ns_per_tick * elapsed(end_ticks, start_ticks));
	wiops = 1e9 * wcnt / (ns_per_tick * elapsed(end_ticks, start_ticks));

	printf("%s %d threads blk_size %d riops %g %g wiops %g %g iops %g %g\n",
		device, n_thread, blk_size, riops, riops*blk_size*1e-6, wiops, wiops*blk_size*1e-6, riops+wiops, (riops+wiops)*blk_size*1e-6);

err:
	return 0;
}


static void timer_handler(union sigval arg){
	running = 0;
}

void print_usage(char *name){
	printf("%s -d [device_file] -D [device_size]\n", name);
}

int main(int argc, char *argv[]){
	int opt, blk_size, initial_blk_size = 0, final_blk_size = 10 * 1024 * 1024, r_ratio = 100, iodepth = 128;
	int aio = 0;
	off_t device_size = 0;
	char *fname = NULL;

	while((opt = getopt(argc, argv, "f:d:D:s:e:t:r:n:a")) != -1){
		switch(opt){
			case 'f':
				fname = strdup(optarg);
				break;
			case 'd':
				iodepth = atoi(optarg);
				break;
			case 'D':
				device_size = atol(optarg);
				break;
			case 's':
				initial_blk_size = atoi(optarg);
				break;
			case 'e':
				final_blk_size = atoi(optarg);
				break;
			case 't':
				measure_time = atoi(optarg);
				break;
			case 'r':
				r_ratio = atoi(optarg);
				break;
			case 'n':
				n_thread = atoi(optarg);
				break;
			case 'a':
				aio = 1;
				break;
		}
	}

	if(fname == NULL || device_size == 0){
		print_usage(argv[0]);
		return 1;
	}

	sev.sigev_notify = SIGEV_THREAD;
	sev.sigev_notify_function = timer_handler;
	sev.sigev_notify_attributes = NULL;
	sev.sigev_value.sival_ptr = NULL;
	if(timer_create(CLOCK_REALTIME, &sev, &timerid) == -1){
		fprintf(stderr, "failed to create a timer.\n");
		goto err;
	}

	printf("Starting measuring random iops on %s, device_size: %ld, r_ratio: %d, iodepth: %d, aio: %d\n", 
		fname, device_size, r_ratio, iodepth, aio);
	fflush(stdout);

	blk_size = initial_blk_size ? : 4096;
	while(1){
		if(blk_size > final_blk_size) break;
		measure_random_iops(fname, device_size, blk_size, r_ratio, iodepth, aio);
		blk_size = 2 * blk_size;
	}

err:
	return 0;
}
