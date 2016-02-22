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

#define BLKSIZE (32 * 1024 * 1024)

int main(int argc, char *argv[]){
	int fd, ret;
	char *buf;

	fd = open("/dev/sdb", O_DIRECT | O_RDWR | O_LARGEFILE);
	if(fd < 0){
		perror("open failed.");
		goto err;
	}

	if(posix_memalign((void**)&buf, 65536, BLKSIZE)){
		fprintf(stderr, "buf allocation failed.\n");
		goto err1;
	}

	ret = read(fd, buf, BLKSIZE);
	if(ret != BLKSIZE){
		fprintf(stderr, "read failed. %d\n", ret);
		goto err2;
	}

	printf("done\n");

err2:
	free(buf);
err1:
	close(fd);
err:
	return 0;
}
