%code requires {
#include "../semantic/symbol_table.h"

typedef struct ExprInfo ExprInfo;
typedef struct ArgumentList ArgumentList;
}

%{
#include "../semantic/symbol_table.h"
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

struct ExprInfo {
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

static TypeKind current_declaration_type = TYPE_INVALID;
static int current_declaration_is_const = 0;
static Symbol *pending_function_definition = NULL;
static Symbol *current_function_symbol = NULL;
static PendingFunctionSignature pending_function_signature = {0};
static int loop_depth = 0;
static int switch_depth = 0;

static void *checked_malloc(size_t size) {
    void *memory = malloc(size);

    if (!memory) {
        perror("malloc");
        exit(EXIT_FAILURE);
    }

    return memory;
}

static char *duplicate_text(const char *text) {
    size_t length = strlen(text) + 1;
    char *copy = checked_malloc(length);

    memcpy(copy, text, length);
    return copy;
}

static ExprInfo *make_expr(
    TypeKind type,
    Symbol *symbol,
    int is_lvalue,
    int is_valid,
    int is_string_literal
) {
    ExprInfo *expr = checked_malloc(sizeof(*expr));

    expr->type = type;
    expr->symbol = symbol;
    expr->is_lvalue = is_lvalue;
    expr->is_valid = is_valid;
    expr->is_string_literal = is_string_literal;
    return expr;
}

static ExprInfo *make_invalid_expr(void) {
    return make_expr(TYPE_INVALID, NULL, 0, 0, 0);
}

static void free_expr(ExprInfo *expr) {
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
    }
}

static ExprInfo *validate_arithmetic_expression(
    ExprInfo *left,
    ExprInfo *right,
    const char *context,
    int require_integer
) {
    int valid = 1;
    TypeKind result_type = TYPE_INVALID;

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
    }

    free_expr(left);
    free_expr(right);
    return make_expr(result_type, NULL, 0, valid, 0);
}

static ExprInfo *validate_logical_expression(ExprInfo *left, ExprInfo *right, const char *context) {
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

    free_expr(left);
    free_expr(right);
    return make_expr(TYPE_BOOL, NULL, 0, valid, 0);
}

static ExprInfo *validate_unary_numeric_expression(ExprInfo *expr, const char *context) {
    TypeKind result_type = TYPE_INVALID;
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
    }

    free_expr(expr);
    return make_expr(result_type, NULL, 0, valid, 0);
}

static ExprInfo *validate_not_expression(ExprInfo *expr) {
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

    free_expr(expr);
    return make_expr(TYPE_BOOL, NULL, 0, valid, 0);
}

static ExprInfo *validate_increment_expression(ExprInfo *expr, const char *context) {
    TypeKind result_type = TYPE_INVALID;
    Symbol *symbol = NULL;
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

    if (valid && expr->symbol) {
        symbol_mark_initialized(expr->symbol);
    }

    if (valid) {
        result_type = expr->type;
        symbol = expr->symbol;
    }

    free_expr(expr);
    return make_expr(result_type, symbol, 0, valid, 0);
}

static ExprInfo *validate_assignment_expression(
    ExprInfo *target,
    const char *assignment_op,
    ExprInfo *value
) {
    TypeKind result_type = TYPE_INVALID;
    Symbol *target_symbol = NULL;
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

    if (target && target->symbol) {
        target_symbol = target->symbol;
    }

    if (valid && target_symbol) {
        symbol_mark_initialized(target_symbol);
        result_type = target->type;
    }

    free_expr(target);
    free_expr(value);
    return make_expr(result_type, target_symbol, 0, valid, 0);
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
                if (!expr_require_rvalue(arguments->items[index], "as a function argument")) {
                    valid = 0;
                    continue;
                }

                if (
                    index < total_parameters &&
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

    free_expr(callee);
    free_argument_list(arguments);
    return make_expr(return_type, NULL, 0, valid, 0);
}

static ExprInfo *validate_index_expression(ExprInfo *base, ExprInfo *index) {
    TypeKind result_type = TYPE_INVALID;
    Symbol *base_symbol = NULL;
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
        result_type = base->type;
        base_symbol = base->symbol;
    }

    free_expr(base);
    free_expr(index);
    return make_expr(result_type, base_symbol, 1, valid, 0);
}

