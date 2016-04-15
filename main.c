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
int r_ratio = 100;
int sequential = 1;
char *fname = NULL;
int running = 1;
uint64_t start_ticks, cur_ticks, prev_ticks;
double ns_per_tick;
struct timespec start_tp;

int n_thread = 0;

struct thread_args {
	int id;
	uint64_t rcnt, prev_rcnt;
	uint64_t wcnt, prev_wcnt;;
	char *device;
	int blk_size;
	int blk_cnt;
	int r_ratio;
	int iodepth;
};


static void sig_handler(int sig){
	if(sig == SIGINT || sig == SIGTERM){
		running = 0;
		printf("SIGINT\n");
	}

	if(sig == SIGUSR1){
		if(running < n_thread) running++;
		fprintf(stderr, "SIGUSR1: increasing # of running threads to %d.\n", running);
	}

	if(sig == SIGUSR2){
		if(running > 1) running--;
		fprintf(stderr, "SIGUSR2: decreasing # of running threads to %d.\n", running);
	}
}

static void timer_handler(union sigval arg){
	uint64_t elapsed_ticks, diff_ticks, elapsed_ns, diff_ns;
	double total_rbw, total_riops, rbw, riops;
	double total_wbw, total_wiops, wbw, wiops;
	double temp_iops;
	uint64_t cur_rcnt, cur_wcnt;
	int i;
	struct thread_args *args = arg.sival_ptr;

	prev_ticks = cur_ticks;
	cur_ticks = getticks();

	elapsed_ticks = cur_ticks - start_ticks;
	elapsed_ns = elapsed_ticks * ns_per_tick;
	diff_ticks = cur_ticks - prev_ticks;
	diff_ns = diff_ticks * ns_per_tick;

	total_riops = total_wiops = 0;
	total_rbw = total_wbw = 0;
	riops = wiops = 0;
	rbw = wbw = 0;

	for(i = 0; i < n_thread; i++){
		cur_rcnt = args[i].rcnt;
		cur_wcnt = args[i].wcnt;

		temp_iops = (double)(cur_rcnt) / ((double)elapsed_ns * 1e-9);
		total_riops += temp_iops;
		total_rbw += (temp_iops * (double)(args[i].blk_size) * 1e-6);

		temp_iops = (double)(cur_wcnt) / ((double)elapsed_ns * 1e-9);
		total_wiops += temp_iops;
		total_wbw += (temp_iops * (double)(args[i].blk_size) * 1e-6);

		temp_iops = (double)(cur_rcnt - args[i].prev_rcnt) / ((double)diff_ns * 1e-9);
		riops += temp_iops;
		rbw += (temp_iops * (double)(args[i].blk_size) * 1e-6);

		temp_iops = (double)(cur_wcnt - args[i].prev_wcnt) / ((double)diff_ns * 1e-9);
		wiops += temp_iops;
		wbw += (temp_iops * (double)(args[i].blk_size) * 1e-6);

		args[i].prev_rcnt = cur_rcnt;
		args[i].prev_wcnt = cur_wcnt;
	}

	printf("[%lu]\t %d bytes %g ops\t%g ops\t%g MB/s\t%g MB/s\t%g ops\t%g ops\t%g MB/s\t%g MB/s\n",
		(unsigned long)(elapsed_ns * 1e-9) + start_tp.tv_sec, args[0].blk_size, total_riops, total_wiops, total_rbw, total_wbw, riops, wiops, rbw, wbw);	


}

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

#define MAX_IO_DEPTH (512)

void *run_aio(void *__arg){
	int fd, ret, blk_cnt, blk_size, r_ratio, iodepth, i, tid;
	struct thread_args *arg = (struct thread_args*)__arg;

	aio_context_t ctx;
	int complete[MAX_IO_DEPTH];
	int r[MAX_IO_DEPTH];
	struct iocb cb[MAX_IO_DEPTH];
	struct iocb *cbs[MAX_IO_DEPTH];
	char *buf[MAX_IO_DEPTH];
	struct io_event events[MAX_IO_DEPTH];
	int op_inflight;
	int op_issued;

	blk_cnt = arg->blk_cnt;
	blk_size = arg->blk_size;
	r_ratio = arg->r_ratio;
	arg->rcnt = arg->wcnt = 0;
	arg->prev_rcnt = arg->prev_wcnt = 0;
	iodepth = arg->iodepth;
	tid = arg->id;

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

	for(i = 0; i < MAX_IO_DEPTH; i++){
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

	printf("tid[%d] device: %s device_size: %ld blk_size: %d blk_cnt: %d r_ratio: %d\n", arg->id, arg->device, device_size, arg->blk_size, arg->blk_cnt, arg->r_ratio);


	while(running){
		if(running < (tid + 1)) continue;
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
				fprintf(stderr, "couldn't submit IOs");
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
				arg->rcnt++;
			} else {
				arg->wcnt++;
			}
		}
	}

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



