#ifndef SYMBOL_TABLE_H
#define SYMBOL_TABLE_H

#include <stdio.h>

typedef enum TypeKind {
    TYPE_UNKNOWN,
    TYPE_ERROR,
    TYPE_INT,
    TYPE_FLOAT,
    TYPE_DOUBLE,
    TYPE_CHAR,
    TYPE_BOOL,
    TYPE_VOID,
    TYPE_STRING
} TypeKind;

typedef enum SymbolKind {
    SYMBOL_VARIABLE,
    SYMBOL_CONSTANT,
    SYMBOL_FUNCTION,
    SYMBOL_PARAMETER
} SymbolKind;

typedef struct SymbolEntry {
    char *name;
    char *scope_name;
    TypeKind type_kind;

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
    TypeKind type_kind,
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

const char *type_kind_name(TypeKind type_kind);
int type_is_integral(TypeKind type_kind);
int type_is_numeric(TypeKind type_kind);
int type_is_condition(TypeKind type_kind);
int type_can_assign(TypeKind target_type, TypeKind value_type);
int type_can_compare(TypeKind left_type, TypeKind right_type);
TypeKind type_common_numeric(TypeKind left_type, TypeKind right_type);

void symbol_table_dump(FILE *out);
int symbol_table_semantic_error_count(void);

#endif
