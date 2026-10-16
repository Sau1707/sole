#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef SOLE_HOME
#define SOLE_HOME "."
#endif

static int argument_count;
static char **argument_values;

extern char **environ;

int sole_rt_process_run(const char *executable, char *const argv[], int *status) {
    pid_t child;
    int error = posix_spawnp(&child, executable, NULL, NULL, argv, environ);
    if (error) return error;
    while (waitpid(child, status, 0) < 0) {
        if (errno != EINTR) return errno;
    }
    return 0;
}

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
                length = snprintf(runtime, sizeof(runtime), "%s/lib/runtime/core.ll", candidate);
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

static char *output_path(const char *path) {
    char *resolved = realpath(path, NULL);
    if (resolved) return resolved;
    if (errno != ENOENT) return NULL;
    struct stat info;
    if (lstat(path, &info) == 0) {
        errno = S_ISLNK(info.st_mode) ? ENOLINK : ENOENT;
        return NULL;
    }
    if (errno != ENOENT) return NULL;
    return strdup(path);
}

char *sole_rt_output_path(const char *path) {
    char *resolved = output_path(path);
    if (!resolved) {
        fprintf(stderr, "sole: %s: %s\n", path,
                errno == ENOLINK ? "dangling output symlink" : strerror(errno));
        exit(1);
    }
    return resolved;
}

static char *sibling_template(const char *path, const char *name) {
    const char *slash = strrchr(path, '/');
    size_t parent = slash ? (size_t)(slash - path + 1) : 0;
    char *temporary = malloc(parent + strlen(name) + 1);
    if (!temporary) return NULL;
    memcpy(temporary, path, parent);
    strcpy(temporary + parent, name);
    return temporary;
}

char *sole_rt_output_dir(const char *output) {
    char *path = sibling_template(output, ".sole-output-XXXXXX");
    if (!path) fail("out of memory");
    if (!mkdtemp(path)) {
        int error = errno;
        free(path);
        fail(strerror(error));
    }
    return path;
}

const char *sole_rt_atomic_write_file(const char *path, const char *data, int64_t length) {
    if (length < 0 || (uint64_t)length > SIZE_MAX) return "invalid file length";
    char *resolved = output_path(path);
    if (!resolved) return errno == ENOLINK ? "dangling output symlink" : strerror(errno);
    struct stat original;
    const char *message = NULL;
    if (stat(resolved, &original) != 0) {
        message = strerror(errno);
    } else if (!S_ISREG(original.st_mode)) {
        message = "cannot atomically format a non-regular file";
    } else if (original.st_nlink != 1) {
        message = "cannot atomically format a file with multiple hard links";
    } else if (access(resolved, W_OK) != 0) {
        message = strerror(errno);
    }
    if (message) {
        free(resolved);
        return message;
    }
    char *temporary = sibling_template(resolved, ".sole-format-XXXXXX");
    if (!temporary) {
        free(resolved);
        return "out of memory";
    }
    int descriptor = mkstemp(temporary);
    if (descriptor < 0) {
        message = strerror(errno);
        free(temporary);
        free(resolved);
        return message;
    }
    size_t written = 0;
    while (written < (size_t)length) {
        size_t remaining = (size_t)length - written;
        if (remaining > (size_t)SSIZE_MAX) remaining = (size_t)SSIZE_MAX;
        ssize_t count = write(descriptor, data + written, remaining);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) {
            message = count == 0 ? "short write while formatting" : strerror(errno);
            break;
        }
        written += (size_t)count;
    }
    struct stat staged;
    if (!message && fstat(descriptor, &staged) != 0) message = strerror(errno);
    if (!message && (staged.st_uid != original.st_uid || staged.st_gid != original.st_gid) &&
        fchown(descriptor, original.st_uid, original.st_gid) != 0) message = strerror(errno);
    if (!message && fchmod(descriptor, original.st_mode & 07777) != 0) message = strerror(errno);
    if (!message && fsync(descriptor) != 0) message = strerror(errno);
    if (close(descriptor) != 0 && !message) message = strerror(errno);
    struct stat current;
    if (!message) {
        if (lstat(resolved, &current) != 0) message = strerror(errno);
        else if (current.st_dev != original.st_dev || current.st_ino != original.st_ino ||
                 current.st_nlink != 1) message = "file changed while formatting";
    }
    if (!message && rename(temporary, resolved) != 0) message = strerror(errno);
    if (message) unlink(temporary);
    free(temporary);
    free(resolved);
    return message;
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
