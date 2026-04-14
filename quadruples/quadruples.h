#ifndef QUADRUPLES_H
#define QUADRUPLES_H

#include <stdio.h>

typedef struct {
    char *op;
    char *arg1;
    char *arg2;
    char *result;
} Quadruple;

void quadruples_init(void);
void quadruples_free(void);

int quadruple_emit(const char *op, const char *arg1, const char *arg2, const char *result);
int quadruple_emit_label(const char *label);
void quadruple_patch_result(int index, const char *result);

char *quadruple_new_temp(void);
char *quadruple_new_label(void);

int quadruple_count(void);
const Quadruple *quadruple_at(int index);
void quadruples_print(FILE *stream);

#endif
