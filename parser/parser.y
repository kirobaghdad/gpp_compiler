%code requires {
#include "../semantic/symbol_table.h"
#include "../quadruples/quadruples.h"

typedef struct ExprInfo ExprInfo;
typedef struct ArgumentList ArgumentList;
typedef struct WhileContext WhileContext;
typedef struct DoWhileContext DoWhileContext;
typedef struct ForContext ForContext;
}

%{
#include "../semantic/symbol_table.h"
#include "../quadruples/quadruples.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Provided by Flex */
extern int yylex(void);
extern FILE *yyin;
extern int line_num;
extern int error_count;

void yyerror(const char *s);

int yyparse(void);

typedef struct {
    char *name;
    TypeKind return_type;
    ParameterInfo *parameters;
    size_t parameter_count;
    size_t parameter_capacity;
} PendingFunctionSignature;

typedef struct ExprInfo ExprInfo;
typedef struct ArgumentList ArgumentList;
typedef struct WhileContext WhileContext;
typedef struct DoWhileContext DoWhileContext;
typedef struct ForContext ForContext;

struct ExprInfo {
    char *place;
    TypeKind type;
    Symbol *symbol;
    int is_lvalue;
    int is_valid;
    int is_string_literal;
};

struct ArgumentList {
    ExprInfo **items;
    size_t count;
    size_t capacity;
};

struct WhileContext {
    char *start_label;
    char *end_label;
};

struct DoWhileContext {
    char *start_label;
    char *condition_label;
    char *end_label;
};

struct ForContext {
    char *condition_label;
    char *body_label;
    char *iteration_label;
    char *end_label;
};

typedef struct BreakContext {
    char *label;
    struct BreakContext *next;
} BreakContext;

typedef struct ContinueContext {
    char *label;
    struct ContinueContext *next;
} ContinueContext;

typedef struct SwitchCase {
    char *value;
    char *label;
    struct SwitchCase *next;
} SwitchCase;

typedef struct SwitchContext {
    char *expression_place;
    char *dispatch_label;
    char *break_label;
    char *default_label;
    SwitchCase *cases_head;
    SwitchCase *cases_tail;
    struct SwitchContext *next;
} SwitchContext;

static TypeKind current_declaration_type = TYPE_INVALID;
static int current_declaration_is_const = 0;
static Symbol *pending_function_definition = NULL;
static Symbol *current_function_symbol = NULL;
static PendingFunctionSignature pending_function_signature = {0};
static BreakContext *break_stack = NULL;
static ContinueContext *continue_stack = NULL;
static SwitchContext *switch_stack = NULL;
static char *current_function_name = NULL;

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

static char *format_integer(int value) {
    int needed = snprintf(NULL, 0, "%d", value);
    char *text = checked_malloc((size_t)needed + 1);

    snprintf(text, (size_t)needed + 1, "%d", value);
    return text;
}

static char *format_float_literal(float value) {
    int needed = snprintf(NULL, 0, "%.6g", (double)value);
    char *text = checked_malloc((size_t)needed + 1);

    snprintf(text, (size_t)needed + 1, "%.6g", (double)value);
    return text;
}

static ExprInfo *make_expr(
    char *place,
    TypeKind type,
    Symbol *symbol,
    int is_lvalue,
    int is_valid,
    int is_string_literal
) {
    ExprInfo *expr = checked_malloc(sizeof(*expr));

    expr->place = place ? place : duplicate_text("-");
    expr->type = type;
    expr->symbol = symbol;
    expr->is_lvalue = is_lvalue;
    expr->is_valid = is_valid;
    expr->is_string_literal = is_string_literal;
    return expr;
}

static ExprInfo *make_invalid_expr(void) {
    return make_expr(NULL, TYPE_INVALID, NULL, 0, 0, 0);
}

static void free_expr(ExprInfo *expr) {
    if (!expr) {
        return;
    }

    free(expr->place);
    free(expr);
}

static ArgumentList *make_argument_list(ExprInfo *expr) {
    ArgumentList *arguments = checked_malloc(sizeof(*arguments));

    arguments->count = 0;
    arguments->capacity = 4;
    arguments->items = checked_malloc(arguments->capacity * sizeof(*arguments->items));
    arguments->items[arguments->count++] = expr;
    return arguments;
}

static ArgumentList *append_argument(ArgumentList *arguments, ExprInfo *expr) {
    ExprInfo **grown;
    size_t new_capacity;

    if (!arguments) {
        return make_argument_list(expr);
    }

    if (arguments->count < arguments->capacity) {
        arguments->items[arguments->count++] = expr;
        return arguments;
    }

    new_capacity = arguments->capacity * 2;
    grown = realloc(arguments->items, new_capacity * sizeof(*grown));

    if (!grown) {
        perror("realloc");
        exit(EXIT_FAILURE);
    }

    arguments->items = grown;
    arguments->capacity = new_capacity;
    arguments->items[arguments->count++] = expr;
    return arguments;
}

static void free_argument_list(ArgumentList *arguments) {
    size_t index;

    if (!arguments) {
        return;
    }

    for (index = 0; index < arguments->count; ++index) {
        free_expr(arguments->items[index]);
    }

    free(arguments->items);
    free(arguments);
}

static int is_numeric_type(TypeKind type) {
    return
        type == TYPE_INT ||
        type == TYPE_FLOAT ||
        type == TYPE_DOUBLE ||
        type == TYPE_CHAR ||
        type == TYPE_BOOL;
}

static int is_integer_like_type(TypeKind type) {
    return type == TYPE_INT || type == TYPE_CHAR || type == TYPE_BOOL;
}

static int is_scalar_type(TypeKind type) {
    return is_numeric_type(type);
}

static TypeKind merge_numeric_types(TypeKind left, TypeKind right) {
    if (left == TYPE_DOUBLE || right == TYPE_DOUBLE) {
        return TYPE_DOUBLE;
    }

    if (left == TYPE_FLOAT || right == TYPE_FLOAT) {
        return TYPE_FLOAT;
    }

    if (left == TYPE_INT || right == TYPE_INT) {
        return TYPE_INT;
    }

    if (left == TYPE_CHAR || right == TYPE_CHAR) {
        return TYPE_CHAR;
    }

    if (left == TYPE_BOOL || right == TYPE_BOOL) {
        return TYPE_BOOL;
    }

    return TYPE_INVALID;
}

static int types_assignable(TypeKind target, TypeKind source) {
    if (target == TYPE_INVALID || source == TYPE_INVALID) {
        return 0;
    }

    if (target == TYPE_VOID || source == TYPE_VOID) {
        return 0;
    }

    if (target == source) {
        return 1;
    }

    return is_scalar_type(target) && is_scalar_type(source);
}

static const char *type_quad_name(TypeKind type) {
    switch (type) {
        case TYPE_INT:
            return "INT";
        case TYPE_FLOAT:
            return "FLOAT";
        case TYPE_DOUBLE:
            return "DOUBLE";
        case TYPE_CHAR:
            return "CHAR";
        case TYPE_BOOL:
            return "BOOL";
        case TYPE_VOID:
            return "VOID";
        case TYPE_INVALID:
        default:
            return "INVALID";
    }
}

static char *format_conversion_op(TypeKind from, TypeKind to) {
    int needed = snprintf(
        NULL,
        0,
        "CAST_%s_TO_%s",
        type_quad_name(from),
        type_quad_name(to)
    );
    char *op = checked_malloc((size_t)needed + 1);

    snprintf(
        op,
        (size_t)needed + 1,
        "CAST_%s_TO_%s",
        type_quad_name(from),
        type_quad_name(to)
    );
    return op;
}

static void convert_expr_to_type(ExprInfo *expr, TypeKind target_type) {
    char *op;
    char *converted_place;

    if (!expr || !expr->is_valid || expr->type == target_type) {
        return;
    }

    if (!types_assignable(target_type, expr->type)) {
        return;
    }

    op = format_conversion_op(expr->type, target_type);
    converted_place = quadruple_new_temp();
    quadruple_emit(op, expr->place, "-", converted_place);

    free(op);
    free(expr->place);
    expr->place = converted_place;
    expr->type = target_type;
    expr->symbol = NULL;
    expr->is_lvalue = 0;
}

static int expr_require_rvalue(ExprInfo *expr, const char *context) {
    SymbolKind kind;

    if (!expr || !expr->is_valid) {
        return 0;
    }

    if (expr->is_string_literal) {
        symbol_table_report_error(line_num, "string literal is not valid %s", context);
        expr->is_valid = 0;
        return 0;
    }

    if (!expr->symbol) {
        return 1;
    }

    kind = symbol_kind(expr->symbol);

    if (kind == SYMBOL_FUNCTION) {
        symbol_table_report_error(
            line_num,
            "function '%s' cannot be used as a value without a call",
            symbol_name(expr->symbol)
        );
        expr->is_valid = 0;
        return 0;
    }

    if ((kind == SYMBOL_VARIABLE || kind == SYMBOL_PARAMETER) && !symbol_is_initialized(expr->symbol)) {
        symbol_table_report_error(
            line_num,
            "variable '%s' used before being initialized",
            symbol_name(expr->symbol)
        );
    }

    symbol_mark_used(expr->symbol);
    return 1;
}

static void validate_condition(ExprInfo *expr, const char *context) {
    if (!expr_require_rvalue(expr, context)) {
        return;
    }

    if (!is_scalar_type(expr->type)) {
        symbol_table_report_error(
            line_num,
            "expression %s must have a scalar type, found '%s'",
            context,
            type_kind_name(expr->type)
        );
        expr->is_valid = 0;
        return;
    }

    convert_expr_to_type(expr, TYPE_BOOL);
}

static void validate_switch_expression(ExprInfo *expr) {
    if (!expr_require_rvalue(expr, "in switch expression")) {
        return;
    }

    if (!is_integer_like_type(expr->type)) {
        symbol_table_report_error(
            line_num,
            "switch expression must have an integer-like type, found '%s'",
            type_kind_name(expr->type)
        );
        expr->is_valid = 0;
    }
}

static ExprInfo *validate_arithmetic_expression(
    ExprInfo *left,
    ExprInfo *right,
    const char *context,
    const char *quad_op,
    int require_integer
) {
    TypeKind result_type = TYPE_INVALID;
    char *result_place = NULL;
    int valid = 1;

    if (!expr_require_rvalue(left, context)) {
        valid = 0;
    }

    if (!expr_require_rvalue(right, context)) {
        valid = 0;
    }

    if (valid && (!is_numeric_type(left->type) || !is_numeric_type(right->type))) {
        symbol_table_report_error(
            line_num,
            "%s requires numeric operands, found '%s' and '%s'",
            context,
            type_kind_name(left->type),
            type_kind_name(right->type)
        );
        valid = 0;
    }

    if (valid && require_integer && (!is_integer_like_type(left->type) || !is_integer_like_type(right->type))) {
        symbol_table_report_error(
            line_num,
            "%s requires integer-like operands, found '%s' and '%s'",
            context,
            type_kind_name(left->type),
            type_kind_name(right->type)
        );
        valid = 0;
    }

    if (valid) {
        result_type = merge_numeric_types(left->type, right->type);
        convert_expr_to_type(left, result_type);
        convert_expr_to_type(right, result_type);
        result_place = quadruple_new_temp();
        quadruple_emit(quad_op, left->place, right->place, result_place);
    }

    free_expr(left);
    free_expr(right);

    if (!valid) {
        return make_invalid_expr();
    }

    return make_expr(result_place, result_type, NULL, 0, 1, 0);
}

static ExprInfo *validate_logical_expression(
    ExprInfo *left,
    ExprInfo *right,
    const char *context,
    const char *quad_op
) {
    char *result_place = NULL;
    int valid = 1;

    if (!expr_require_rvalue(left, context)) {
        valid = 0;
    }

    if (!expr_require_rvalue(right, context)) {
        valid = 0;
    }

    if (valid && (!is_scalar_type(left->type) || !is_scalar_type(right->type))) {
        symbol_table_report_error(
            line_num,
            "%s requires scalar operands, found '%s' and '%s'",
            context,
            type_kind_name(left->type),
            type_kind_name(right->type)
        );
        valid = 0;
    }

    if (valid) {
        TypeKind operand_type = strcmp(quad_op, "AND") == 0 || strcmp(quad_op, "OR") == 0
            ? TYPE_BOOL
            : merge_numeric_types(left->type, right->type);

        convert_expr_to_type(left, operand_type);
        convert_expr_to_type(right, operand_type);
        result_place = quadruple_new_temp();
        quadruple_emit(quad_op, left->place, right->place, result_place);
    }

    free_expr(left);
    free_expr(right);

    if (!valid) {
        return make_invalid_expr();
    }

    return make_expr(result_place, TYPE_BOOL, NULL, 0, 1, 0);
}

static ExprInfo *validate_unary_passthrough(ExprInfo *expr, const char *context) {
    TypeKind result_type = TYPE_INVALID;
    char *result_place = NULL;
    int valid = 1;

    if (!expr_require_rvalue(expr, context)) {
        valid = 0;
    }

    if (valid && !is_numeric_type(expr->type)) {
        symbol_table_report_error(
            line_num,
            "%s requires a numeric operand, found '%s'",
            context,
            type_kind_name(expr->type)
        );
        valid = 0;
    }

    if (valid) {
        result_type = expr->type;
        result_place = duplicate_text(expr->place);
    }

    free_expr(expr);

    if (!valid) {
        return make_invalid_expr();
    }

    return make_expr(result_place, result_type, NULL, 0, 1, 0);
}

static ExprInfo *validate_unary_numeric_expression(
    ExprInfo *expr,
    const char *context,
    const char *quad_op
) {
    TypeKind result_type = TYPE_INVALID;
    char *result_place = NULL;
    int valid = 1;

    if (!expr_require_rvalue(expr, context)) {
        valid = 0;
    }

    if (valid && !is_numeric_type(expr->type)) {
        symbol_table_report_error(
            line_num,
            "%s requires a numeric operand, found '%s'",
            context,
            type_kind_name(expr->type)
        );
        valid = 0;
    }

    if (valid) {
        result_type = expr->type;
        result_place = quadruple_new_temp();
        quadruple_emit(quad_op, expr->place, "-", result_place);
    }

    free_expr(expr);

    if (!valid) {
        return make_invalid_expr();
    }

    return make_expr(result_place, result_type, NULL, 0, 1, 0);
}

static ExprInfo *validate_not_expression(ExprInfo *expr) {
    char *result_place = NULL;
    int valid = 1;

    if (!expr_require_rvalue(expr, "for logical negation")) {
        valid = 0;
    }

    if (valid && !is_scalar_type(expr->type)) {
        symbol_table_report_error(
            line_num,
            "logical negation requires a scalar operand, found '%s'",
            type_kind_name(expr->type)
        );
        valid = 0;
    }

    if (valid) {
        result_place = quadruple_new_temp();
        quadruple_emit("NOT", expr->place, "-", result_place);
    }

    free_expr(expr);

    if (!valid) {
        return make_invalid_expr();
    }

    return make_expr(result_place, TYPE_BOOL, NULL, 0, 1, 0);
}

static ExprInfo *validate_increment_expression(
    ExprInfo *expr,
    const char *context,
    int delta,
    int is_prefix
) {
    TypeKind result_type = TYPE_INVALID;
    char *result_place = NULL;
    char *updated_value = NULL;
    int valid = 1;

    if (!expr || !expr->is_valid) {
        free_expr(expr);
        return make_invalid_expr();
    }

    if (!expr->is_lvalue) {
        symbol_table_report_error(line_num, "left-hand side of %s must be a modifiable lvalue", context);
        valid = 0;
    }

    if (expr->symbol && symbol_is_const(expr->symbol)) {
        symbol_table_report_error(
            line_num,
            "const variable '%s' cannot be modified using %s",
            symbol_name(expr->symbol),
            context
        );
        valid = 0;
    }

    if (!expr_require_rvalue(expr, context)) {
        valid = 0;
    }

    if (valid && !is_numeric_type(expr->type)) {
        symbol_table_report_error(
            line_num,
            "%s requires a numeric operand, found '%s'",
            context,
            type_kind_name(expr->type)
        );
        valid = 0;
    }

    if (valid) {
        updated_value = quadruple_new_temp();

        if (!is_prefix) {
            result_place = quadruple_new_temp();
            quadruple_emit("ASSIGN", expr->place, "-", result_place);
        }

        quadruple_emit(delta > 0 ? "ADD" : "SUB", expr->place, "1", updated_value);
        quadruple_emit("ASSIGN", updated_value, "-", expr->place);

        if (is_prefix) {
            result_place = duplicate_text(expr->place);
        }

        symbol_mark_initialized(expr->symbol);
        result_type = expr->type;
        free(updated_value);
    }

    free_expr(expr);

    if (!valid) {
        return make_invalid_expr();
    }

    return make_expr(result_place, result_type, NULL, 0, 1, 0);
}

static const char *compound_assignment_operation(const char *assignment_op) {
    if (strcmp(assignment_op, "ADD_ASSIGN") == 0) {
        return "ADD";
    }

    if (strcmp(assignment_op, "SUB_ASSIGN") == 0) {
        return "SUB";
    }

    if (strcmp(assignment_op, "MUL_ASSIGN") == 0) {
        return "MUL";
    }

    if (strcmp(assignment_op, "DIV_ASSIGN") == 0) {
        return "DIV";
    }

    if (strcmp(assignment_op, "MOD_ASSIGN") == 0) {
        return "MOD";
    }

    return NULL;
}

static ExprInfo *validate_assignment_expression(
    ExprInfo *target,
    const char *assignment_op,
    ExprInfo *value
) {
    TypeKind result_type = TYPE_INVALID;
    char *result_place = NULL;
    const char *compound_op;
    int valid = 1;
    int is_compound = strcmp(assignment_op, "ASSIGN") != 0;

    if (!target || !target->is_valid) {
        valid = 0;
    }

    if (!value || !expr_require_rvalue(value, "on the right-hand side of assignment")) {
        valid = 0;
    }

    if (!target || !target->is_lvalue) {
        symbol_table_report_error(line_num, "left-hand side of assignment must be a modifiable lvalue");
        valid = 0;
    }

    if (target && target->symbol && symbol_is_const(target->symbol)) {
        symbol_table_report_error(
            line_num,
            "const variable '%s' cannot be reassigned",
            symbol_name(target->symbol)
        );
        valid = 0;
    }

    if (is_compound && target && !expr_require_rvalue(target, "in compound assignment")) {
        valid = 0;
    }

    if (valid && is_compound && (!is_numeric_type(target->type) || !is_numeric_type(value->type))) {
        symbol_table_report_error(
            line_num,
            "compound assignment requires numeric operands, found '%s' and '%s'",
            type_kind_name(target->type),
            type_kind_name(value->type)
        );
        valid = 0;
    }

    if (
        valid &&
        is_compound &&
        strcmp(assignment_op, "MOD_ASSIGN") == 0 &&
        (!is_integer_like_type(target->type) || !is_integer_like_type(value->type))
    ) {
        symbol_table_report_error(
            line_num,
            "modulo assignment requires integer-like operands, found '%s' and '%s'",
            type_kind_name(target->type),
            type_kind_name(value->type)
        );
        valid = 0;
    }

    if (valid && !is_compound && !types_assignable(target->type, value->type)) {
        symbol_table_report_error(
            line_num,
            "cannot assign value of type '%s' to '%s'",
            type_kind_name(value->type),
            type_kind_name(target->type)
        );
        valid = 0;
    }

    if (valid) {
        compound_op = compound_assignment_operation(assignment_op);
        result_place = duplicate_text(target->place);
        result_type = target->type;

        if (!is_compound) {
            convert_expr_to_type(value, target->type);
            quadruple_emit("ASSIGN", value->place, "-", target->place);
        } else if (compound_op) {
            char *temp = quadruple_new_temp();

            convert_expr_to_type(value, target->type);
            quadruple_emit(compound_op, target->place, value->place, temp);
            quadruple_emit("ASSIGN", temp, "-", target->place);
            free(temp);
        }

        if (target->symbol) {
            symbol_mark_initialized(target->symbol);
        }
    }

    free_expr(target);
    free_expr(value);

    if (!valid) {
        return make_invalid_expr();
    }

    return make_expr(result_place, result_type, NULL, 0, 1, 0);
}

static ExprInfo *validate_function_call(ExprInfo *callee, ArgumentList *arguments) {
    Symbol *function_symbol = NULL;
    TypeKind return_type = TYPE_INVALID;
    size_t index;
    int valid = 1;

    if (!callee || !callee->is_valid) {
        valid = 0;
    } else if (!callee->symbol || symbol_kind(callee->symbol) != SYMBOL_FUNCTION) {
        symbol_table_report_error(line_num, "called expression is not a function");
        valid = 0;
    } else {
        function_symbol = callee->symbol;
        return_type = symbol_type(function_symbol);
        symbol_mark_used(function_symbol);
    }

    if (arguments) {
        for (index = 0; index < arguments->count; ++index) {
            if (!expr_require_rvalue(arguments->items[index], "as a function argument")) {
                valid = 0;
            }
        }
    }

    if (function_symbol) {
        size_t argument_count = arguments ? arguments->count : 0;
        size_t total_parameters = symbol_parameter_count(function_symbol);
        size_t required_parameters = symbol_required_parameter_count(function_symbol);

        if (argument_count < required_parameters || argument_count > total_parameters) {
            symbol_table_report_error(
                line_num,
                "function '%s' expects between %lu and %lu arguments, but %lu were provided",
                symbol_name(function_symbol),
                (unsigned long)required_parameters,
                (unsigned long)total_parameters,
                (unsigned long)argument_count
            );
            valid = 0;
        }

        if (arguments) {
            for (index = 0; index < arguments->count; ++index) {
                if (
                    index < total_parameters &&
                    arguments->items[index]->is_valid &&
                    !types_assignable(symbol_parameter_type(function_symbol, index), arguments->items[index]->type)
                ) {
                    symbol_table_report_error(
                        line_num,
                        "argument %lu of function '%s' has type '%s', expected '%s'",
                        (unsigned long)(index + 1),
                        symbol_name(function_symbol),
                        type_kind_name(arguments->items[index]->type),
                        type_kind_name(symbol_parameter_type(function_symbol, index))
                    );
                    valid = 0;
                }
            }
        }
    }

    if (valid && function_symbol) {
        size_t provided_count = arguments ? arguments->count : 0;
        size_t total_parameters = symbol_parameter_count(function_symbol);
        char *argument_count = format_integer((int)total_parameters);

        if (arguments) {
            for (index = 0; index < arguments->count; ++index) {
                convert_expr_to_type(
                    arguments->items[index],
                    symbol_parameter_type(function_symbol, index)
                );
                quadruple_emit("PARAM", arguments->items[index]->place, "-", "-");
            }
        }

        for (index = provided_count; index < total_parameters; ++index) {
            quadruple_emit(
                "PARAM",
                symbol_parameter_default_value(function_symbol, index),
                "-",
                "-"
            );
        }

        if (return_type == TYPE_VOID) {
            quadruple_emit("CALL", callee->place, argument_count, "-");
            free(argument_count);
            free_expr(callee);
            free_argument_list(arguments);
            return make_expr(NULL, TYPE_VOID, NULL, 0, 1, 0);
        }

        {
            char *result_place = quadruple_new_temp();

            quadruple_emit("CALL", callee->place, argument_count, result_place);
            free(argument_count);
            free_expr(callee);
            free_argument_list(arguments);
            return make_expr(result_place, return_type, NULL, 0, 1, 0);
        }
    }

    free_expr(callee);
    free_argument_list(arguments);
    return make_invalid_expr();
}

static ExprInfo *validate_index_expression(ExprInfo *base, ExprInfo *index) {
    Symbol *base_symbol = NULL;
    TypeKind result_type = TYPE_INVALID;
    char *result_place = NULL;
    int valid = 1;

    if (!expr_require_rvalue(base, "as a subscripted expression")) {
        valid = 0;
    }

    if (!expr_require_rvalue(index, "as an array index")) {
        valid = 0;
    }

    if (valid && !is_integer_like_type(index->type)) {
        symbol_table_report_error(
            line_num,
            "array index must be integer-like, found '%s'",
            type_kind_name(index->type)
        );
        valid = 0;
    }

    if (valid) {
        int needed = snprintf(NULL, 0, "%s[%s]", base->place, index->place);

        result_place = checked_malloc((size_t)needed + 1);
        snprintf(result_place, (size_t)needed + 1, "%s[%s]", base->place, index->place);
        result_type = base->type;
        base_symbol = base->symbol;
    }

    free_expr(base);
    free_expr(index);

    if (!valid) {
        return make_invalid_expr();
    }

    return make_expr(result_place, result_type, base_symbol, 1, 1, 0);
}

static void discard_pending_parameters(void) {
    size_t index;

    for (index = 0; index < pending_function_signature.parameter_count; ++index) {
        free(pending_function_signature.parameters[index].name);
        free(pending_function_signature.parameters[index].default_value);
    }

    free(pending_function_signature.parameters);
    pending_function_signature.parameters = NULL;
    pending_function_signature.parameter_count = 0;
    pending_function_signature.parameter_capacity = 0;
}

static void reset_pending_function_signature(void) {
    discard_pending_parameters();
    free(pending_function_signature.name);
    pending_function_signature.name = NULL;
    pending_function_signature.return_type = TYPE_INVALID;
}

static void begin_function_signature(TypeKind return_type, const char *name) {
    reset_pending_function_signature();
    pending_function_signature.return_type = return_type;
    pending_function_signature.name = duplicate_text(name);
}

static void add_pending_parameter(
    TypeKind type,
    const char *name,
    int has_default_value,
    const char *default_value
) {
    ParameterInfo *parameters;
    size_t new_capacity;

    if (pending_function_signature.parameter_count == pending_function_signature.parameter_capacity) {
        new_capacity = pending_function_signature.parameter_capacity == 0
            ? 4
            : pending_function_signature.parameter_capacity * 2;

        parameters = realloc(
            pending_function_signature.parameters,
            new_capacity * sizeof(*parameters)
        );

        if (!parameters) {
            perror("realloc");
            exit(EXIT_FAILURE);
        }

        pending_function_signature.parameters = parameters;
        pending_function_signature.parameter_capacity = new_capacity;
    }

    pending_function_signature.parameters[pending_function_signature.parameter_count].name =
        duplicate_text(name);
    pending_function_signature.parameters[pending_function_signature.parameter_count].type = type;
    pending_function_signature.parameters[pending_function_signature.parameter_count].has_default_value =
        has_default_value;
    pending_function_signature.parameters[pending_function_signature.parameter_count].default_value =
        duplicate_text(default_value);
    ++pending_function_signature.parameter_count;
}

static Symbol *finalize_function_header(void) {
    Symbol *function_symbol = symbol_table_declare_function(
        pending_function_signature.name,
        pending_function_signature.return_type,
        pending_function_signature.parameters,
        pending_function_signature.parameter_count,
        0,
        line_num
    );

    reset_pending_function_signature();
    return function_symbol;
}

static void finish_declaration(void) {
    current_declaration_type = TYPE_INVALID;
    current_declaration_is_const = 0;
}

static Symbol *declare_current_variable(const char *name, int is_initialized) {
    return symbol_table_declare_variable(
        name,
        current_declaration_type,
        current_declaration_is_const,
        is_initialized,
        line_num
    );
}

static void begin_function_definition(Symbol *function_symbol) {
    const char *function_name;

    pending_function_definition = function_symbol;
    current_function_symbol = function_symbol;
    symbol_table_mark_function_defined(function_symbol, line_num);

    free(current_function_name);
    function_name = symbol_name(function_symbol);
    current_function_name = duplicate_text(function_name ? function_name : "anonymous");
    quadruple_emit("FUNC_BEGIN", current_function_name, "-", "-");
}

static void finish_function_definition(void) {
    current_function_symbol = NULL;

    if (current_function_name) {
        quadruple_emit("FUNC_END", current_function_name, "-", "-");
        free(current_function_name);
        current_function_name = NULL;
    }
}

static void enter_compound_scope(void) {
    if (pending_function_definition) {
        symbol_table_enter_function_scope(pending_function_definition);
        pending_function_definition = NULL;
        return;
    }

    symbol_table_enter_block_scope();
}

static void push_break_label(char *label) {
    BreakContext *context = checked_malloc(sizeof(*context));

    context->label = label;
    context->next = break_stack;
    break_stack = context;
}

static void pop_break_label(void) {
    BreakContext *context;

    if (!break_stack) {
        return;
    }

    context = break_stack;
    break_stack = break_stack->next;
    free(context);
}

static const char *current_break_label(void) {
    return break_stack ? break_stack->label : NULL;
}

static void push_continue_label(char *label) {
    ContinueContext *context = checked_malloc(sizeof(*context));

    context->label = label;
    context->next = continue_stack;
    continue_stack = context;
}

static void pop_continue_label(void) {
    ContinueContext *context;

    if (!continue_stack) {
        return;
    }

    context = continue_stack;
    continue_stack = continue_stack->next;
    free(context);
}

static const char *current_continue_label(void) {
    return continue_stack ? continue_stack->label : NULL;
}

static WhileContext *begin_while_loop(void) {
    WhileContext *context = checked_malloc(sizeof(*context));

    context->start_label = quadruple_new_label();
    context->end_label = quadruple_new_label();

    quadruple_emit_label(context->start_label);
    push_break_label(context->end_label);
    push_continue_label(context->start_label);
    return context;
}

static void while_emit_condition(WhileContext *context, ExprInfo *condition) {
    if (context && condition && condition->is_valid) {
        quadruple_emit("JMP_FALSE", condition->place, "-", context->end_label);
    }

    free_expr(condition);
}

static void finish_while_loop(WhileContext *context) {
    if (!context) {
        return;
    }

    quadruple_emit("JMP", "-", "-", context->start_label);
    quadruple_emit_label(context->end_label);
    pop_continue_label();
    pop_break_label();

    free(context->start_label);
    free(context->end_label);
    free(context);
}

static DoWhileContext *begin_do_while_loop(void) {
    DoWhileContext *context = checked_malloc(sizeof(*context));

    context->start_label = quadruple_new_label();
    context->condition_label = quadruple_new_label();
    context->end_label = quadruple_new_label();

    quadruple_emit_label(context->start_label);
    push_break_label(context->end_label);
    push_continue_label(context->condition_label);
    return context;
}

static void begin_do_while_condition(DoWhileContext *context) {
    if (context) {
        quadruple_emit_label(context->condition_label);
    }
}

static void finish_do_while_loop(DoWhileContext *context, ExprInfo *condition) {
    if (!context) {
        free_expr(condition);
        return;
    }

    if (condition && condition->is_valid) {
        quadruple_emit("JMP_TRUE", condition->place, "-", context->start_label);
    }

    quadruple_emit_label(context->end_label);
    pop_continue_label();
    pop_break_label();

    free_expr(condition);
    free(context->start_label);
    free(context->condition_label);
    free(context->end_label);
    free(context);
}

static ForContext *begin_for_loop(void) {
    ForContext *context = checked_malloc(sizeof(*context));

    context->condition_label = quadruple_new_label();
    context->body_label = quadruple_new_label();
    context->iteration_label = quadruple_new_label();
    context->end_label = quadruple_new_label();

    push_break_label(context->end_label);
    push_continue_label(context->iteration_label);
    return context;
}

static void for_after_init(ForContext *context) {
    if (!context) {
        return;
    }

    quadruple_emit("JMP", "-", "-", context->condition_label);
    quadruple_emit_label(context->condition_label);
}

static void for_after_condition(ForContext *context, ExprInfo *condition) {
    if (!context) {
        free_expr(condition);
        return;
    }

    if (condition && condition->is_valid) {
        quadruple_emit("JMP_FALSE", condition->place, "-", context->end_label);
    }

    quadruple_emit("JMP", "-", "-", context->body_label);
    quadruple_emit_label(context->iteration_label);
    free_expr(condition);
}

static void for_after_iteration(ForContext *context, ExprInfo *iteration) {
    if (!context) {
        free_expr(iteration);
        return;
    }

    free_expr(iteration);
    quadruple_emit("JMP", "-", "-", context->condition_label);
    quadruple_emit_label(context->body_label);
}

static void finish_for_loop(ForContext *context) {
    if (!context) {
        return;
    }

    quadruple_emit("JMP", "-", "-", context->iteration_label);
    quadruple_emit_label(context->end_label);
    pop_continue_label();
    pop_break_label();

    free(context->condition_label);
    free(context->body_label);
    free(context->iteration_label);
    free(context->end_label);
    free(context);
}

static void free_switch_cases(SwitchCase *cases) {
    while (cases) {
        SwitchCase *next_case = cases->next;

        free(cases->value);
        free(cases->label);
        free(cases);
        cases = next_case;
    }
}

static void begin_switch_context(ExprInfo *expression) {
    SwitchContext *context = checked_malloc(sizeof(*context));

    context->expression_place = duplicate_text(
        expression && expression->is_valid ? expression->place : "-"
    );
    context->dispatch_label = quadruple_new_label();
    context->break_label = quadruple_new_label();
    context->default_label = NULL;
    context->cases_head = NULL;
    context->cases_tail = NULL;
    context->next = switch_stack;
    switch_stack = context;

    push_break_label(context->break_label);
    quadruple_emit("JMP", "-", "-", context->dispatch_label);
}

static SwitchContext *current_switch_context(void) {
    return switch_stack;
}

static int last_quadruple_is_jump_to(const char *label) {
    const Quadruple *quadruple;

    if (!label || quadruple_count() == 0) {
        return 0;
    }

    quadruple = quadruple_at(quadruple_count() - 1);
    return
        quadruple &&
        strcmp(quadruple->op, "JMP") == 0 &&
        strcmp(quadruple->result, label) == 0;
}

static void emit_switch_case_label(ExprInfo *value) {
    SwitchCase *switch_case;
    SwitchContext *context = current_switch_context();

    if (!context || !value || !value->is_valid) {
        free_expr(value);
        return;
    }

    switch_case = checked_malloc(sizeof(*switch_case));
    switch_case->value = duplicate_text(value->place);
    switch_case->label = quadruple_new_label();
    switch_case->next = NULL;

    if (!context->cases_head) {
        context->cases_head = switch_case;
    } else {
        context->cases_tail->next = switch_case;
    }

    context->cases_tail = switch_case;
    quadruple_emit_label(switch_case->label);
    free_expr(value);
}

static void emit_switch_default_label(void) {
    SwitchContext *context = current_switch_context();

    if (!context) {
        return;
    }

    if (!context->default_label) {
        context->default_label = quadruple_new_label();
    }

    quadruple_emit_label(context->default_label);
}

static void finish_switch_context(void) {
    SwitchCase *switch_case;
    SwitchContext *context = switch_stack;

    if (!context) {
        return;
    }

    switch_stack = context->next;

    if (!last_quadruple_is_jump_to(context->break_label)) {
        quadruple_emit("JMP", "-", "-", context->break_label);
    }

    quadruple_emit_label(context->dispatch_label);

    for (switch_case = context->cases_head; switch_case; switch_case = switch_case->next) {
        char *temp = quadruple_new_temp();

        quadruple_emit("EQ", context->expression_place, switch_case->value, temp);
        quadruple_emit("JMP_TRUE", temp, "-", switch_case->label);
        free(temp);
    }

    quadruple_emit(
        "JMP",
        "-",
        "-",
        context->default_label ? context->default_label : context->break_label
    );
    quadruple_emit_label(context->break_label);
    pop_break_label();

    free(context->expression_place);
    free(context->dispatch_label);
    free(context->break_label);
    free(context->default_label);
    free_switch_cases(context->cases_head);
    free(context);
}

static void cleanup_parser_state(void) {
    while (break_stack) {
        pop_break_label();
    }

    while (continue_stack) {
        pop_continue_label();
    }

    while (switch_stack) {
        SwitchContext *next_context = switch_stack->next;

        free(switch_stack->expression_place);
        free(switch_stack->dispatch_label);
        free(switch_stack->break_label);
        free(switch_stack->default_label);
        free_switch_cases(switch_stack->cases_head);
        free(switch_stack);
        switch_stack = next_context;
    }

    free(current_function_name);
    current_function_name = NULL;
    current_function_symbol = NULL;
    pending_function_definition = NULL;
    current_declaration_type = TYPE_INVALID;
    current_declaration_is_const = 0;
}
%}

