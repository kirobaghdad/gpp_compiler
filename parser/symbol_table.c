#include "symbol_table.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Scope {
    int id;
    int level;
    char *label;
    struct Scope *parent;
    SymbolEntry *symbols_head;
    SymbolEntry *symbols_tail;
    struct Scope *next_all;
} Scope;

static Scope *current_scope = NULL;
static Scope *all_scopes_head = NULL;
static Scope *all_scopes_tail = NULL;
static SymbolEntry *all_symbols_head = NULL;
static SymbolEntry *all_symbols_tail = NULL;

static int next_scope_id = 0;
static int semantic_error_count = 0;

static char *copy_text(const char *text) {
    size_t len;
    char *copy;

    if (!text) {
        return NULL;
    }

    len = strlen(text) + 1;
    copy = (char *)malloc(len);
    if (!copy) {
        fprintf(stderr, "Out of memory while duplicating text.\n");
        exit(1);
    }

    memcpy(copy, text, len);
    return copy;
}

const char *type_kind_name(TypeKind type_kind) {
    switch (type_kind) {
        case TYPE_INT:
            return "int";
        case TYPE_FLOAT:
            return "float";
        case TYPE_DOUBLE:
            return "double";
        case TYPE_CHAR:
            return "char";
        case TYPE_BOOL:
            return "bool";
        case TYPE_VOID:
            return "void";
        case TYPE_STRING:
            return "string";
        case TYPE_ERROR:
            return "error";
        case TYPE_UNKNOWN:
        default:
            return "unknown";
    }
}

int type_is_integral(TypeKind type_kind) {
    return type_kind == TYPE_BOOL ||
           type_kind == TYPE_CHAR ||
           type_kind == TYPE_INT;
}

int type_is_numeric(TypeKind type_kind) {
    return type_is_integral(type_kind) ||
           type_kind == TYPE_FLOAT ||
           type_kind == TYPE_DOUBLE;
}

int type_is_condition(TypeKind type_kind) {
    return type_kind == TYPE_BOOL || type_is_numeric(type_kind);
}

int type_can_assign(TypeKind target_type, TypeKind value_type) {
    if (target_type == TYPE_UNKNOWN || value_type == TYPE_UNKNOWN ||
        target_type == TYPE_ERROR || value_type == TYPE_ERROR) {
        return 1;
    }

    if (target_type == value_type) {
        return 1;
    }

    if (target_type == TYPE_VOID || value_type == TYPE_VOID) {
        return 0;
    }

    if (type_is_numeric(target_type) && type_is_numeric(value_type)) {
        return 1;
    }

    return 0;
}

int type_can_compare(TypeKind left_type, TypeKind right_type) {
    if (left_type == TYPE_UNKNOWN || right_type == TYPE_UNKNOWN ||
        left_type == TYPE_ERROR || right_type == TYPE_ERROR) {
        return 1;
    }

    if (type_is_numeric(left_type) && type_is_numeric(right_type)) {
        return 1;
    }

    return left_type == right_type && left_type != TYPE_VOID;
}

TypeKind type_common_numeric(TypeKind left_type, TypeKind right_type) {
    if (!type_is_numeric(left_type) || !type_is_numeric(right_type)) {
        return TYPE_ERROR;
    }

    if (left_type == TYPE_DOUBLE || right_type == TYPE_DOUBLE) {
        return TYPE_DOUBLE;
    }

    if (left_type == TYPE_FLOAT || right_type == TYPE_FLOAT) {
        return TYPE_FLOAT;
    }

    return TYPE_INT;
}

static const char *symbol_kind_name(SymbolKind kind) {
    switch (kind) {
        case SYMBOL_VARIABLE:
            return "variable";
        case SYMBOL_CONSTANT:
            return "constant";
        case SYMBOL_FUNCTION:
            return "function";
        case SYMBOL_PARAMETER:
            return "parameter";
    }

    return "unknown";
}

static void report_semantic_error(const char *message, const char *name, int line_num) {
    if (name) {
        fprintf(stderr, "Semantic Error at line %d: %s '%s'\n", line_num, message, name);
    } else {
        fprintf(stderr, "Semantic Error at line %d: %s\n", line_num, message);
    }
    semantic_error_count++;
}

void symbol_table_report_semantic_error(const char *message, const char *name, int line_num) {
    report_semantic_error(message, name, line_num);
}

static void append_scope(Scope *scope) {
    if (!all_scopes_head) {
        all_scopes_head = scope;
        all_scopes_tail = scope;
        return;
    }

    all_scopes_tail->next_all = scope;
    all_scopes_tail = scope;
}

static void append_symbol(SymbolEntry *entry) {
    if (!all_symbols_head) {
        all_symbols_head = entry;
        all_symbols_tail = entry;
        return;
    }

    all_symbols_tail->next_all = entry;
    all_symbols_tail = entry;
}

static Scope *create_scope(const char *label, Scope *parent) {
    Scope *scope = (Scope *)calloc(1, sizeof(Scope));
    if (!scope) {
        fprintf(stderr, "Out of memory while creating scope.\n");
        exit(1);
    }

    scope->id = next_scope_id++;
    scope->level = parent ? parent->level + 1 : 0;
    scope->label = copy_text(label ? label : "scope");
    scope->parent = parent;
    append_scope(scope);
    return scope;
}

