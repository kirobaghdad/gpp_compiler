#ifndef SYMBOL_TABLE_H
#define SYMBOL_TABLE_H

#include <stdio.h>

typedef enum SymbolKind {
    SYMBOL_VARIABLE,
    SYMBOL_CONSTANT,
    SYMBOL_FUNCTION,
    SYMBOL_PARAMETER
} SymbolKind;

typedef struct SymbolEntry {
    char *name;
    char *type;
    char *scope_name;

    SymbolKind kind;

    int scope_id;
    int scope_level;
    int declaration_line;
    int is_initialized;
    int is_used;
    int has_default_value;
    
    struct SymbolEntry *next_in_scope;
    struct SymbolEntry *next_all;

} SymbolEntry;

void symbol_table_init(void);
void symbol_table_destroy(void);

void symbol_table_enter_scope(const char *label);
void symbol_table_leave_scope(void);

SymbolEntry *symbol_table_declare(
    const char *name,
    const char *type,
    SymbolKind kind,
    int is_initialized,
    int has_default_value,
    int declaration_line
);

SymbolEntry *symbol_table_lookup(const char *name);
SymbolEntry *symbol_table_lookup_current_scope(const char *name);

void symbol_table_mark_used(const char *name, int line_num);
void symbol_table_mark_initialized(const char *name, int line_num);
void symbol_table_report_semantic_error(const char *message, const char *name, int line_num);

void symbol_table_dump(FILE *out);
int symbol_table_semantic_error_count(void);

#endif