%define parse.error verbose
%output "parser/yacc_tab.c"
%defines "parser/yacc_tab.h"

%union {
    int ival;
    float fval;
    char* str;
    TypeKind type;
    Symbol* symbol;
    ExprInfo* expr;
    ArgumentList* args;
    WhileContext* while_ctx;
    DoWhileContext* do_while_ctx;
    ForContext* for_ctx;
}

%token INT_TYPE
%token FLOAT_TYPE
%token DOUBLE_TYPE
%token CHAR_TYPE
%token BOOL_TYPE
%token VOID_TYPE
%token CONST_KW
%token IF
%token ELSE
%token WHILE
%token DO
%token FOR
%token SWITCH
%token CASE
%token DEFAULT
%token BREAK
%token CONTINUE
%token RETURN
%token TRUE_KW
%token FALSE_KW
%token <fval> FLOAT_LITERAL
%token <ival> INTEGER_LITERAL
%token <str> CHAR_LITERAL
%token <str> STRING_LITERAL
%token PLUS
%token MINUS
%token MULT
%token DIV
%token MOD
%token INC
%token DEC
%token EQ_OP
%token NE_OP
%token LT_OP
%token GT_OP
%token LE_OP
%token GE_OP
%token AND_OP
%token OR_OP
%token NOT_OP
%token ASSIGN
%token ADD_ASSIGN
%token SUB_ASSIGN
%token MUL_ASSIGN
%token DIV_ASSIGN
%token MOD_ASSIGN
%token LPAREN
%token RPAREN
%token LBRACE
%token RBRACE
%token LBRACKET
%token RBRACKET
%token SEMI
%token COMMA
%token COLON
%token <str> IDENTIFIER

