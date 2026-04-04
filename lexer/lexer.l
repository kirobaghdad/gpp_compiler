%{
#include "../parser/yacc_tab.h" 
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int line_num = 1;
int comment_start_line = 1;
int error_count = 0;

void yyerror(const char *s);

static char *dup_lexeme(const char *text) {
    size_t len = strlen(text) + 1;
    char *copy = malloc(len);

    if (!copy) {
        perror("malloc");
        exit(EXIT_FAILURE);
    }

    memcpy(copy, text, len);
    return copy;
}
%}

%option noyywrap noinput nounput
%x COMMENT

DIGIT       [0-9]
LETTER      [a-zA-Z_]
ID          {LETTER}({LETTER}|{DIGIT})*
NUM         {DIGIT}+
REAL        ({DIGIT}+"."{DIGIT}*|"."{DIGIT}+)
WHITESPACE  [ \t\r]+

%%

"//".*                                    { /* Single-line comment */ }

"/*"                                        {
                                            comment_start_line = line_num;
                                            BEGIN(COMMENT);
                                          }

<COMMENT>"*/"                               { BEGIN(INITIAL); }
<COMMENT>\n                                 { line_num++; }
<COMMENT>.                                  { /* Consume comment text */ }
<COMMENT><<EOF>>                            {
                                            error_count++;
                                            printf("Lexical Error: Unterminated multi-line comment starting at line %d\n", comment_start_line);
                                            BEGIN(INITIAL);
                                            return 0;
                                          }
%{
// Supported Keywords
%}

"int"       { return INT_TYPE; }
"float"     { return FLOAT_TYPE; }
"double"    { return DOUBLE_TYPE; }
"char"      { return CHAR_TYPE; }
"bool"      { return BOOL_TYPE; }
"void"      { return VOID_TYPE; }

"const"     { return CONST_KW; }

"if"        { return IF; }
"else"      { return ELSE; }
"while"     { return WHILE; }
"do"        { return DO; }
"for"       { return FOR; }
"switch"    { return SWITCH; }
"case"      { return CASE; }
"default"   { return DEFAULT; }
"break"     { return BREAK; }
"continue"  { return CONTINUE; }
"return"    { return RETURN; }

"true"      { return TRUE_KW; }
"false"     { return FALSE_KW; }

{REAL}      { yylval.fval = atof(yytext); return FLOAT_LITERAL; }
{NUM}       { yylval.ival = atoi(yytext); return INTEGER_LITERAL; }

L?'(\\.|[^\\'])+' { yylval.str = dup_lexeme(yytext); return CHAR_LITERAL; }
L?\"(\\.|[^\\"])*\" { yylval.str = dup_lexeme(yytext); return STRING_LITERAL; }

"+"         { return PLUS; }
"-"         { return MINUS; }
"*"         { return MULT; }
"/"         { return DIV; }
"%"         { return MOD; }
"++"        { return INC; }
"--"        { return DEC; }

"=="        { return EQ_OP; }
"!="        { return NE_OP; }
"<"         { return LT_OP; }
">"         { return GT_OP; }
"<="        { return LE_OP; }
">="        { return GE_OP; }

"&&"        { return AND_OP; }
"||"        { return OR_OP; }
"!"         { return NOT_OP; }

"="         { return ASSIGN; }
"+="        { return ADD_ASSIGN; }
"-="        { return SUB_ASSIGN; }
"*="        { return MUL_ASSIGN; }
"/="        { return DIV_ASSIGN; }
"%="        { return MOD_ASSIGN; }

"("         { return LPAREN; }
")"         { return RPAREN; }
"{"         { return LBRACE; }
"}"         { return RBRACE; }
"["         { return LBRACKET; }
"]"         { return RBRACKET; }
";"         { return SEMI; }
","         { return COMMA; }
":"         { return COLON; }

{ID}        { yylval.str = dup_lexeme(yytext); return IDENTIFIER; }

{WHITESPACE} { /* Ignore whitespace */ }
\n          { line_num++; }

.           {
                error_count++;
                printf("Lexical Error: Unknown character '%s' at line %d\n", yytext, line_num);
            }

%%



void yyerror(const char *s) {
    error_count++;
    fprintf(stderr, "Error at line %d: %s\n", line_num, s);
}

#ifdef LEXER_STANDALONE
YYSTYPE yylval;

int main(int argc, char **argv) {
    if (argc > 1) {
        FILE *file = fopen(argv[1], "r");
        if (!file) {
            perror(argv[1]);
            return 1;
        }
        yyin = file;
    }
    
    int token;
    
    while ((token = yylex())) {
        printf("Token: %d, Text: '%s'\n", token, yytext);
    }
    
    return 0;
}
#endif
