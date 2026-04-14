%code requires {
#include "../semantic/symbol_table.h"
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

static TypeKind current_declaration_type = TYPE_INVALID;
static int current_declaration_is_const = 0;
static Symbol *pending_function_definition = NULL;
static PendingFunctionSignature pending_function_signature = {0};

static char *duplicate_text(const char *text) {
    size_t length = strlen(text) + 1;
    char *copy = malloc(length);

    if (!copy) {
        perror("malloc");
        exit(EXIT_FAILURE);
    }

    memcpy(copy, text, length);
    return copy;
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

    if (pending_function_signature.parameter_count == pending_function_signature.parameter_capacity) {
        size_t new_capacity = pending_function_signature.parameter_capacity == 0
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

static void prepare_function_definition(Symbol *function_symbol) {
    pending_function_definition = function_symbol;
    symbol_table_mark_function_defined(function_symbol, line_num);
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
    : SWITCH LPAREN expression RPAREN scoped_lbrace switch_clause_list_opt RBRACE
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
    : case_label block_item_list_opt
    ;

case_label
    : CASE constant_expression COLON
    | DEFAULT COLON
    ;

constant_expression
    : expression
    ;

iteration_statement
    : WHILE LPAREN expression RPAREN statement
    | DO statement WHILE LPAREN expression RPAREN SEMI
    | FOR LPAREN
        {
            symbol_table_enter_block_scope();
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