%type <type> type_specifier
%type <symbol> function_header
%type <expr> expression expression_opt constant_expression
%type <expr> assignment_expression logical_or_expression logical_and_expression
%type <expr> equality_expression relational_expression additive_expression
%type <expr> multiplicative_expression unary_expression postfix_expression
%type <expr> primary_expression literal for_cond for_iter
%type <args> argument_expression_list argument_expression_list_opt
%type <str> assignment_operator
%type <str> if_guard
%type <while_ctx> while_start
%type <do_while_ctx> do_start
%type <for_ctx> for_start

%right ASSIGN ADD_ASSIGN SUB_ASSIGN MUL_ASSIGN DIV_ASSIGN MOD_ASSIGN
%left OR_OP
%left AND_OP
%left EQ_OP NE_OP
%left LT_OP GT_OP LE_OP GE_OP
%left PLUS MINUS
%left MULT DIV MOD
%right NOT_OP
%right UMINUS

%nonassoc LOWER_THAN_ELSE
%nonassoc ELSE

%start translation_unit

%%

translation_unit
    : /* empty */
    | translation_unit external_declaration
    ;

external_declaration
    : function_definition
    | function_declaration SEMI
    | declaration SEMI
    | error SEMI
        {
            finish_declaration();
            reset_pending_function_signature();
            yyerrok;
        }
    ;

