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
    int is_lvalue;
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

static ExprInfo *make_expr(char *place, TypeKind type, int is_lvalue) {
    ExprInfo *expr = checked_malloc(sizeof(*expr));

    expr->place = place;
    expr->type = type;
    expr->is_lvalue = is_lvalue;
    return expr;
}

static void free_expr(ExprInfo *expr) {
    if (!expr) {
        return;
    }

    free(expr->place);
    free(expr);
}

static TypeKind merge_expression_types(TypeKind left, TypeKind right) {
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

static ExprInfo *emit_binary_operation(const char *op, ExprInfo *left, ExprInfo *right) {
    char *temp = quadruple_new_temp();
    TypeKind type = merge_expression_types(
        left ? left->type : TYPE_INVALID,
        right ? right->type : TYPE_INVALID
    );

    quadruple_emit(op, left ? left->place : "-", right ? right->place : "-", temp);
    free_expr(left);
    free_expr(right);
    return make_expr(temp, type, 0);
}

static ExprInfo *emit_unary_operation(const char *op, ExprInfo *operand) {
    char *temp;
    TypeKind type;

    if (!operand) {
        return NULL;
    }

    temp = quadruple_new_temp();
    type = operand->type;

    quadruple_emit(op, operand->place, "-", temp);
    free_expr(operand);
    return make_expr(temp, type, 0);
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

static ExprInfo *emit_assignment_expression(
    ExprInfo *target,
    const char *assignment_op,
    ExprInfo *value
) {
    char *result_place;
    const char *compound_op;

    if (!target || !value || !assignment_op) {
        free_expr(target);
        free_expr(value);
        return NULL;
    }

    result_place = duplicate_text(target->place);
    compound_op = compound_assignment_operation(assignment_op);

    if (strcmp(assignment_op, "ASSIGN") == 0) {
        quadruple_emit("ASSIGN", value->place, "-", target->place);
    } else if (compound_op) {
        char *temp = quadruple_new_temp();

        quadruple_emit(compound_op, target->place, value->place, temp);
        quadruple_emit("ASSIGN", temp, "-", target->place);
        free(temp);
    }

    free_expr(target);
    free_expr(value);
    return make_expr(result_place, TYPE_INVALID, 0);
}

static ExprInfo *emit_increment_expression(ExprInfo *target, int delta, int is_prefix) {
    char *updated_value;
    char *result_place;
    TypeKind type;

    if (!target) {
        return NULL;
    }

    updated_value = quadruple_new_temp();
    result_place = NULL;

    if (!is_prefix) {
        result_place = quadruple_new_temp();
        quadruple_emit("ASSIGN", target->place, "-", result_place);
    }

    quadruple_emit(delta > 0 ? "ADD" : "SUB", target->place, "1", updated_value);
    quadruple_emit("ASSIGN", updated_value, "-", target->place);
    free(updated_value);

    if (is_prefix) {
        result_place = duplicate_text(target->place);
    }

    type = target->type;
    free_expr(target);
    return make_expr(result_place, type, 0);
}

static ExprInfo *emit_index_expression(ExprInfo *base, ExprInfo *index) {
    int needed;
    char *place;
    TypeKind type;

    if (!base || !index) {
        free_expr(base);
        free_expr(index);
        return NULL;
    }

    needed = snprintf(NULL, 0, "%s[%s]", base->place, index->place);
    place = checked_malloc((size_t)needed + 1);
    snprintf(place, (size_t)needed + 1, "%s[%s]", base->place, index->place);
    type = base->type;

    free_expr(base);
    free_expr(index);
    return make_expr(place, type, 1);
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

static ExprInfo *emit_function_call(ExprInfo *callee, ArgumentList *arguments) {
    Symbol *symbol;
    TypeKind result_type;
    char *argument_count;
    char *result_place;
    size_t index;

    if (!callee) {
        free_argument_list(arguments);
        return NULL;
    }

    symbol = symbol_table_lookup(callee->place);
    result_type = symbol && symbol_kind(symbol) == SYMBOL_FUNCTION
        ? symbol_type(symbol)
        : TYPE_INVALID;

    if (arguments) {
        for (index = 0; index < arguments->count; ++index) {
            quadruple_emit("PARAM", arguments->items[index]->place, "-", "-");
        }
    }

    argument_count = format_integer(arguments ? (int)arguments->count : 0);

    if (result_type == TYPE_VOID) {
        quadruple_emit("CALL", callee->place, argument_count, "-");
        free(argument_count);
        free_expr(callee);
        free_argument_list(arguments);
        return make_expr(duplicate_text("-"), TYPE_VOID, 0);
    }

    result_place = quadruple_new_temp();
    quadruple_emit("CALL", callee->place, argument_count, result_place);
    free(argument_count);
    free_expr(callee);
    free_argument_list(arguments);
    return make_expr(result_place, result_type, 0);
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

static void declare_current_variable(const char *name, int is_initialized) {
    symbol_table_declare_variable(
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
    symbol_table_mark_function_defined(function_symbol, line_num);

    free(current_function_name);
    function_name = symbol_name(function_symbol);
    current_function_name = duplicate_text(function_name ? function_name : "anonymous");
    quadruple_emit("FUNC_BEGIN", current_function_name, "-", "-");
}

static void finish_function_definition(void) {
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
    if (context && condition) {
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

    if (condition) {
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

    if (condition) {
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

    context->expression_place = duplicate_text(expression ? expression->place : "-");
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

static void emit_switch_case_label(ExprInfo *value) {
    SwitchCase *switch_case;
    SwitchContext *context = current_switch_context();

    if (!context || !value) {
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
            declare_current_variable($1, 1);
            if ($3) {
                quadruple_emit("ASSIGN", $3->place, "-", $1);
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
                quadruple_emit("JMP_FALSE", $3->place, "-", false_label);
            }

            free_expr($3);
            $$ = false_label;
        }
    ;

switch_statement
    : SWITCH LPAREN expression RPAREN
        {
            begin_switch_context($3);
            free_expr($3);
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
            emit_switch_case_label($2);
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
            while_emit_condition($3, $4);
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
            finish_do_while_loop($1, $6);
        }
    | FOR LPAREN for_start for_init
        {
            for_after_init($3);
        }
      for_cond
        {
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
    ;

for_cond
    : expression_opt SEMI
        {
            $$ = $1;
        }
    ;

for_iter
    : expression_opt
        {
            $$ = $1;
        }
    ;

jump_statement
    : BREAK SEMI
        {
            const char *label = current_break_label();

            if (label) {
                quadruple_emit("JMP", "-", "-", label);
            }
        }
    | CONTINUE SEMI
        {
            const char *label = current_continue_label();

            if (label) {
                quadruple_emit("JMP", "-", "-", label);
            }
        }
    | RETURN expression_opt SEMI
        {
            quadruple_emit(
                "RETURN",
                $2 ? $2->place : "-",
                "-",
                current_function_name ? current_function_name : "-"
            );
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
            $$ = emit_assignment_expression($1, $2, $3);
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
            $$ = emit_binary_operation("OR", $1, $3);
        }
    ;

logical_and_expression
    : equality_expression
        {
            $$ = $1;
        }
    | logical_and_expression AND_OP equality_expression
        {
            $$ = emit_binary_operation("AND", $1, $3);
        }
    ;

equality_expression
    : relational_expression
        {
            $$ = $1;
        }
    | equality_expression EQ_OP relational_expression
        {
            $$ = emit_binary_operation("EQ", $1, $3);
        }
    | equality_expression NE_OP relational_expression
        {
            $$ = emit_binary_operation("NE", $1, $3);
        }
    ;

relational_expression
    : additive_expression
        {
            $$ = $1;
        }
    | relational_expression LT_OP additive_expression
        {
            $$ = emit_binary_operation("LT", $1, $3);
        }
    | relational_expression GT_OP additive_expression
        {
            $$ = emit_binary_operation("GT", $1, $3);
        }
    | relational_expression LE_OP additive_expression
        {
            $$ = emit_binary_operation("LE", $1, $3);
        }
    | relational_expression GE_OP additive_expression
        {
            $$ = emit_binary_operation("GE", $1, $3);
        }
    ;

additive_expression
    : multiplicative_expression
        {
            $$ = $1;
        }
    | additive_expression PLUS multiplicative_expression
        {
            $$ = emit_binary_operation("ADD", $1, $3);
        }
    | additive_expression MINUS multiplicative_expression
        {
            $$ = emit_binary_operation("SUB", $1, $3);
        }
    ;

multiplicative_expression
    : unary_expression
        {
            $$ = $1;
        }
    | multiplicative_expression MULT unary_expression
        {
            $$ = emit_binary_operation("MUL", $1, $3);
        }
    | multiplicative_expression DIV unary_expression
        {
            $$ = emit_binary_operation("DIV", $1, $3);
        }
    | multiplicative_expression MOD unary_expression
        {
            $$ = emit_binary_operation("MOD", $1, $3);
        }
    ;

unary_expression
    : postfix_expression
        {
            $$ = $1;
        }
    | INC unary_expression
        {
            $$ = emit_increment_expression($2, 1, 1);
        }
    | DEC unary_expression
        {
            $$ = emit_increment_expression($2, -1, 1);
        }
    | PLUS unary_expression
        {
            $$ = $2;
        }
    | MINUS unary_expression %prec UMINUS
        {
            $$ = emit_unary_operation("NEG", $2);
        }
    | NOT_OP unary_expression
        {
            $$ = emit_unary_operation("NOT", $2);
        }
    ;

postfix_expression
    : primary_expression
        {
            $$ = $1;
        }
    | postfix_expression INC
        {
            $$ = emit_increment_expression($1, 1, 0);
        }
    | postfix_expression DEC
        {
            $$ = emit_increment_expression($1, -1, 0);
        }
    | postfix_expression LPAREN argument_expression_list_opt RPAREN
        {
            $$ = emit_function_call($1, $3);
        }
    | postfix_expression LBRACKET expression RBRACKET
        {
            $$ = emit_index_expression($1, $3);
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
            TypeKind type = symbol ? symbol_type(symbol) : TYPE_INVALID;

            $$ = make_expr($1, type, 1);
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
            $$ = make_expr(format_integer($1), TYPE_INT, 0);
        }
    | FLOAT_LITERAL
        {
            $$ = make_expr(format_float_literal($1), TYPE_FLOAT, 0);
        }
    | CHAR_LITERAL
        {
            $$ = make_expr($1, TYPE_CHAR, 0);
        }
    | STRING_LITERAL
        {
            $$ = make_expr($1, TYPE_CHAR, 0);
        }
    | TRUE_KW
        {
            $$ = make_expr(duplicate_text("true"), TYPE_BOOL, 0);
        }
    | FALSE_KW
        {
            $$ = make_expr(duplicate_text("false"), TYPE_BOOL, 0);
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
