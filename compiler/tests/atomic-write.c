#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern const char *sole_rt_atomic_write_file(const char *, const char *, int64_t)
    __asm__("_sole.fn.atomic_write_file");
extern char *sole_rt_output_path(const char *) __asm__("_sole.fn.output_path");
extern char *sole_rt_output_dir(const char *) __asm__("_sole.fn.output_dir");
extern uint64_t sole_stat_layout(int) __asm__("_sole.fn.stat_layout");
extern ssize_t __real_write(int, const void *, size_t);
extern int __real_close(int);
extern int __real_rename(const char *, const char *);
extern int __real_fchmod(int, mode_t);
extern int __real_fsync(int);

static enum { NONE, SHORT_ERROR, ZERO_WRITE, CLOSE_ERROR, RENAME_ERROR, SYNC_ERROR, MODE_ERROR, INTERRUPTED_WRITE } fault;
static int writes;

ssize_t __wrap_write(int fd, const void *data, size_t length) {
    if (fault == INTERRUPTED_WRITE && writes++ == 0) {
        errno = EINTR;
        return -1;
    }
    if (fault == SHORT_ERROR) {
        if (writes++ == 0) return __real_write(fd, data, length / 2);
        errno = ENOSPC;
        return -1;
    }
    if (fault == ZERO_WRITE) return 0;
    return __real_write(fd, data, length);
}

int __wrap_close(int fd) {
    int result = __real_close(fd);
    if (fault == CLOSE_ERROR) {
        errno = EIO;
        return -1;
    }
    return result;
}

int __wrap_rename(const char *from, const char *to) {
    if (fault == RENAME_ERROR) {
        errno = EACCES;
        return -1;
    }
    return __real_rename(from, to);
}

int __wrap_fchmod(int fd, mode_t mode) {
    if (fault == MODE_ERROR) {
        errno = EPERM;
        return -1;
    }
    return __real_fchmod(fd, mode);
}

int __wrap_fsync(int fd) {
    if (fault == SYNC_ERROR) {
        errno = ENOSPC;
        return -1;
    }
    return __real_fsync(fd);
}

static void put(const char *path, const char *text) {
    FILE *file = fopen(path, "wb");
    assert(file);
    assert(fwrite(text, 1, strlen(text), file) == strlen(text));
    assert(fclose(file) == 0);
}

static void contents(const char *path, const char *expected) {
    char text[128];
    FILE *file = fopen(path, "rb");
    assert(file);
    size_t size = fread(text, 1, sizeof(text), file);
    assert(size == strlen(expected));
    assert(memcmp(text, expected, size) == 0);
    assert(fclose(file) == 0);
}

static void clean(void) {
    DIR *directory = opendir(".");
    assert(directory);
    struct dirent *entry;
    while ((entry = readdir(directory)))
        assert(strncmp(entry->d_name, ".sole-", 6) != 0);
    assert(closedir(directory) == 0);
}

static void unchanged(const struct stat *before) {
    struct stat after;
    assert(stat("input", &after) == 0);
    assert(after.st_ino == before->st_ino);
    assert(after.st_mode == before->st_mode);
    assert(after.st_uid == before->st_uid && after.st_gid == before->st_gid);
    contents("input", "original");
    clean();
}

static void permission_failure(void) {
    assert(chmod("input", 0444) == 0);
    assert(chmod(".", 0777) == 0);
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        if (geteuid() == 0) {
            assert(setgid(65534) == 0);
            assert(setuid(65534) == 0);
        }
        assert(sole_rt_atomic_write_file("input", "changed", 7));
        clean();
        _exit(0);
    }
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    contents("input", "original");
    assert(chmod("input", 0640) == 0);
    assert(chmod(".", 0700) == 0);
}

int main(int argc, char **argv) {
    assert(sole_stat_layout(0) == sizeof(struct stat));
    assert(sole_stat_layout(1) == offsetof(struct stat, st_mode));
    assert(sole_stat_layout(2) == offsetof(struct stat, st_uid));
    assert(sole_stat_layout(3) == offsetof(struct stat, st_gid));
    assert(sole_stat_layout(4) == offsetof(struct stat, st_nlink));
    assert(sole_stat_layout(5) == offsetof(struct stat, st_dev));
    assert(sole_stat_layout(6) == offsetof(struct stat, st_ino));
    assert(argc == 2 && chdir(argv[1]) == 0);
    put("interrupted", "original");
    fault = INTERRUPTED_WRITE;
    writes = 0;
    assert(sole_rt_atomic_write_file("interrupted", "replacement", 11) == NULL);
    fault = NONE;
    assert(writes == 2);
    contents("interrupted", "replacement");
    assert(unlink("interrupted") == 0);
    put("input", "original");
    assert(chmod("input", 0640) == 0);
    struct stat before, after;
    assert(stat("input", &before) == 0);
    for (int injected = SHORT_ERROR; injected <= MODE_ERROR; injected++) {
        fault = injected;
        writes = 0;
        const char *error = sole_rt_atomic_write_file("input", "replacement", 11);
        fault = NONE;
        assert(error && *error);
        if (injected == SHORT_ERROR) assert(writes == 2);
        unchanged(&before);
    }
    assert(sole_rt_atomic_write_file("input", "", -1));
    unchanged(&before);
    permission_failure();

    assert(link("input", "alias") == 0);
    const char *error = sole_rt_atomic_write_file("input", "replacement", 11);
    assert(error && strstr(error, "multiple hard links"));
    unchanged(&before);
    contents("alias", "original");
    assert(unlink("alias") == 0);

    assert(symlink("input", "link") == 0);
    char *resolved = sole_rt_output_path("link");
    char *expected = realpath("input", NULL);
    assert(expected && strcmp(resolved, expected) == 0);
    free(expected);
    free(resolved);
    assert(sole_rt_atomic_write_file("link", "replacement", 11) == NULL);
    contents("input", "replacement");
    assert(lstat("link", &after) == 0 && S_ISLNK(after.st_mode));
    assert(stat("input", &after) == 0);
    assert(before.st_mode == after.st_mode);
    assert(before.st_uid == after.st_uid && before.st_gid == after.st_gid);
    assert(sole_rt_atomic_write_file("input", "", 0) == NULL);
    contents("input", "");
    clean();

    assert(symlink("missing", "dangling") == 0);
    error = sole_rt_atomic_write_file("dangling", "replacement", 11);
    assert(error && strstr(error, "dangling output symlink"));
    assert(lstat("dangling", &after) == 0 && S_ISLNK(after.st_mode));
    assert(access("missing", F_OK) != 0);
    clean();
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        sole_rt_output_path("dangling");
        _exit(99);
    }
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 1);
    resolved = sole_rt_output_path("missing");
    assert(strcmp(resolved, "missing") == 0);
    free(resolved);

    assert(mkdir("parent", 0700) == 0);
    char *staging = sole_rt_output_dir("parent/program");
    assert(strncmp(staging, "parent/", 7) == 0);
    assert(stat(staging, &after) == 0 && S_ISDIR(after.st_mode));
    assert((after.st_mode & 0777) == 0700);
    assert(stat("parent", &before) == 0 && before.st_dev == after.st_dev);
    assert(rmdir(staging) == 0);
    free(staging);
    child = fork();
    assert(child >= 0);
    if (child == 0) {
        sole_rt_output_dir("parent/missing/program");
        _exit(99);
    }
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 1);
    assert(access("parent/missing", F_OK) != 0);
    clean();
    puts("Passed atomic runtime writes and output staging checks.");
    return 0;
}