function_header
    : type_specifier IDENTIFIER LPAREN
        {
            begin_function_signature($1, $2);
            free($2);
        }
      parameter_list_opt RPAREN
        {
            $$ = finalize_function_header();
        }
    ;

function_definition
    : function_header
        {
            begin_function_definition($1);
        }
      compound_statement
        {
            finish_function_definition();
        }
    ;

function_declaration
    : function_header
    ;

parameter_list_opt
    : /* empty */
    | parameter_list
    | error
        {
            discard_pending_parameters();
            yyerrok;
        }
    ;

parameter_list
    : parameter_declaration
    | parameter_list COMMA parameter_declaration
    ;

parameter_declaration
    : type_specifier IDENTIFIER
        {
            add_pending_parameter($1, $2, 0, NULL);
            free($2);
        }
    | type_specifier IDENTIFIER ASSIGN expression
        {
            if ($4 && expr_require_rvalue($4, "as a default parameter value") &&
                !types_assignable($1, $4->type)) {
                symbol_table_report_error(
                    line_num,
                    "default value for parameter '%s' has type '%s', expected '%s'",
                    $2,
                    type_kind_name($4->type),
                    type_kind_name($1)
                );
            }

            if ($4 && $4->is_valid) {
                convert_expr_to_type($4, $1);
            }

            add_pending_parameter($1, $2, 1, $4 && $4->is_valid ? $4->place : "-");
            free($2);
            free_expr($4);
        }
    ;

