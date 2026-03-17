%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "symbol_table.h"

typedef struct ExprInfo ExprInfo;

/* Provided by Flex */
extern int yylex(void);
extern FILE *yyin;
extern int line_num;

void yyerror(const char *s);

int yyparse(void);

static TypeKind current_declaration_type = TYPE_UNKNOWN;
static int current_declaration_is_const = 0;
static int suppress_next_compound_scope = 0;
static int compound_scope_entries[512];
static int compound_scope_depth = 0;

static void begin_declaration(TypeKind type_name, int is_const);
static void finish_declaration(void);
static void declare_identifier(const char *name, ExprInfo initializer);
static void begin_function_definition(TypeKind return_type, const char *name);
static void begin_compound_scope(void);
static void end_compound_scope(void);
static ExprInfo make_expr(TypeKind type, int is_lvalue);
static void report_type_mismatch(const char *context, const char *name, TypeKind target_type, TypeKind value_type);
static ExprInfo infer_identifier_expression(const char *name);
static ExprInfo infer_arithmetic_expression(const char *operator_name, ExprInfo left, ExprInfo right);
static ExprInfo infer_comparison_expression(const char *operator_name, ExprInfo left, ExprInfo right);
static ExprInfo infer_logical_expression(const char *operator_name, ExprInfo left, ExprInfo right);
%}

%define parse.error verbose

%code requires {
    #include "symbol_table.h"

    typedef struct ExprInfo {
        TypeKind type;
        int is_lvalue;
    } ExprInfo;
}

%union {
    int ival;
    float fval;
    char* str;
    ExprInfo expr;
    TypeKind type_kind;
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

%type <expr> global_initializer_opt
%type <expr> constant_expression
%type <expr> expression
%type <expr> assignment_expression
%type <expr> logical_or_expression
%type <expr> logical_and_expression
%type <expr> equality_expression
%type <expr> relational_expression
%type <expr> additive_expression
%type <expr> multiplicative_expression
%type <expr> unary_expression
%type <expr> postfix_expression
%type <expr> primary_expression
%type <expr> literal
%type <type_kind> type_specifier

%start translation_unit

%%

translation_unit
    : /* empty */
    | translation_unit external_declaration
    ;

external_declaration
    : type_specifier IDENTIFIER LPAREN
      {
          begin_function_definition($1, $2);
      }
      parameter_list_opt RPAREN compound_statement
      {
          symbol_table_leave_scope();
          free($2);
      }
    | type_specifier IDENTIFIER global_initializer_opt
      {
          begin_declaration($1, 0);
          declare_identifier($2, $3);
      }
      global_init_declarator_tail SEMI
      {
          finish_declaration();
          free($2);
      }
    | CONST_KW type_specifier IDENTIFIER global_initializer_opt
      {
          begin_declaration($2, 1);
          declare_identifier($3, $4);
      }
      global_init_declarator_tail SEMI
      {
          finish_declaration();
          free($3);
      }
    ;

global_initializer_opt
    : /* empty */
      {
          $$ = make_expr(TYPE_UNKNOWN, 0);
      }
    | ASSIGN expression
      {
          $$ = $2;
      }
    ;

global_init_declarator_tail
    : /* empty */
    | COMMA init_declarator_list
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
          symbol_table_declare($2, $1, SYMBOL_PARAMETER, 1, 0, line_num);
          free($2);
      }
    | type_specifier IDENTIFIER ASSIGN expression
      {
          if (!type_can_assign($1, $4.type)) {
              report_type_mismatch("default value", $2, $1, $4.type);
          }
          symbol_table_declare($2, $1, SYMBOL_PARAMETER, 1, 1, line_num);
          free($2);
      }
    ;

type_specifier
    : INT_TYPE    { $$ = TYPE_INT; }
    | FLOAT_TYPE  { $$ = TYPE_FLOAT; }
    | DOUBLE_TYPE { $$ = TYPE_DOUBLE; }
    | CHAR_TYPE   { $$ = TYPE_CHAR; }
    | BOOL_TYPE   { $$ = TYPE_BOOL; }
    | VOID_TYPE   { $$ = TYPE_VOID; }
    ;

declaration
    : type_specifier
      {
          begin_declaration($1, 0);
      }
      init_declarator_list
      {
          finish_declaration();
      }
    | CONST_KW type_specifier
      {
          begin_declaration($2, 1);
      }
      init_declarator_list
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
          declare_identifier($1, make_expr(TYPE_UNKNOWN, 0));
          free($1);
      }
    | IDENTIFIER ASSIGN expression
      {
          declare_identifier($1, $3);
          free($1);
      }
    ;

