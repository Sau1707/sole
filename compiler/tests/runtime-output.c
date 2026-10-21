#include <assert.h>
#include <dirent.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char *sole_rt_output_path(const char *) __asm__("_sole.fn.output_path");
extern char *sole_rt_output_dir(const char *) __asm__("_sole.fn.output_dir");
extern uint64_t sole_stat_layout(int) __asm__("_sole.fn.stat_layout");

static void clean(void) {
    DIR *directory = opendir(".");
    assert(directory);
    struct dirent *entry;
    while ((entry = readdir(directory)))
        assert(strncmp(entry->d_name, ".sole-", 6) != 0);
    assert(closedir(directory) == 0);
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
    FILE *file = fopen("input", "wb");
    assert(file && fclose(file) == 0);
    assert(symlink("input", "link") == 0);
    char *resolved = sole_rt_output_path("link");
    char *expected = realpath("input", NULL);
    assert(expected && strcmp(resolved, expected) == 0);
    free(expected);
    free(resolved);

    assert(symlink("missing", "dangling") == 0);
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        sole_rt_output_path("dangling");
        _exit(99);
    }
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 1);
    struct stat before, after;
    assert(lstat("dangling", &after) == 0 && S_ISLNK(after.st_mode));
    assert(access("missing", F_OK) != 0);
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
    puts("Passed runtime output staging checks.");
    return 0;
}