type_specifier
    : INT_TYPE
        {
            $$ = TYPE_INT;
            current_declaration_type = $$;
        }
    | FLOAT_TYPE
        {
            $$ = TYPE_FLOAT;
            current_declaration_type = $$;
        }
    | DOUBLE_TYPE
        {
            $$ = TYPE_DOUBLE;
            current_declaration_type = $$;
        }
    | CHAR_TYPE
        {
            $$ = TYPE_CHAR;
            current_declaration_type = $$;
        }
    | BOOL_TYPE
        {
            $$ = TYPE_BOOL;
            current_declaration_type = $$;
        }
    | VOID_TYPE
        {
            $$ = TYPE_VOID;
            current_declaration_type = $$;
        }
    ;

declaration
    : type_specifier init_declarator_list
        {
            finish_declaration();
        }
    | CONST_KW
        {
            current_declaration_is_const = 1;
        }
      type_specifier init_declarator_list
        {
            finish_declaration();
        }
    | type_specifier error
        {
            finish_declaration();
            yyerrok;
        }
    ;

init_declarator_list
    : init_declarator
    | init_declarator_list COMMA init_declarator
    ;

init_declarator
    : IDENTIFIER
        {
            declare_current_variable($1, 0);
            free($1);
        }
    | IDENTIFIER ASSIGN expression
        {
            Symbol *symbol = declare_current_variable($1, 1);

            if ($3 && expr_require_rvalue($3, "in variable initialization") &&
                !types_assignable(current_declaration_type, $3->type)) {
                symbol_table_report_error(
                    line_num,
                    "cannot initialize '%s' of type '%s' with value of type '%s'",
                    $1,
                    type_kind_name(current_declaration_type),
                    type_kind_name($3->type)
                );
            }

            if ($3 && $3->is_valid) {
                convert_expr_to_type($3, current_declaration_type);
                quadruple_emit("ASSIGN", $3->place, "-", $1);
            } else if (symbol && symbol_is_const(symbol)) {
                symbol_mark_initialized(symbol);
            }

            free_expr($3);
            free($1);
        }
    | IDENTIFIER ASSIGN error
        {
            declare_current_variable($1, 0);
            free($1);
            yyerrok;
        }
    ;