compound_statement
    : LBRACE
      {
          begin_compound_scope();
      }
      block_item_list_opt
      RBRACE
      {
          end_compound_scope();
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
    ;

expression_opt
    : /* empty */
    | expression
    ;

selection_statement
    : IF LPAREN expression RPAREN statement %prec LOWER_THAN_ELSE
    | IF LPAREN expression RPAREN statement ELSE statement
    | switch_statement
    ;

switch_statement
    : SWITCH LPAREN expression RPAREN LBRACE
      {
          symbol_table_enter_scope("switch");
      }
      switch_clause_list_opt
      RBRACE
      {
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
    : case_label statement_list_opt
    ;

case_label
    : CASE constant_expression COLON
    | DEFAULT COLON
    ;

constant_expression
    : expression
      {
          $$ = $1;
      }
    ;

statement_list_opt
    : /* empty */
    | statement_list
    ;

statement_list
    : statement
    | statement_list statement
    ;

iteration_statement
    : WHILE LPAREN expression RPAREN statement
    | DO statement WHILE LPAREN expression RPAREN SEMI
    | FOR LPAREN
      {
          symbol_table_enter_scope("for");
      }
      for_init for_cond for_iter RPAREN statement
      {
          symbol_table_leave_scope();
      }
    ;

for_init
    : declaration SEMI
    | expression_opt SEMI
    ;

for_cond
    : expression_opt SEMI
    ;

for_iter
    : expression_opt
    ;

jump_statement
    : BREAK SEMI
    | CONTINUE SEMI
    | RETURN expression_opt SEMI
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
          if (!$1.is_lvalue) {
              symbol_table_report_semantic_error("left-hand side of assignment must be assignable", NULL, line_num);
          }

          if (!type_can_assign($1.type, $3.type)) {
              report_type_mismatch("assignment", NULL, $1.type, $3.type);
          }

          $$ = make_expr($1.type, 0);
      }
    ;

assignment_operator
    : ASSIGN
    | ADD_ASSIGN
    | SUB_ASSIGN
    | MUL_ASSIGN
    | DIV_ASSIGN
    | MOD_ASSIGN
    ;

logical_or_expression
    : logical_and_expression
      {
          $$ = $1;
      }
    | logical_or_expression OR_OP logical_and_expression
      {
          $$ = infer_logical_expression("||", $1, $3);
      }
    ;

logical_and_expression
    : equality_expression
      {
          $$ = $1;
      }
    | logical_and_expression AND_OP equality_expression
      {
          $$ = infer_logical_expression("&&", $1, $3);
      }
    ;

equality_expression
    : relational_expression
      {
          $$ = $1;
      }
    | equality_expression EQ_OP relational_expression
      {
          $$ = infer_comparison_expression("==", $1, $3);
      }
    | equality_expression NE_OP relational_expression
      {
          $$ = infer_comparison_expression("!=", $1, $3);
      }
    ;

relational_expression
    : additive_expression
      {
          $$ = $1;
      }
    | relational_expression LT_OP additive_expression
      {
          $$ = infer_comparison_expression("<", $1, $3);
      }
    | relational_expression GT_OP additive_expression
      {
          $$ = infer_comparison_expression(">", $1, $3);
      }
    | relational_expression LE_OP additive_expression
      {
          $$ = infer_comparison_expression("<=", $1, $3);
      }
    | relational_expression GE_OP additive_expression
      {
          $$ = infer_comparison_expression(">=", $1, $3);
      }
    ;

additive_expression
    : multiplicative_expression
      {
          $$ = $1;
      }
    | additive_expression PLUS multiplicative_expression
      {
          $$ = infer_arithmetic_expression("+", $1, $3);
      }
    | additive_expression MINUS multiplicative_expression
      {
          $$ = infer_arithmetic_expression("-", $1, $3);
      }
    ;

multiplicative_expression
    : unary_expression
      {
          $$ = $1;
      }
    | multiplicative_expression MULT unary_expression
      {
          $$ = infer_arithmetic_expression("*", $1, $3);
      }
    | multiplicative_expression DIV unary_expression
      {
          $$ = infer_arithmetic_expression("/", $1, $3);
      }
    | multiplicative_expression MOD unary_expression
      {
          if (!type_is_integral($1.type) || !type_is_integral($3.type)) {
              symbol_table_report_semantic_error("operator '%' requires integer operands", NULL, line_num);
              $$ = make_expr(TYPE_ERROR, 0);
          } else {
              $$ = make_expr(TYPE_INT, 0);
          }
      }
    ;

unary_expression
    : postfix_expression
      {
          $$ = $1;
      }
    | INC unary_expression
      {
          if (!$2.is_lvalue || !type_is_numeric($2.type)) {
              symbol_table_report_semantic_error("operator '++' requires a numeric assignable operand", NULL, line_num);
              $$ = make_expr(TYPE_ERROR, 0);
          } else {
              $$ = make_expr($2.type, 0);
          }
      }
    | DEC unary_expression
      {
          if (!$2.is_lvalue || !type_is_numeric($2.type)) {
              symbol_table_report_semantic_error("operator '--' requires a numeric assignable operand", NULL, line_num);
              $$ = make_expr(TYPE_ERROR, 0);
          } else {
              $$ = make_expr($2.type, 0);
          }
      }
    | PLUS unary_expression
      {
          if (!type_is_numeric($2.type)) {
              symbol_table_report_semantic_error("unary '+' requires a numeric operand", NULL, line_num);
              $$ = make_expr(TYPE_ERROR, 0);
          } else {
              $$ = make_expr($2.type, 0);
          }
      }
    | MINUS unary_expression %prec UMINUS
      {
          if (!type_is_numeric($2.type)) {
              symbol_table_report_semantic_error("unary '-' requires a numeric operand", NULL, line_num);
              $$ = make_expr(TYPE_ERROR, 0);
          } else {
              $$ = make_expr($2.type, 0);
          }
      }
    | NOT_OP unary_expression
      {
          if (!type_is_condition($2.type)) {
              symbol_table_report_semantic_error("operator '!' requires a boolean or numeric operand", NULL, line_num);
              $$ = make_expr(TYPE_ERROR, 0);
          } else {
              $$ = make_expr(TYPE_BOOL, 0);
          }
      }
    ;

postfix_expression
    : primary_expression
      {
          $$ = $1;
      }
    | postfix_expression INC
      {
          if (!$1.is_lvalue || !type_is_numeric($1.type)) {
              symbol_table_report_semantic_error("operator '++' requires a numeric assignable operand", NULL, line_num);
              $$ = make_expr(TYPE_ERROR, 0);
          } else {
              $$ = make_expr($1.type, 0);
          }
      }
    | postfix_expression DEC
      {
          if (!$1.is_lvalue || !type_is_numeric($1.type)) {
              symbol_table_report_semantic_error("operator '--' requires a numeric assignable operand", NULL, line_num);
              $$ = make_expr(TYPE_ERROR, 0);
          } else {
              $$ = make_expr($1.type, 0);
          }
      }
    | postfix_expression LPAREN argument_expression_list_opt RPAREN
      {
          $$ = make_expr($1.type, 0);
      }
    | postfix_expression LBRACKET expression RBRACKET
      {
          $$ = make_expr($1.type, 1);
      }
    ;

argument_expression_list_opt
    : /* empty */
    | argument_expression_list
    ;

argument_expression_list
    : assignment_expression
    | argument_expression_list COMMA assignment_expression
    ;

primary_expression
    : IDENTIFIER
      {
          $$ = infer_identifier_expression($1);
          free($1);
      }
    | literal
      {
          $$ = $1;
      }
    | LPAREN expression RPAREN
      {
          $$ = make_expr($2.type, 0);
      }
    ;

literal
    : INTEGER_LITERAL
      {
          $$ = make_expr(TYPE_INT, 0);
      }
    | FLOAT_LITERAL
      {
          $$ = make_expr(TYPE_FLOAT, 0);
      }
    | CHAR_LITERAL
      {
          $$ = make_expr(TYPE_CHAR, 0);
      }
    | STRING_LITERAL
      {
          $$ = make_expr(TYPE_STRING, 0);
      }
    | TRUE_KW
      {
          $$ = make_expr(TYPE_BOOL, 0);
      }
    | FALSE_KW
      {
          $$ = make_expr(TYPE_BOOL, 0);
      }
    ;

%%

static void begin_declaration(TypeKind type_name, int is_const) {
    current_declaration_type = type_name;
    current_declaration_is_const = is_const;
}

static void finish_declaration(void) {
    current_declaration_type = TYPE_UNKNOWN;
    current_declaration_is_const = 0;
}

static ExprInfo make_expr(TypeKind type, int is_lvalue) {
    ExprInfo expr;

    expr.type = type;
    expr.is_lvalue = is_lvalue;
    return expr;
}

static void report_type_mismatch(const char *context, const char *name, TypeKind target_type, TypeKind value_type) {
    char message[256];

    if (name) {
        snprintf(
            message,
            sizeof(message),
            "type mismatch in %s for '%s': expected '%s' but found '%s'",
            context ? context : "expression",
            name,
            type_kind_name(target_type),
            type_kind_name(value_type)
        );
    } else {
        snprintf(
            message,
            sizeof(message),
            "type mismatch in %s: expected '%s' but found '%s'",
            context ? context : "expression",
            type_kind_name(target_type),
            type_kind_name(value_type)
        );
    }

    symbol_table_report_semantic_error(message, NULL, line_num);
}

static ExprInfo infer_identifier_expression(const char *name) {
    SymbolEntry *entry = symbol_table_lookup(name);

    if (!entry) {
        symbol_table_mark_used(name, line_num);
        return make_expr(TYPE_ERROR, 0);
    }

    entry->is_used = 1;
    return make_expr(entry->type_kind, entry->kind != SYMBOL_FUNCTION);
}

static ExprInfo infer_arithmetic_expression(const char *operator_name, ExprInfo left, ExprInfo right) {
    if (!type_is_numeric(left.type) || !type_is_numeric(right.type)) {
        char message[128];
        snprintf(message, sizeof(message), "operator '%s' requires numeric operands", operator_name);
        symbol_table_report_semantic_error(message, NULL, line_num);
        return make_expr(TYPE_ERROR, 0);
    }

    return make_expr(type_common_numeric(left.type, right.type), 0);
}

static ExprInfo infer_comparison_expression(const char *operator_name, ExprInfo left, ExprInfo right) {
    if (type_can_compare(left.type, right.type)) {
        return make_expr(TYPE_BOOL, 0);
    }

    {
        char message[128];
        snprintf(message, sizeof(message), "operator '%s' requires comparable operand types", operator_name);
        symbol_table_report_semantic_error(message, NULL, line_num);
    }
    return make_expr(TYPE_ERROR, 0);
}

static ExprInfo infer_logical_expression(const char *operator_name, ExprInfo left, ExprInfo right) {
    if (!type_is_condition(left.type) || !type_is_condition(right.type)) {
        char message[128];
        snprintf(message, sizeof(message), "operator '%s' requires boolean or numeric operands", operator_name);
        symbol_table_report_semantic_error(message, NULL, line_num);
        return make_expr(TYPE_ERROR, 0);
    }

    return make_expr(TYPE_BOOL, 0);
}

static void declare_identifier(const char *name, ExprInfo initializer) {
    SymbolKind kind = current_declaration_is_const ? SYMBOL_CONSTANT : SYMBOL_VARIABLE;
    int is_initialized = initializer.type != TYPE_UNKNOWN;

    if (current_declaration_is_const && !is_initialized) {
        symbol_table_report_semantic_error("constant must be initialized", name, line_num);
    }

    if (initializer.type != TYPE_UNKNOWN && !type_can_assign(current_declaration_type, initializer.type)) {
        report_type_mismatch("initialization", name, current_declaration_type, initializer.type);
        is_initialized = 0;
    }

    symbol_table_declare(
        name,
        current_declaration_type,
        kind,
        is_initialized,
        0,
        line_num
    );
}

static void begin_function_definition(TypeKind return_type, const char *name) {
    char scope_label[256];

    symbol_table_declare(name, return_type, SYMBOL_FUNCTION, 1, 0, line_num);

    snprintf(scope_label, sizeof(scope_label), "function:%s", name);
    symbol_table_enter_scope(scope_label);
    suppress_next_compound_scope = 1;
}

static void begin_compound_scope(void) {
    int entered_scope = 1;

    if (suppress_next_compound_scope) {
        suppress_next_compound_scope = 0;
        entered_scope = 0;
    } else {
        symbol_table_enter_scope("block");
    }

    if (compound_scope_depth < (int)(sizeof(compound_scope_entries) / sizeof(compound_scope_entries[0]))) {
        compound_scope_entries[compound_scope_depth++] = entered_scope;
    }
}

static void end_compound_scope(void) {
    int entered_scope;

    if (compound_scope_depth == 0) {
        return;
    }

    entered_scope = compound_scope_entries[--compound_scope_depth];
    if (entered_scope) {
        symbol_table_leave_scope();
    }
}

int main(int argc, char **argv) {
    int result;
    int semantic_errors;

    symbol_table_init();

    if (argc > 1) {
        yyin = fopen(argv[1], "r");
        if (!yyin) {
            perror(argv[1]);
            symbol_table_destroy();
            return 1;
        }
    }

    result = yyparse();
    semantic_errors = symbol_table_semantic_error_count();
    symbol_table_dump(stdout);
    symbol_table_destroy();

    return result || semantic_errors;
}
