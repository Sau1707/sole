#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef SOLE_HOME
#define SOLE_HOME "."
#endif

static int argument_count;
static char **argument_values;

static void fail(const char *message) {
    fprintf(stderr, "sole: %s\n", message);
    exit(1);
}

void sole_rt_init(int argc, char **argv) {
    argument_count = argc;
    argument_values = argv;
}

int64_t sole_rt_arg_count(void) { return argument_count; }

const char *sole_rt_arg(int64_t index) {
    if (index < 0 || index >= argument_count) fail("argument index out of bounds");
    return argument_values[index];
}

const char *sole_rt_home(void) {
    const char *configured = getenv("SOLE_HOME");
    if (configured) return configured;
    static char home[PATH_MAX];
    if (home[0]) return home;
    char executable[PATH_MAX];
    ssize_t size = readlink("/proc/self/exe", executable, sizeof(executable) - 1);
    if (size > 0 && size < (ssize_t)sizeof(executable) - 1) {
        executable[size] = 0;
        char *slash = strrchr(executable, '/');
        if (slash) {
            *slash = 0;
            const char *suffixes[] = {"/../share/sole", "/.."};
            for (size_t i = 0; i < sizeof(suffixes) / sizeof(suffixes[0]); i++) {
                char candidate[PATH_MAX], runtime[PATH_MAX];
                int length = snprintf(candidate, sizeof(candidate), "%s%s", executable, suffixes[i]);
                if (length < 0 || length >= (int)sizeof(candidate)) continue;
                length = snprintf(runtime, sizeof(runtime), "%s/runtime/core.ll", candidate);
                if (length < 0 || length >= (int)sizeof(runtime)) continue;
                struct stat info;
                if (stat(runtime, &info) == 0 && S_ISREG(info.st_mode) && realpath(candidate, home)) return home;
            }
        }
    }
    return SOLE_HOME;
}

const char *sole_rt_lib_home(void) {
    const char *configured = getenv("SOLE_LIB");
    if (configured) return configured;
    static char library[PATH_MAX];
    int length = snprintf(library, sizeof(library), "%s/lib", sole_rt_home());
    if (length < 0 || length >= (int)sizeof(library)) fail("library path is too long");
    return library;
}

char *sole_rt_realpath(const char *path) {
    char *resolved = realpath(path, NULL);
    if (!resolved) fail(strerror(errno));
    return resolved;
}

int sole_rt_is_file(const char *path) {
    struct stat info;
    return stat(path, &info) == 0 && S_ISREG(info.st_mode);
}

char *sole_rt_temp_dir(void) {
    const char *root = getenv("TMPDIR");
    if (!root) root = access("/tmp/opencode", W_OK) == 0 ? "/tmp/opencode" : "/tmp";
    size_t size = strlen(root) + 32;
    char *path = malloc(size);
    if (!path) fail("out of memory");
    snprintf(path, size, "%s/sole-XXXXXX", root);
    if (!mkdtemp(path)) fail("cannot create temporary directory");
    return path;
}

int sole_rt_same_file(const char *a, const char *b) {
    struct stat first, second;
    return stat(a, &first) == 0 && stat(b, &second) == 0 &&
           first.st_dev == second.st_dev && first.st_ino == second.st_ino;
}

char *sole_rt_read_file(const char *path, int64_t *length) {
    FILE *file = fopen(path, "rb");
    if (!file) fail(strerror(errno));
    if (fseek(file, 0, SEEK_END) != 0) fail("cannot seek input file");
    long size = ftell(file);
    if (size < 0 || fseek(file, 0, SEEK_SET) != 0) fail("cannot measure input file");
    char *data = malloc((size_t)size + 1);
    if (!data) fail("out of memory");
    if (fread(data, 1, (size_t)size, file) != (size_t)size) fail("cannot read input file");
    if (fclose(file) != 0) fail("cannot close input file");
    data[size] = 0;
    *length = size;
    return data;
}

void sole_rt_write_file(const char *path, const char *data, int64_t length) {
    if (length < 0) fail("invalid file length");
    FILE *file = fopen(path, "wb");
    if (!file) fail(strerror(errno));
    if (fwrite(data, 1, (size_t)length, file) != (size_t)length) fail("cannot write output file");
    if (fclose(file) != 0) fail("cannot close output file");
}

uint64_t sole_rt_f64_bits(double value) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof(bits));
    return bits;
}