compound_statement
    : scoped_lbrace block_item_list_opt RBRACE
        {
            symbol_table_leave_scope();
        }
    | scoped_lbrace error RBRACE
        {
            symbol_table_leave_scope();
            yyerrok;
        }
    ;

scoped_lbrace
    : LBRACE
        {
            enter_compound_scope();
        }
    ;

block_item_list_opt
    : /* empty */
    | block_item_list
    ;

block_item_list
    : block_item
    | block_item_list block_item
    ;

block_item
    : declaration SEMI
    | statement
    ;

statement
    : expression_statement
    | compound_statement
    | selection_statement
    | iteration_statement
    | jump_statement
    | error SEMI
        {
            yyerrok;
        }
    ;

expression_statement
    : expression_opt SEMI
        {
            free_expr($1);
        }
    ;

expression_opt
    : /* empty */
        {
            $$ = NULL;
        }
    | expression
        {
            $$ = $1;
        }
    ;

selection_statement
    : if_guard statement %prec LOWER_THAN_ELSE
        {
            quadruple_emit_label($1);
            free($1);
        }
    | if_guard statement ELSE
        {
            char *end_label = quadruple_new_label();

            quadruple_emit("JMP", "-", "-", end_label);
            quadruple_emit_label($1);
            free($1);
            $<str>$ = end_label;
        }
      statement
        {
            quadruple_emit_label($<str>4);
            free($<str>4);
        }
    | switch_statement
    ;

