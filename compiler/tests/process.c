#include <assert.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>

extern int sole_rt_process_run(const char *, char *const [], int *);

static volatile sig_atomic_t interruptions;

static void tick(int signal) {
    (void)signal;
    interruptions++;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "child") == 0) {
        usleep(100000);
        return 23;
    }
    assert(argc == 2);
    char *child[] = {argv[0], "child", NULL};
    struct sigaction action = {.sa_handler = tick};
    sigemptyset(&action.sa_mask);
    assert(sigaction(SIGALRM, &action, NULL) == 0);
    struct itimerval timer = {.it_interval = {.tv_usec = 1000}, .it_value = {.tv_usec = 1000}};
    assert(setitimer(ITIMER_REAL, &timer, NULL) == 0);
    int status;
    assert(sole_rt_process_run(argv[0], child, &status) == 0);
    timer = (struct itimerval){0};
    assert(setitimer(ITIMER_REAL, &timer, NULL) == 0);
    assert(interruptions > 0);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 23);
    assert(waitpid(-1, &status, WNOHANG) == -1 && errno == ECHILD);

    FILE *file = fopen(argv[1], "w");
    assert(file);
    assert(fputs("exit 0\n", file) >= 0);
    assert(fclose(file) == 0);
    assert(chmod(argv[1], 0700) == 0);
    char *script[] = {argv[1], NULL};
    assert(sole_rt_process_run(argv[1], script, &status) == ENOEXEC);
    assert(chmod(argv[1], 0600) == 0);
    assert(sole_rt_process_run(argv[1], script, &status) == EACCES);
    assert(unlink(argv[1]) == 0);
    assert(sole_rt_process_run(argv[1], script, &status) == ENOENT);
    return 0;
}
