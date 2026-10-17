/* AI-assisted isolated fault injection; never load into a live node process. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int is_candidate(FILE *stream)
{
    char link[64], path[4096];
    ssize_t size;
    snprintf(link, sizeof(link), "/proc/self/fd/%d", fileno(stream));
    size = readlink(link, path, sizeof(path) - 1);
    if (size < 0)
        return 0;
    path[size] = 0;
    return strstr(path, "/.board-write-") != NULL;
}

size_t fwrite(const void *ptr, size_t size, size_t count, FILE *stream)
{
    static size_t (*real_fwrite)(const void *, size_t, size_t, FILE *);
    const char *fault = getenv("BOARD_TEST_FAULT");
    if (!real_fwrite)
        real_fwrite = dlsym(RTLD_NEXT, "fwrite");
    if (fault && !strcmp(fault, "short-write") && is_candidate(stream)) {
        errno = ENOSPC;
        return 0;
    }
    return real_fwrite(ptr, size, count, stream);
}

int fclose(FILE *stream)
{
    static int (*real_fclose)(FILE *);
    const char *fault = getenv("BOARD_TEST_FAULT");
    int fail = fault && !strcmp(fault, "close") && is_candidate(stream);
    if (!real_fclose)
        real_fclose = dlsym(RTLD_NEXT, "fclose");
    int result = real_fclose(stream);
    if (fail) {
        errno = EIO;
        return EOF;
    }
    return result;
}

int fsync(int fd)
{
    static int (*real_fsync)(int);
    static int interrupted;
    struct stat st;
    const char *fault = getenv("BOARD_TEST_FAULT");
    if (!real_fsync)
        real_fsync = dlsym(RTLD_NEXT, "fsync");
    if (fault && !fstat(fd, &st)) {
        if (!strcmp(fault, "interrupt-once") && !interrupted++) {
            errno = EINTR;
            return -1;
        }
        if ((!strcmp(fault, "file-sync") && S_ISREG(st.st_mode)) ||
            (!strcmp(fault, "dir-sync") && S_ISDIR(st.st_mode))) {
            errno = EIO;
            return -1;
        }
        if (!strcmp(fault, "exit-before-rename") && S_ISREG(st.st_mode))
            _exit(99);
    }
    return real_fsync(fd);
}

int rename(const char *old, const char *new)
{
    static int (*real_rename)(const char *, const char *);
    const char *fault = getenv("BOARD_TEST_FAULT");
    if (!real_rename)
        real_rename = dlsym(RTLD_NEXT, "rename");
    if (fault && !strcmp(fault, "rename")) {
        errno = EIO;
        return -1;
    }
    return real_rename(old, new);
}