if_guard
    : IF LPAREN expression RPAREN
        {
            char *false_label = quadruple_new_label();

            if ($3) {
                validate_condition($3, "in if condition");
            }

            if ($3 && $3->is_valid) {
                quadruple_emit("JMP_FALSE", $3->place, "-", false_label);
            }

            free_expr($3);
            $$ = false_label;
        }
    | IF LPAREN error RPAREN
        {
            $$ = quadruple_new_label();
            yyerrok;
        }
    ;

switch_statement
    : SWITCH LPAREN expression RPAREN
        {
            if ($3) {
                validate_switch_expression($3);
            }

            begin_switch_context($3);
            free_expr($3);
        }
      scoped_lbrace switch_clause_list_opt RBRACE
        {
            finish_switch_context();
            symbol_table_leave_scope();
        }
    | SWITCH LPAREN error RPAREN
        {
            begin_switch_context(NULL);
            yyerrok;
        }
      scoped_lbrace switch_clause_list_opt RBRACE
        {
            finish_switch_context();
            symbol_table_leave_scope();
        }
    ;

switch_clause_list_opt
    : /* empty */
    | switch_clause_list
    ;

switch_clause_list
    : switch_clause
    | switch_clause_list switch_clause
    ;

switch_clause
    : case_label block_item_list_opt
    ;

case_label
    : CASE constant_expression COLON
        {
            if ($2) {
                if (!expr_require_rvalue($2, "in case label")) {
                    $2->is_valid = 0;
                }

                if ($2->is_valid && !is_integer_like_type($2->type)) {
                    symbol_table_report_error(
                        line_num,
                        "case label must have an integer-like type, found '%s'",
                        type_kind_name($2->type)
                    );
                    $2->is_valid = 0;
                }
            }

            emit_switch_case_label($2);
        }
    | CASE error COLON
        {
            yyerrok;
        }
    | DEFAULT COLON
        {
            emit_switch_default_label();
        }
    ;

constant_expression
    : expression
        {
            $$ = $1;
        }
    ;

iteration_statement
    : WHILE LPAREN while_start expression RPAREN
        {
            if ($4) {
                validate_condition($4, "in while condition");
            }

            while_emit_condition($3, $4);
        }
      statement
        {
            finish_while_loop($3);
        }
    | WHILE LPAREN while_start error RPAREN
        {
            while_emit_condition($3, NULL);
            yyerrok;
        }
      statement
        {
            finish_while_loop($3);
        }
    | do_start statement WHILE LPAREN
        {
            begin_do_while_condition($1);
        }
      expression RPAREN SEMI
        {
            if ($6) {
                validate_condition($6, "in do-while condition");
            }

            finish_do_while_loop($1, $6);
        }
    | do_start statement WHILE LPAREN
        {
            begin_do_while_condition($1);
        }
      error RPAREN SEMI
        {
            finish_do_while_loop($1, NULL);
            yyerrok;
        }
    | FOR LPAREN for_start for_init
        {
            for_after_init($3);
        }
      for_cond
        {
            if ($6) {
                validate_condition($6, "in for condition");
            }

            for_after_condition($3, $6);
        }
      for_iter RPAREN
        {
            for_after_iteration($3, $8);
        }
      statement
        {
            finish_for_loop($3);
            symbol_table_leave_scope();
        }
    ;

while_start
    : /* empty */
        {
            $$ = begin_while_loop();
        }
    ;

do_start
    : DO
        {
            $$ = begin_do_while_loop();
        }
    ;

for_start
    : /* empty */
        {
            symbol_table_enter_block_scope();
            $$ = begin_for_loop();
        }
    ;

for_init
    : declaration SEMI
    | expression_opt SEMI
        {
            free_expr($1);
        }
    | error SEMI
        {
            yyerrok;
        }
    ;

for_cond
    : expression_opt SEMI
        {
            $$ = $1;
        }
    | error SEMI
        {
            $$ = NULL;
            yyerrok;
        }
    ;

for_iter
    : expression_opt
        {
            $$ = $1;
        }
    | error
        {
            $$ = NULL;
            yyerrok;
        }
    ;

jump_statement
    : BREAK SEMI
        {
            const char *label = current_break_label();

            if (!label) {
                symbol_table_report_error(line_num, "'break' used outside of loop or switch");
            } else {
                quadruple_emit("JMP", "-", "-", label);
            }
        }
    | CONTINUE SEMI
        {
            const char *label = current_continue_label();

            if (!label) {
                symbol_table_report_error(line_num, "'continue' used outside of loop");
            } else {
                quadruple_emit("JMP", "-", "-", label);
            }
        }
    | RETURN expression_opt SEMI
        {
            TypeKind return_type = current_function_symbol ? symbol_type(current_function_symbol) : TYPE_INVALID;

            if (!current_function_symbol) {
                symbol_table_report_error(line_num, "'return' used outside of a function");
            } else if (return_type == TYPE_VOID) {
                if ($2) {
                    symbol_table_report_error(
                        line_num,
                        "void function '%s' must not return a value",
                        symbol_name(current_function_symbol)
                    );
                }
            } else {
                if (!$2) {
                    symbol_table_report_error(
                        line_num,
                        "non-void function '%s' must return a value of type '%s'",
                        symbol_name(current_function_symbol),
                        type_kind_name(return_type)
                    );
                } else if (expr_require_rvalue($2, "in return statement") &&
                           !types_assignable(return_type, $2->type)) {
                    symbol_table_report_error(
                        line_num,
                        "function '%s' returns '%s' but value has type '%s'",
                        symbol_name(current_function_symbol),
                        type_kind_name(return_type),
                        type_kind_name($2->type)
                    );
                }

                if ($2 && $2->is_valid) {
                    convert_expr_to_type($2, return_type);
                }
            }

            if (current_function_name) {
                quadruple_emit(
                    "RETURN",
                    ($2 && $2->is_valid) ? $2->place : "-",
                    "-",
                    current_function_name
                );
            }

            free_expr($2);
        }
    ;