static void free_scopes(void) {
    Scope *scope = all_scopes_head;

    while (scope) {
        Scope *next = scope->next_all;
        free(scope->label);
        free(scope);
        scope = next;
    }
}

static void free_symbols(void) {
    SymbolEntry *entry = all_symbols_head;

    while (entry) {
        SymbolEntry *next = entry->next_all;
        free(entry->name);
        free(entry->scope_name);
        free(entry);
        entry = next;
    }
}

void symbol_table_init(void) {
    symbol_table_destroy();

    next_scope_id = 0;
    semantic_error_count = 0;
    current_scope = create_scope("global", NULL);
}

void symbol_table_destroy(void) {
    current_scope = NULL;
    free_symbols();
    free_scopes();
    all_scopes_head = NULL;
    all_scopes_tail = NULL;
    all_symbols_head = NULL;
    all_symbols_tail = NULL;
    next_scope_id = 0;
    semantic_error_count = 0;
}

void symbol_table_enter_scope(const char *label) {
    current_scope = create_scope(label, current_scope);
}

void symbol_table_leave_scope(void) {
    if (!current_scope || !current_scope->parent) {
        return;
    }

    current_scope = current_scope->parent;
}

SymbolEntry *symbol_table_lookup_current_scope(const char *name) {
    SymbolEntry *entry;

    if (!current_scope) {
        return NULL;
    }

    entry = current_scope->symbols_head;
    while (entry) {
        if (strcmp(entry->name, name) == 0) {
            return entry;
        }
        entry = entry->next_in_scope;
    }

    return NULL;
}

SymbolEntry *symbol_table_lookup(const char *name) {
    Scope *scope = current_scope;

    while (scope) {
        SymbolEntry *entry = scope->symbols_head;
        while (entry) {
            if (strcmp(entry->name, name) == 0) {
                return entry;
            }
            entry = entry->next_in_scope;
        }
        scope = scope->parent;
    }

    return NULL;
}

SymbolEntry *symbol_table_declare(
    const char *name,
    TypeKind type_kind,
    SymbolKind kind,
    int is_initialized,
    int has_default_value,
    int declaration_line
) {
    SymbolEntry *existing;
    SymbolEntry *entry;

    if (!current_scope) {
        return NULL;
    }

    existing = symbol_table_lookup_current_scope(name);
    if (existing) {
        report_semantic_error("redeclaration of identifier", name, declaration_line);
        return existing;
    }

    entry = (SymbolEntry *)calloc(1, sizeof(SymbolEntry));
    if (!entry) {
        fprintf(stderr, "Out of memory while creating symbol entry.\n");
        exit(1);
    }

    entry->name = copy_text(name);
    entry->scope_name = copy_text(current_scope->label);
    entry->type_kind = type_kind;
    entry->kind = kind;
    entry->scope_id = current_scope->id;
    entry->scope_level = current_scope->level;
    entry->declaration_line = declaration_line;
    entry->is_initialized = is_initialized;
    entry->has_default_value = has_default_value;

    if (!current_scope->symbols_head) {
        current_scope->symbols_head = entry;
        current_scope->symbols_tail = entry;
    } else {
        current_scope->symbols_tail->next_in_scope = entry;
        current_scope->symbols_tail = entry;
    }

    append_symbol(entry);
    return entry;
}

void symbol_table_mark_used(const char *name, int line_num) {
    SymbolEntry *entry = symbol_table_lookup(name);

    if (!entry) {
        report_semantic_error("use of undeclared identifier", name, line_num);
        return;
    }

    entry->is_used = 1;
}

void symbol_table_mark_initialized(const char *name, int line_num) {
    SymbolEntry *entry = symbol_table_lookup(name);

    if (!entry) {
        report_semantic_error("assignment to undeclared identifier", name, line_num);
        return;
    }

    entry->is_initialized = 1;
}

void symbol_table_dump(FILE *out) {
    SymbolEntry *entry = all_symbols_head;

    fprintf(out, "\nSymbol Table\n");
    fprintf(out, "-----------------------------------------------------------------------------------------\n");
    fprintf(out, "%-16s %-10s %-10s %-14s %-7s %-6s %-6s %-7s %-7s\n",
            "Name", "Type", "Kind", "Scope", "Level", "Line", "Init", "Used", "Default");
    fprintf(out, "-----------------------------------------------------------------------------------------\n");

    while (entry) {
        fprintf(out, "%-16s %-10s %-10s %-14s %-7d %-6d %-6s %-7s %-7s\n",
                entry->name,
                type_kind_name(entry->type_kind),
                symbol_kind_name(entry->kind),
                entry->scope_name ? entry->scope_name : "-",
                entry->scope_level,
                entry->declaration_line,
                entry->is_initialized ? "yes" : "no",
                entry->is_used ? "yes" : "no",
                entry->has_default_value ? "yes" : "no");
        entry = entry->next_all;
    }

    fprintf(out, "-----------------------------------------------------------------------------------------\n");
    fprintf(out, "Semantic errors: %d\n", semantic_error_count);
}

int symbol_table_semantic_error_count(void) {
    return semantic_error_count;
}