static void reset_pending_function_signature(void) {
    size_t index;

    free(pending_function_signature.name);
    pending_function_signature.name = NULL;

    for (index = 0; index < pending_function_signature.parameter_count; ++index) {
        free(pending_function_signature.parameters[index].name);
    }

    free(pending_function_signature.parameters);
    pending_function_signature.parameters = NULL;
    pending_function_signature.parameter_count = 0;
    pending_function_signature.parameter_capacity = 0;
    pending_function_signature.return_type = TYPE_INVALID;
}

static void begin_function_signature(TypeKind return_type, const char *name) {
    reset_pending_function_signature();
    pending_function_signature.return_type = return_type;
    pending_function_signature.name = duplicate_text(name);
}

static void add_pending_parameter(TypeKind type, const char *name, int has_default_value) {
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

static void prepare_function_definition(Symbol *function_symbol) {
    pending_function_definition = function_symbol;
    current_function_symbol = function_symbol;
    symbol_table_mark_function_defined(function_symbol, line_num);
}

static void finish_function_definition(void) {
    current_function_symbol = NULL;
}

static void enter_compound_scope(void) {
    if (pending_function_definition) {
        symbol_table_enter_function_scope(pending_function_definition);
        pending_function_definition = NULL;
        return;
    }

    symbol_table_enter_block_scope();
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
%type <expr> primary_expression literal
%type <args> argument_expression_list argument_expression_list_opt
%type <str> assignment_operator

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
            prepare_function_definition($1);
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
    ;

parameter_list
    : parameter_declaration
    | parameter_list COMMA parameter_declaration
    ;

parameter_declaration
    : type_specifier IDENTIFIER
        {
            add_pending_parameter($1, $2, 0);
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

            add_pending_parameter($1, $2, 1);
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

            if (symbol && symbol_is_const(symbol) && !$3->is_valid) {
                symbol_mark_initialized(symbol);
            }

            free_expr($3);
            free($1);
        }
    ;

compound_statement
    : scoped_lbrace block_item_list_opt RBRACE
        {
            symbol_table_leave_scope();
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
    | error SEMI    { yyerrok; }
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
    : IF LPAREN expression RPAREN statement %prec LOWER_THAN_ELSE
        {
            validate_condition($3, "in if condition");
            free_expr($3);
        }
    | IF LPAREN expression RPAREN statement ELSE statement
        {
            validate_condition($3, "in if condition");
            free_expr($3);
        }
    | switch_statement
    ;

switch_statement
    : SWITCH LPAREN expression RPAREN
        {
            validate_condition($3, "in switch expression");
            free_expr($3);
            ++switch_depth;
        }
      scoped_lbrace switch_clause_list_opt RBRACE
        {
            symbol_table_leave_scope();
            --switch_depth;
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
                }
            }

            free_expr($2);
        }
    | DEFAULT COLON
    ;

constant_expression
    : expression
        {
            $$ = $1;
        }
    ;

iteration_statement
    : WHILE LPAREN expression RPAREN
        {
            validate_condition($3, "in while condition");
            free_expr($3);
            ++loop_depth;
        }
      statement
        {
            --loop_depth;
        }
    | DO
        {
            ++loop_depth;
        }
      statement WHILE LPAREN expression RPAREN SEMI
        {
            validate_condition($6, "in do-while condition");
            free_expr($6);
            --loop_depth;
        }
    | FOR LPAREN
        {
            symbol_table_enter_block_scope();
        }
      for_init for_cond for_iter RPAREN
        {
            ++loop_depth;
        }
      statement
        {
            --loop_depth;
            symbol_table_leave_scope();
        }
    ;

for_init
    : declaration SEMI
    | expression_opt SEMI
        {
            free_expr($1);
        }
    ;

for_cond
    : expression_opt SEMI
        {
            if ($1) {
                validate_condition($1, "in for condition");
            }

            free_expr($1);
        }
    ;

for_iter
    : expression_opt
        {
            free_expr($1);
        }
    ;

jump_statement
    : BREAK SEMI
        {
            if (loop_depth == 0 && switch_depth == 0) {
                symbol_table_report_error(line_num, "'break' used outside of loop or switch");
            }
        }
    | CONTINUE SEMI
        {
            if (loop_depth == 0) {
                symbol_table_report_error(line_num, "'continue' used outside of loop");
            }
        }
    | RETURN expression_opt SEMI
        {
            TypeKind return_type = current_function_symbol ? symbol_type(current_function_symbol) : TYPE_INVALID;

            if (!current_function_symbol) {
                symbol_table_report_error(line_num, "'return' used outside of a function");
            } else if (return_type == TYPE_VOID) {
                if ($2) {
                    symbol_table_report_error(line_num, "void function '%s' must not return a value", symbol_name(current_function_symbol));
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
            $$ = validate_logical_expression($1, $3, "logical OR");
        }
    ;

logical_and_expression
    : equality_expression
        {
            $$ = $1;
        }
    | logical_and_expression AND_OP equality_expression
        {
            $$ = validate_logical_expression($1, $3, "logical AND");
        }
    ;

equality_expression
    : relational_expression
        {
            $$ = $1;
        }
    | equality_expression EQ_OP relational_expression
        {
            $$ = validate_logical_expression($1, $3, "equality comparison");
        }
    | equality_expression NE_OP relational_expression
        {
            $$ = validate_logical_expression($1, $3, "inequality comparison");
        }
    ;

relational_expression
    : additive_expression
        {
            $$ = $1;
        }
    | relational_expression LT_OP additive_expression
        {
            $$ = validate_logical_expression($1, $3, "relational comparison");
        }
    | relational_expression GT_OP additive_expression
        {
            $$ = validate_logical_expression($1, $3, "relational comparison");
        }
    | relational_expression LE_OP additive_expression
        {
            $$ = validate_logical_expression($1, $3, "relational comparison");
        }
    | relational_expression GE_OP additive_expression
        {
            $$ = validate_logical_expression($1, $3, "relational comparison");
        }
    ;

additive_expression
    : multiplicative_expression
        {
            $$ = $1;
        }
    | additive_expression PLUS multiplicative_expression
        {
            $$ = validate_arithmetic_expression($1, $3, "addition", 0);
        }
    | additive_expression MINUS multiplicative_expression
        {
            $$ = validate_arithmetic_expression($1, $3, "subtraction", 0);
        }
    ;

multiplicative_expression
    : unary_expression
        {
            $$ = $1;
        }
    | multiplicative_expression MULT unary_expression
        {
            $$ = validate_arithmetic_expression($1, $3, "multiplication", 0);
        }
    | multiplicative_expression DIV unary_expression
        {
            $$ = validate_arithmetic_expression($1, $3, "division", 0);
        }
    | multiplicative_expression MOD unary_expression
        {
            $$ = validate_arithmetic_expression($1, $3, "modulo", 1);
        }
    ;

unary_expression
    : postfix_expression
        {
            $$ = $1;
        }
    | INC unary_expression
        {
            $$ = validate_increment_expression($2, "prefix increment");
        }
    | DEC unary_expression
        {
            $$ = validate_increment_expression($2, "prefix decrement");
        }
    | PLUS unary_expression
        {
            $$ = validate_unary_numeric_expression($2, "unary plus");
        }
    | MINUS unary_expression %prec UMINUS
        {
            $$ = validate_unary_numeric_expression($2, "unary minus");
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
            $$ = validate_increment_expression($1, "postfix increment");
        }
    | postfix_expression DEC
        {
            $$ = validate_increment_expression($1, "postfix decrement");
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
                free($1);
                $$ = make_expr(
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
            $$ = make_expr(TYPE_INT, NULL, 0, 1, 0);
        }
    | FLOAT_LITERAL
        {
            $$ = make_expr(TYPE_FLOAT, NULL, 0, 1, 0);
        }
    | CHAR_LITERAL
        {
            free($1);
            $$ = make_expr(TYPE_CHAR, NULL, 0, 1, 0);
        }
    | STRING_LITERAL
        {
            free($1);
            $$ = make_expr(TYPE_INVALID, NULL, 0, 1, 1);
        }
    | TRUE_KW
        {
            $$ = make_expr(TYPE_BOOL, NULL, 0, 1, 0);
        }
    | FALSE_KW
        {
            $$ = make_expr(TYPE_BOOL, NULL, 0, 1, 0);
        }
    ;

%%

int main(int argc, char **argv) {
    int result;

    symbol_table_init();

    if (argc > 1) {
        yyin = fopen(argv[1], "r");
        if (!yyin) {
            perror(argv[1]);
            symbol_table_free();
            return 1;
        }
    }

    result = yyparse();

    if (result == 0) {
        symbol_table_report_unused_variables();
        symbol_table_print(stdout);
    }

    if (result == 0 && error_count == 0 && symbol_table_error_count() == 0) {
        printf("Parsing completed successfully.\n");
        reset_pending_function_signature();
        symbol_table_free();
        return 0;
    }

    reset_pending_function_signature();
    symbol_table_free();
    return 1;
}