expression
    : assignment_expression
        {
            $$ = $1;
        }
    ;

assignment_expression
    : logical_or_expression
        {
            $$ = $1;
        }
    | unary_expression assignment_operator assignment_expression
        {
            $$ = validate_assignment_expression($1, $2, $3);
            free($2);
        }
    ;

assignment_operator
    : ASSIGN
        {
            $$ = duplicate_text("ASSIGN");
        }
    | ADD_ASSIGN
        {
            $$ = duplicate_text("ADD_ASSIGN");
        }
    | SUB_ASSIGN
        {
            $$ = duplicate_text("SUB_ASSIGN");
        }
    | MUL_ASSIGN
        {
            $$ = duplicate_text("MUL_ASSIGN");
        }
    | DIV_ASSIGN
        {
            $$ = duplicate_text("DIV_ASSIGN");
        }
    | MOD_ASSIGN
        {
            $$ = duplicate_text("MOD_ASSIGN");
        }
    ;

logical_or_expression
    : logical_and_expression
        {
            $$ = $1;
        }
    | logical_or_expression OR_OP logical_and_expression
        {
            $$ = validate_logical_expression($1, $3, "logical OR", "OR");
        }
    ;

logical_and_expression
    : equality_expression
        {
            $$ = $1;
        }
    | logical_and_expression AND_OP equality_expression
        {
            $$ = validate_logical_expression($1, $3, "logical AND", "AND");
        }
    ;

equality_expression
    : relational_expression
        {
            $$ = $1;
        }
    | equality_expression EQ_OP relational_expression
        {
            $$ = validate_logical_expression($1, $3, "equality comparison", "EQ");
        }
    | equality_expression NE_OP relational_expression
        {
            $$ = validate_logical_expression($1, $3, "inequality comparison", "NE");
        }
    ;

relational_expression
    : additive_expression
        {
            $$ = $1;
        }
    | relational_expression LT_OP additive_expression
        {
            $$ = validate_logical_expression($1, $3, "relational comparison", "LT");
        }
    | relational_expression GT_OP additive_expression
        {
            $$ = validate_logical_expression($1, $3, "relational comparison", "GT");
        }
    | relational_expression LE_OP additive_expression
        {
            $$ = validate_logical_expression($1, $3, "relational comparison", "LE");
        }
    | relational_expression GE_OP additive_expression
        {
            $$ = validate_logical_expression($1, $3, "relational comparison", "GE");
        }
    ;

additive_expression
    : multiplicative_expression
        {
            $$ = $1;
        }
    | additive_expression PLUS multiplicative_expression
        {
            $$ = validate_arithmetic_expression($1, $3, "addition", "ADD", 0);
        }
    | additive_expression MINUS multiplicative_expression
        {
            $$ = validate_arithmetic_expression($1, $3, "subtraction", "SUB", 0);
        }
    ;

multiplicative_expression
    : unary_expression
        {
            $$ = $1;
        }
    | multiplicative_expression MULT unary_expression
        {
            $$ = validate_arithmetic_expression($1, $3, "multiplication", "MUL", 0);
        }
    | multiplicative_expression DIV unary_expression
        {
            $$ = validate_arithmetic_expression($1, $3, "division", "DIV", 0);
        }
    | multiplicative_expression MOD unary_expression
        {
            $$ = validate_arithmetic_expression($1, $3, "modulo", "MOD", 1);
        }
    ;

unary_expression
    : postfix_expression
        {
            $$ = $1;
        }
    | INC unary_expression
        {
            $$ = validate_increment_expression($2, "prefix increment", 1, 1);
        }
    | DEC unary_expression
        {
            $$ = validate_increment_expression($2, "prefix decrement", -1, 1);
        }
    | PLUS unary_expression
        {
            $$ = validate_unary_passthrough($2, "unary plus");
        }
    | MINUS unary_expression %prec UMINUS
        {
            $$ = validate_unary_numeric_expression($2, "unary minus", "NEG");
        }
    | NOT_OP unary_expression
        {
            $$ = validate_not_expression($2);
        }
    ;

postfix_expression
    : primary_expression
        {
            $$ = $1;
        }
    | postfix_expression INC
        {
            $$ = validate_increment_expression($1, "postfix increment", 1, 0);
        }
    | postfix_expression DEC
        {
            $$ = validate_increment_expression($1, "postfix decrement", -1, 0);
        }
    | postfix_expression LPAREN argument_expression_list_opt RPAREN
        {
            $$ = validate_function_call($1, $3);
        }
    | postfix_expression LBRACKET expression RBRACKET
        {
            $$ = validate_index_expression($1, $3);
        }
    ;

argument_expression_list_opt
    : /* empty */
        {
            $$ = NULL;
        }
    | argument_expression_list
        {
            $$ = $1;
        }
    ;

argument_expression_list
    : assignment_expression
        {
            $$ = make_argument_list($1);
        }
    | argument_expression_list COMMA assignment_expression
        {
            $$ = append_argument($1, $3);
        }
    ;

primary_expression
    : IDENTIFIER
        {
            Symbol *symbol = symbol_table_lookup($1);

            if (!symbol) {
                symbol_table_report_error(line_num, "undeclared identifier '%s'", $1);
                free($1);
                $$ = make_invalid_expr();
            } else {
                $$ = make_expr(
                    $1,
                    symbol_type(symbol),
                    symbol,
                    symbol_kind(symbol) != SYMBOL_FUNCTION,
                    1,
                    0
                );
            }
        }
    | literal
        {
            $$ = $1;
        }
    | LPAREN expression RPAREN
        {
            $$ = $2;
        }
    ;

literal
    : INTEGER_LITERAL
        {
            $$ = make_expr(format_integer($1), TYPE_INT, NULL, 0, 1, 0);
        }
    | FLOAT_LITERAL
        {
            $$ = make_expr(format_float_literal($1), TYPE_FLOAT, NULL, 0, 1, 0);
        }
    | CHAR_LITERAL
        {
            $$ = make_expr($1, TYPE_CHAR, NULL, 0, 1, 0);
        }
    | STRING_LITERAL
        {
            $$ = make_expr($1, TYPE_INVALID, NULL, 0, 1, 1);
        }
    | TRUE_KW
        {
            $$ = make_expr(duplicate_text("true"), TYPE_BOOL, NULL, 0, 1, 0);
        }
    | FALSE_KW
        {
            $$ = make_expr(duplicate_text("false"), TYPE_BOOL, NULL, 0, 1, 0);
        }
    ;

%%

int main(int argc, char **argv) {
    int result;

    symbol_table_init();
    quadruples_init();

    if (argc > 1) {
        yyin = fopen(argv[1], "r");
        if (!yyin) {
            perror(argv[1]);
            symbol_table_free();
            quadruples_free();
            return 1;
        }
    }

    result = yyparse();

    if (result == 0) {
        symbol_table_report_unused_variables();
        quadruples_print(stdout);
        symbol_table_print(stdout);
    }

    if (result == 0 && error_count == 0 && symbol_table_error_count() == 0) {
        printf("Parsing completed successfully.\n");
        cleanup_parser_state();
        reset_pending_function_signature();
        symbol_table_free();
        quadruples_free();
        return 0;
    }

    cleanup_parser_state();
    reset_pending_function_signature();
    symbol_table_free();
    quadruples_free();
    return 1;
}
