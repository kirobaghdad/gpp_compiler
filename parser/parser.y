%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "symbol_table.h"

/* Provided by Flex */
extern int yylex(void);
extern FILE *yyin;
extern int line_num;

void yyerror(const char *s);

int yyparse(void);

static char *current_declaration_type = NULL;
static int current_declaration_is_const = 0;
static int suppress_next_compound_scope = 0;
static int compound_scope_entries[512];
static int compound_scope_depth = 0;

static char *copy_text(const char *text);
static void begin_declaration(const char *type_name, int is_const);
static void finish_declaration(void);
static void declare_identifier(const char *name, int is_initialized);
static void begin_function_definition(const char *return_type, const char *name);
static void begin_compound_scope(void);
static void end_compound_scope(void);
%}

%define parse.error verbose

%union {
    int ival;
    float fval;
    char* str;
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

%type <ival> global_initializer_opt
%type <str> type_specifier

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
          free($1);
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
          free($1);
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
          free($2);
          free($3);
      }
    ;

global_initializer_opt
    : /* empty */
      {
          $$ = 0;
      }
    | ASSIGN expression
      {
          $$ = 1;
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
          free($1);
          free($2);
      }
    | type_specifier IDENTIFIER ASSIGN expression
      {
          symbol_table_declare($2, $1, SYMBOL_PARAMETER, 1, 1, line_num);
          free($1);
          free($2);
      }
    ;

type_specifier
    : INT_TYPE    { $$ = copy_text("int"); }
    | FLOAT_TYPE  { $$ = copy_text("float"); }
    | DOUBLE_TYPE { $$ = copy_text("double"); }
    | CHAR_TYPE   { $$ = copy_text("char"); }
    | BOOL_TYPE   { $$ = copy_text("bool"); }
    | VOID_TYPE   { $$ = copy_text("void"); }
    ;

declaration
    : type_specifier
      {
          begin_declaration($1, 0);
      }
      init_declarator_list
      {
          finish_declaration();
          free($1);
      }
    | CONST_KW type_specifier
      {
          begin_declaration($2, 1);
      }
      init_declarator_list
      {
          finish_declaration();
          free($2);
      }
    ;

init_declarator_list
    : init_declarator
    | init_declarator_list COMMA init_declarator
    ;

init_declarator
    : IDENTIFIER
      {
          declare_identifier($1, 0);
          free($1);
      }
    | IDENTIFIER ASSIGN expression
      {
          declare_identifier($1, 1);
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
    ;

assignment_expression
    : logical_or_expression
    | unary_expression assignment_operator assignment_expression
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
    | logical_or_expression OR_OP logical_and_expression
    ;

logical_and_expression
    : equality_expression
    | logical_and_expression AND_OP equality_expression
    ;

equality_expression
    : relational_expression
    | equality_expression EQ_OP relational_expression
    | equality_expression NE_OP relational_expression
    ;

relational_expression
    : additive_expression
    | relational_expression LT_OP additive_expression
    | relational_expression GT_OP additive_expression
    | relational_expression LE_OP additive_expression
    | relational_expression GE_OP additive_expression
    ;

additive_expression
    : multiplicative_expression
    | additive_expression PLUS multiplicative_expression
    | additive_expression MINUS multiplicative_expression
    ;

multiplicative_expression
    : unary_expression
    | multiplicative_expression MULT unary_expression
    | multiplicative_expression DIV unary_expression
    | multiplicative_expression MOD unary_expression
    ;

unary_expression
    : postfix_expression
    | INC unary_expression
    | DEC unary_expression
    | PLUS unary_expression
    | MINUS unary_expression %prec UMINUS
    | NOT_OP unary_expression
    ;

postfix_expression
    : primary_expression
    | postfix_expression INC
    | postfix_expression DEC
    | postfix_expression LPAREN argument_expression_list_opt RPAREN
    | postfix_expression LBRACKET expression RBRACKET
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
          symbol_table_mark_used($1, line_num);
          free($1);
      }
    | literal
    | LPAREN expression RPAREN
    ;

literal
    : INTEGER_LITERAL
    | FLOAT_LITERAL
    | CHAR_LITERAL
    | STRING_LITERAL
    | TRUE_KW
    | FALSE_KW
    ;

%%

static char *copy_text(const char *text) {
    size_t len;
    char *copy;

    if (!text) {
        return NULL;
    }

    len = strlen(text) + 1;
    copy = (char *)malloc(len);
    if (!copy) {
        fprintf(stderr, "Out of memory while duplicating parser text.\n");
        exit(1);
    }

    memcpy(copy, text, len);
    return copy;
}

static void begin_declaration(const char *type_name, int is_const) {
    free(current_declaration_type);
    current_declaration_type = copy_text(type_name);
    current_declaration_is_const = is_const;
}

static void finish_declaration(void) {
    free(current_declaration_type);
    current_declaration_type = NULL;
    current_declaration_is_const = 0;
}

static void declare_identifier(const char *name, int is_initialized) {
    SymbolKind kind = current_declaration_is_const ? SYMBOL_CONSTANT : SYMBOL_VARIABLE;

    if (current_declaration_is_const && !is_initialized) {
        symbol_table_report_semantic_error("constant must be initialized", name, line_num);
    }

    symbol_table_declare(
        name,
        current_declaration_type ? current_declaration_type : "unknown",
        kind,
        is_initialized,
        0,
        line_num
    );
}

static void begin_function_definition(const char *return_type, const char *name) {
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
