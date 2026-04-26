#ifndef SYMBOL_TABLE_H
#define SYMBOL_TABLE_H

#include <stddef.h>
#include <stdio.h>

typedef enum {
    TYPE_INVALID = 0,
    TYPE_INT,
    TYPE_FLOAT,
    TYPE_DOUBLE,
    TYPE_CHAR,
    TYPE_BOOL,
    TYPE_VOID
} TypeKind;

typedef enum {
    SYMBOL_VARIABLE = 0,
    SYMBOL_PARAMETER,
    SYMBOL_FUNCTION
} SymbolKind;

typedef enum {
    SCOPE_GLOBAL = 0,
    SCOPE_FUNCTION,
    SCOPE_BLOCK
} ScopeKind;

typedef struct ParameterInfo {
    char *name;
    TypeKind type;
    int has_default_value;
    char *default_value;
} ParameterInfo;

typedef struct Symbol Symbol;

void symbol_table_init(void);
void symbol_table_free(void);

const char *type_kind_name(TypeKind type);
const char *symbol_kind_name(SymbolKind kind);
const char *scope_kind_name(ScopeKind kind);

Symbol *symbol_table_declare_variable(
    const char *name,
    TypeKind type,
    int is_const,
    int is_initialized,
    int line
);
Symbol *symbol_table_declare_parameter(
    const char *name,
    TypeKind type,
    int has_default_value,
    const char *default_value,
    int line
);
Symbol *symbol_table_declare_function(
    const char *name,
    TypeKind return_type,
    const ParameterInfo *parameters,
    size_t parameter_count,
    int is_definition,
    int line
);
void symbol_table_mark_function_defined(Symbol *function_symbol, int line);

void symbol_table_enter_block_scope(void);
void symbol_table_enter_function_scope(Symbol *function_symbol);
void symbol_table_leave_scope(void);

Symbol *symbol_table_lookup(const char *name);
Symbol *symbol_table_lookup_current_scope(const char *name);

void symbol_table_report_error(int line, const char *format, ...);

const char *symbol_name(const Symbol *symbol);
SymbolKind symbol_kind(const Symbol *symbol);
TypeKind symbol_type(const Symbol *symbol);
int symbol_is_const(const Symbol *symbol);
int symbol_is_initialized(const Symbol *symbol);
int symbol_has_default_value(const Symbol *symbol);
int symbol_is_defined(const Symbol *symbol);
size_t symbol_parameter_count(const Symbol *symbol);
size_t symbol_required_parameter_count(const Symbol *symbol);
TypeKind symbol_parameter_type(const Symbol *symbol, size_t index);
const char *symbol_parameter_default_value(const Symbol *symbol, size_t index);
void symbol_mark_used(Symbol *symbol);
void symbol_mark_initialized(Symbol *symbol);
void symbol_table_report_unused_variables(void);

void symbol_table_print(FILE *stream);
int symbol_table_error_count(void);

#endif