void *run(void *__arg){
	int fd, ret, blk_cnt, blk_size, r_ratio, tid;
	char *buf = NULL;
	struct thread_args *arg = (struct thread_args*)__arg;

	blk_cnt = arg->blk_cnt;
	blk_size = arg->blk_size;
	r_ratio = arg->r_ratio;
	arg->rcnt = arg->wcnt = 0;
	arg->prev_rcnt = arg->prev_wcnt = 0;
	tid = arg->id;

	fd = open(arg->device, O_DIRECT | O_RDWR | O_LARGEFILE);
	if(fd < 0){
		perror("open failed.");
		goto err;
	}

	if(posix_memalign((void**)&buf, 65536, blk_size)){
		fprintf(stderr, "buf allocation failed.\n");
		goto err1;
	}

	printf("tid[%d] device: %s device_size: %ld blk_size: %d blk_cnt: %d r_ratio: %d\n", arg->id, arg->device, device_size, arg->blk_size, arg->blk_cnt, arg->r_ratio);

	while(running){
		if(running < (tid + 1)) continue;
		if(sequential){
			if(lseek(fd, 0, SEEK_CUR) + blk_size > device_size)
				if(lseek(fd, 0, SEEK_SET)){
					perror("lseek failed\n");
					goto err2;
				}
		} else{
			if(lseek(fd, (lrand48() % blk_cnt) * blk_size, SEEK_SET) < 0){
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
			arg->rcnt++;
		} else {
			ret = write(fd, buf, blk_size);
			if(blk_size != ret){
				perror("write failed\n");
				fprintf(stderr, "ret: %d\n", ret);
				goto err2;
			}
			arg->wcnt++;
		}
	}

err2:
	free(buf);
err1:
	close(fd);
err:
	pthread_exit(0);
}

int main(int argc, char *argv[]){
	int opt, i, aio = 0;
	struct sigevent sev;
	timer_t timerid;
	struct itimerspec its;
	pthread_t *tid;
	int blk_size = 0;
	struct thread_args *args;

	while((opt = getopt(argc, argv, "b:r:s:d:B:t:a:")) != -1){
		switch(opt){
			case 'a':
				aio = atoi(optarg);
				break;
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
			case 't':
				n_thread = atoi(optarg);
				break;
		}
	}

	if(fname == NULL || r_ratio < 0 || r_ratio > 100 || n_thread == 0){
		fprintf(stderr, "usage: %s [-B devicesize(bytes)] [-b blocksize(K)] [-r read ratio] [-s 0:random/1:seq] [-d device file] [-t n_thread]\n", argv[0]);
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
	if(signal(SIGUSR1, sig_handler) == SIG_ERR){
		perror("failed to establish SIGUSR1 handler");
		goto err;
	}
	if(signal(SIGUSR2, sig_handler) == SIG_ERR){
		perror("failed to establish SIGUSR2 handler");
		goto err;
	}

	tid = (pthread_t *)malloc(sizeof(pthread_t) * n_thread);
	args = (struct thread_args *)malloc(sizeof(struct thread_args) * n_thread);

	sev.sigev_notify = SIGEV_THREAD;
	sev.sigev_notify_function = timer_handler;
	sev.sigev_notify_attributes = NULL;
	sev.sigev_value.sival_ptr = args;
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

	for(i = 0; i < n_thread; i++){
		args[i].id = i;
		args[i].device = fname;
		args[i].blk_size = blk_size;
		args[i].blk_cnt = device_size / blk_size;
		args[i].r_ratio = r_ratio;
		args[i].iodepth = aio;
	}

	ns_per_tick = time_per_tick(1000, 100);
	start_ticks = cur_ticks = getticks();
	
	if(clock_gettime(CLOCK_REALTIME, &start_tp)){
		fprintf(stderr, "clock_gettime failed.\n");
		goto err;
	}

	running = n_thread;

	for(i = 0; i< n_thread; i++){
		if(aio > 0){
			if(pthread_create(&tid[i], NULL, run_aio, &args[i])){
				perror("pthread_create failed.");
				goto err;
			}
		} else {
			if(pthread_create(&tid[i], NULL, run, &args[i])){
				perror("pthread_create failed.");
				goto err;
			}
		}
	}

	for(i = 0; i< n_thread; i++){
		pthread_join(tid[i], NULL);
	}

err:
	free(fname);
	return 0;
}


