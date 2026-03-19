%{
#include <stdio.h>
#include <stdlib.h>

/* Provided by Flex */
extern int yylex(void);
extern FILE *yyin;
extern int line_num;
extern int error_count;

void yyerror(const char *s);

int yyparse(void);
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

%start translation_unit

%%

translation_unit
    : /* empty */
    | translation_unit external_declaration
    ;

external_declaration
    : function_definition
    | declaration SEMI
    ;

function_definition
    : type_specifier IDENTIFIER LPAREN parameter_list_opt RPAREN compound_statement
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
    | type_specifier IDENTIFIER ASSIGN expression
    ;

type_specifier
    : INT_TYPE
    | FLOAT_TYPE
    | DOUBLE_TYPE
    | CHAR_TYPE
    | BOOL_TYPE
    | VOID_TYPE
    ;

declaration
    : type_specifier init_declarator_list
    | CONST_KW type_specifier init_declarator_list
    ;

init_declarator_list
    : init_declarator
    | init_declarator_list COMMA init_declarator
    ;

init_declarator
    : IDENTIFIER
    | IDENTIFIER ASSIGN expression
    ;

compound_statement
    : LBRACE block_item_list_opt RBRACE
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
    : SWITCH LPAREN expression RPAREN LBRACE switch_clause_list_opt RBRACE
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
    | FOR LPAREN for_init for_cond for_iter RPAREN statement
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
    if (argc > 1) {
        yyin = fopen(argv[1], "r");
        if (!yyin) {
            perror(argv[1]);
            return 1;
        }
    }

    int result = yyparse();
    if (result == 0 && error_count == 0) {
        printf("Parsing completed successfully.\n");
        return 0;
    }

    return 1;
}
