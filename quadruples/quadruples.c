#include "quadruples.h"

#include <stdlib.h>
#include <string.h>

static Quadruple *quadruples = NULL;
static int quadruple_capacity = 0;
static int quadruple_total = 0;
static int next_temp_id = 0;
static int next_label_id = 0;

static void *checked_malloc(size_t size) {
    void *memory = malloc(size);

    if (!memory) {
        perror("malloc");
        exit(EXIT_FAILURE);
    }

    return memory;
}

static char *duplicate_text(const char *text) {
    size_t length;
    char *copy;

    if (!text) {
        return NULL;
    }

    length = strlen(text) + 1;
    copy = checked_malloc(length);
    memcpy(copy, text, length);
    return copy;
}

static void ensure_capacity(void) {
    Quadruple *grown;
    int new_capacity;

    if (quadruple_total < quadruple_capacity) {
        return;
    }

    new_capacity = quadruple_capacity == 0 ? 32 : quadruple_capacity * 2;
    grown = realloc(quadruples, (size_t)new_capacity * sizeof(*grown));

    if (!grown) {
        perror("realloc");
        exit(EXIT_FAILURE);
    }

    quadruples = grown;
    quadruple_capacity = new_capacity;
}

static char *formatted_name(const char *prefix, int value) {
    int needed = snprintf(NULL, 0, "%s%d", prefix, value);
    char *name = checked_malloc((size_t)needed + 1);

    snprintf(name, (size_t)needed + 1, "%s%d", prefix, value);
    return name;
}

void quadruples_init(void) {
    quadruples_free();
    next_temp_id = 0;
    next_label_id = 0;
}

void quadruples_free(void) {
    int index;

    for (index = 0; index < quadruple_total; ++index) {
        free(quadruples[index].op);
        free(quadruples[index].arg1);
        free(quadruples[index].arg2);
        free(quadruples[index].result);
    }

    free(quadruples);
    quadruples = NULL;
    quadruple_capacity = 0;
    quadruple_total = 0;
    next_temp_id = 0;
    next_label_id = 0;
}

int quadruple_emit(const char *op, const char *arg1, const char *arg2, const char *result) {
    Quadruple *quadruple;

    ensure_capacity();
    quadruple = &quadruples[quadruple_total];

    quadruple->op = duplicate_text(op ? op : "-");
    quadruple->arg1 = duplicate_text(arg1 ? arg1 : "-");
    quadruple->arg2 = duplicate_text(arg2 ? arg2 : "-");
    quadruple->result = duplicate_text(result ? result : "-");

    ++quadruple_total;
    return quadruple_total - 1;
}

int quadruple_emit_label(const char *label) {
    return quadruple_emit("LABEL", "-", "-", label);
}

void quadruple_patch_result(int index, const char *result) {
    if (index < 0 || index >= quadruple_total) {
        return;
    }

    free(quadruples[index].result);
    quadruples[index].result = duplicate_text(result ? result : "-");
}

char *quadruple_new_temp(void) {
    return formatted_name("t", next_temp_id++);
}

char *quadruple_new_label(void) {
    return formatted_name("L", next_label_id++);
}

int quadruple_count(void) {
    return quadruple_total;
}

const Quadruple *quadruple_at(int index) {
    if (index < 0 || index >= quadruple_total) {
        return NULL;
    }

    return &quadruples[index];
}

void quadruples_print(FILE *stream) {
    int index;

    fprintf(stream, "\nQuadruples\n");

    if (quadruple_total == 0) {
        fprintf(stream, "(empty)\n");
        return;
    }

    for (index = 0; index < quadruple_total; ++index) {
        fprintf(
            stream,
            "(%s, %s, %s, %s)\n",
            quadruples[index].op,
            quadruples[index].arg1,
            quadruples[index].arg2,
            quadruples[index].result
        );
    }
}
