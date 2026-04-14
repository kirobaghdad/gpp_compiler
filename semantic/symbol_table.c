#include "symbol_table.h"

#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

struct Symbol {
    char *name;
    SymbolKind kind;
    TypeKind type;
    int line_declared;
    int scope_id;
    int scope_depth;
    int is_const;
    int is_initialized;
    int is_used;
    int has_default_value;
    int is_defined;
    ParameterInfo *parameters;
    size_t parameter_count;
    struct Symbol *next_in_scope;
};

typedef struct Scope {
    int id;
    int depth;
    ScopeKind kind;
    char *label;
    struct Scope *parent;
    Symbol *symbols_head;
    Symbol *symbols_tail;
    struct Scope *next_all;
} Scope;

static Scope *global_scope = NULL;
static Scope *current_scope = NULL;
static Scope *all_scopes_head = NULL;
static Scope *all_scopes_tail = NULL;
static int next_scope_id = 0;
static int semantic_errors = 0;

static void *checked_malloc(size_t size) {
    void *memory = malloc(size);

    if (!memory) {
        perror("malloc");
        exit(EXIT_FAILURE);
    }

    return memory;
}

static char *duplicate_string(const char *text) {
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

static void free_parameter_list(ParameterInfo *parameters, size_t count) {
    size_t index;

    if (!parameters) {
        return;
    }

    for (index = 0; index < count; ++index) {
        free(parameters[index].name);
    }

    free(parameters);
}

static ParameterInfo *copy_parameter_list(const ParameterInfo *parameters, size_t count) {
    ParameterInfo *copy;
    size_t index;

    if (count == 0) {
        return NULL;
    }

    copy = checked_malloc(count * sizeof(*copy));

    for (index = 0; index < count; ++index) {
        copy[index].name = duplicate_string(parameters[index].name);
        copy[index].type = parameters[index].type;
        copy[index].has_default_value = parameters[index].has_default_value;
    }

    return copy;
}

static void report_semantic_error(int line, const char *format, ...) {
    va_list arguments;

    ++semantic_errors;

    fprintf(stderr, "Semantic Error at line %d: ", line);
    va_start(arguments, format);
    vfprintf(stderr, format, arguments);
    va_end(arguments);
    fputc('\n', stderr);
}

static Scope *create_scope(ScopeKind kind, Scope *parent, const char *label) {
    Scope *scope = checked_malloc(sizeof(*scope));

    scope->id = next_scope_id++;
    scope->depth = parent ? parent->depth + 1 : 0;
    scope->kind = kind;
    scope->label = duplicate_string(label);
    scope->parent = parent;
    scope->symbols_head = NULL;
    scope->symbols_tail = NULL;
    scope->next_all = NULL;

    if (!all_scopes_head) {
        all_scopes_head = scope;
    } else {
        all_scopes_tail->next_all = scope;
    }

    all_scopes_tail = scope;
    return scope;
}

static Symbol *find_symbol_in_scope(Scope *scope, const char *name) {
    Symbol *symbol;

    if (!scope) {
        return NULL;
    }

    for (symbol = scope->symbols_head; symbol; symbol = symbol->next_in_scope) {
        if (strcmp(symbol->name, name) == 0) {
            return symbol;
        }
    }

    return NULL;
}

static Symbol *append_symbol(
    Scope *scope,
    const char *name,
    SymbolKind kind,
    TypeKind type,
    int line
) {
    Symbol *symbol = checked_malloc(sizeof(*symbol));

    symbol->name = duplicate_string(name);
    symbol->kind = kind;
    symbol->type = type;
    symbol->line_declared = line;
    symbol->scope_id = scope->id;
    symbol->scope_depth = scope->depth;
    symbol->is_const = 0;
    symbol->is_initialized = 0;
    symbol->is_used = 0;
    symbol->has_default_value = 0;
    symbol->is_defined = 0;
    symbol->parameters = NULL;
    symbol->parameter_count = 0;
    symbol->next_in_scope = NULL;

    if (!scope->symbols_head) {
        scope->symbols_head = symbol;
    } else {
        scope->symbols_tail->next_in_scope = symbol;
    }

    scope->symbols_tail = symbol;
    return symbol;
}

static int function_signatures_match(
    const Symbol *function_symbol,
    TypeKind return_type,
    const ParameterInfo *parameters,
    size_t parameter_count
) {
    size_t index;

    if (function_symbol->type != return_type || function_symbol->parameter_count != parameter_count) {
        return 0;
    }

    for (index = 0; index < parameter_count; ++index) {
        if (function_symbol->parameters[index].type != parameters[index].type) {
            return 0;
        }
    }

    return 1;
}

static void print_symbol_details(FILE *stream, const Symbol *symbol) {
    size_t index;

    if (symbol->kind == SYMBOL_FUNCTION) {
        fprintf(stream, "%s(", symbol->is_defined ? "defined " : "declared ");

        for (index = 0; index < symbol->parameter_count; ++index) {
            if (index > 0) {
                fprintf(stream, ", ");
            }

            fprintf(stream, "%s", type_kind_name(symbol->parameters[index].type));

            if (symbol->parameters[index].name) {
                fprintf(stream, " %s", symbol->parameters[index].name);
            }

            if (symbol->parameters[index].has_default_value) {
                fprintf(stream, " = default");
            }
        }

        fprintf(stream, ")");
        return;
    }

    if (symbol->kind == SYMBOL_PARAMETER && symbol->has_default_value) {
        fprintf(stream, "default argument");
        return;
    }

    fprintf(stream, "-");
}

void symbol_table_init(void) {
    symbol_table_free();

    next_scope_id = 0;
    semantic_errors = 0;

    global_scope = create_scope(SCOPE_GLOBAL, NULL, "global");
    current_scope = global_scope;
}

void symbol_table_free(void) {
    Scope *scope = all_scopes_head;

    while (scope) {
        Scope *next_scope = scope->next_all;
        Symbol *symbol = scope->symbols_head;

        while (symbol) {
            Symbol *next_symbol = symbol->next_in_scope;

            free(symbol->name);
            free_parameter_list(symbol->parameters, symbol->parameter_count);
            free(symbol);
            symbol = next_symbol;
        }

        free(scope->label);
        free(scope);
        scope = next_scope;
    }

    global_scope = NULL;
    current_scope = NULL;
    all_scopes_head = NULL;
    all_scopes_tail = NULL;
    next_scope_id = 0;
    semantic_errors = 0;
}

const char *type_kind_name(TypeKind type) {
    switch (type) {
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
        case TYPE_INVALID:
        default:
            return "invalid";
    }
}

const char *symbol_kind_name(SymbolKind kind) {
    switch (kind) {
        case SYMBOL_VARIABLE:
            return "variable";
        case SYMBOL_PARAMETER:
            return "parameter";
        case SYMBOL_FUNCTION:
            return "function";
        default:
            return "unknown";
    }
}

const char *scope_kind_name(ScopeKind kind) {
    switch (kind) {
        case SCOPE_GLOBAL:
            return "global";
        case SCOPE_FUNCTION:
            return "function";
        case SCOPE_BLOCK:
            return "block";
        default:
            return "unknown";
    }
}

Symbol *symbol_table_declare_variable(
    const char *name,
    TypeKind type,
    int is_const,
    int is_initialized,
    int line
) {
    Symbol *existing;
    Symbol *symbol;

    existing = symbol_table_lookup_current_scope(name);
    if (existing) {
        report_semantic_error(line, "redeclaration of '%s' in the same scope", name);
        return existing;
    }

    symbol = append_symbol(current_scope, name, SYMBOL_VARIABLE, type, line);
    symbol->is_const = is_const;
    symbol->is_initialized = is_initialized;

    if (is_const && !is_initialized) {
        report_semantic_error(line, "const variable '%s' must be initialized", name);
    }

    return symbol;
}

Symbol *symbol_table_declare_parameter(
    const char *name,
    TypeKind type,
    int has_default_value,
    int line
) {
    Symbol *existing;
    Symbol *symbol;

    existing = symbol_table_lookup_current_scope(name);
    if (existing) {
        report_semantic_error(line, "duplicate parameter name '%s'", name);
        return existing;
    }

    symbol = append_symbol(current_scope, name, SYMBOL_PARAMETER, type, line);
    symbol->is_initialized = 1;
    symbol->has_default_value = has_default_value;
    return symbol;
}

Symbol *symbol_table_declare_function(
    const char *name,
    TypeKind return_type,
    const ParameterInfo *parameters,
    size_t parameter_count,
    int is_definition,
    int line
) {
    Symbol *existing;
    Symbol *symbol;

    existing = find_symbol_in_scope(global_scope, name);
    if (existing) {
        if (existing->kind != SYMBOL_FUNCTION) {
            report_semantic_error(line, "'%s' conflicts with an existing symbol", name);
            return existing;
        }

        if (!function_signatures_match(existing, return_type, parameters, parameter_count)) {
            report_semantic_error(line, "conflicting declaration for function '%s'", name);
            return existing;
        }

        if (is_definition) {
            symbol_table_mark_function_defined(existing, line);
        }

        return existing;
    }

    symbol = append_symbol(global_scope, name, SYMBOL_FUNCTION, return_type, line);
    symbol->is_defined = is_definition;
    symbol->parameters = copy_parameter_list(parameters, parameter_count);
    symbol->parameter_count = parameter_count;
    return symbol;
}

void symbol_table_mark_function_defined(Symbol *function_symbol, int line) {
    if (!function_symbol || function_symbol->kind != SYMBOL_FUNCTION) {
        return;
    }

    if (function_symbol->is_defined) {
        report_semantic_error(line, "redefinition of function '%s'", function_symbol->name);
        return;
    }

    function_symbol->is_defined = 1;
}

void symbol_table_enter_block_scope(void) {
    current_scope = create_scope(SCOPE_BLOCK, current_scope, NULL);
}

void symbol_table_enter_function_scope(Symbol *function_symbol) {
    size_t index;

    current_scope = create_scope(
        SCOPE_FUNCTION,
        current_scope,
        function_symbol ? function_symbol->name : NULL
    );

    if (!function_symbol) {
        return;
    }

    for (index = 0; index < function_symbol->parameter_count; ++index) {
        symbol_table_declare_parameter(
            function_symbol->parameters[index].name,
            function_symbol->parameters[index].type,
            function_symbol->parameters[index].has_default_value,
            function_symbol->line_declared
        );
    }
}

void symbol_table_leave_scope(void) {
    if (current_scope && current_scope->parent) {
        current_scope = current_scope->parent;
    }
}

Symbol *symbol_table_lookup(const char *name) {
    Scope *scope = current_scope;

    while (scope) {
        Symbol *symbol = find_symbol_in_scope(scope, name);

        if (symbol) {
            return symbol;
        }

        scope = scope->parent;
    }

    return NULL;
}

Symbol *symbol_table_lookup_current_scope(const char *name) {
    return find_symbol_in_scope(current_scope, name);
}

void symbol_table_print(FILE *stream) {
    Scope *scope;
    int has_symbols = 0;

    fprintf(stream, "\nSymbol Table\n");
    fprintf(
        stream,
        "%-5s %-5s %-18s %-16s %-10s %-8s %-7s %-12s %-6s %s\n",
        "ID",
        "Depth",
        "Scope",
        "Name",
        "Kind",
        "Type",
        "Const",
        "Initialized",
        "Line",
        "Details"
    );
    fprintf(
        stream,
        "----- ----- ------------------ ---------------- --------- -------- ------- ------------ ------ --------------------\n"
    );

    for (scope = all_scopes_head; scope; scope = scope->next_all) {
        Symbol *symbol;
        char scope_name[64];

        if (scope->kind == SCOPE_FUNCTION && scope->label) {
            snprintf(scope_name, sizeof(scope_name), "function(%s)", scope->label);
        } else {
            snprintf(scope_name, sizeof(scope_name), "%s", scope_kind_name(scope->kind));
        }

        for (symbol = scope->symbols_head; symbol; symbol = symbol->next_in_scope) {
            has_symbols = 1;

            fprintf(
                stream,
                "%-5d %-5d %-18s %-16s %-10s %-8s %-7s ",
                symbol->scope_id,
                symbol->scope_depth,
                scope_name,
                symbol->name,
                symbol_kind_name(symbol->kind),
                type_kind_name(symbol->type),
                symbol->kind == SYMBOL_VARIABLE ? (symbol->is_const ? "yes" : "no") : "-"
            );

            if (symbol->kind == SYMBOL_FUNCTION) {
                fprintf(stream, "%-12s ", "-");
            } else {
                fprintf(stream, "%-12s ", symbol->is_initialized ? "yes" : "no");
            }

            fprintf(stream, "%-6d ", symbol->line_declared);
            print_symbol_details(stream, symbol);
            fputc('\n', stream);
        }
    }

    if (!has_symbols) {
        fprintf(stream, "(empty)\n");
    }
}

int symbol_table_error_count(void) {
    return semantic_errors;
}
