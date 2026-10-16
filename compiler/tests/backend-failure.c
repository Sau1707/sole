#include <stdio.h>

extern char *LLVMCreateMessage(const char *message);

int LLVMTargetMachineEmitToFile(void *machine, void *module, char *filename,
                               int kind, char **error) {
    (void)machine;
    (void)module;
    (void)kind;
    FILE *file = fopen(filename, "wb");
    if (file) {
        fputs("partial object", file);
        fclose(file);
    }
    *error = LLVMCreateMessage("injected object emission failure");
    return 1;
}
