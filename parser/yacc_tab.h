#ifndef YACC_TAB_H
#define YACC_TAB_H

typedef union {
    int ival;
    float fval;
    char* str;
} YYSTYPE;

extern YYSTYPE yylval;

enum yytokentype {
    INT_TYPE = 258,
    FLOAT_TYPE,
    DOUBLE_TYPE,
    CHAR_TYPE,
    BOOL_TYPE,
    VOID_TYPE,
    CONST_KW,
    IF,
    ELSE,
    WHILE,
    DO,
    FOR,
    SWITCH,
    CASE,
    DEFAULT,
    BREAK,
    CONTINUE,
    RETURN,
    TRUE_KW,
    FALSE_KW,
    FLOAT_LITERAL,
    INTEGER_LITERAL,
    CHAR_LITERAL,
    STRING_LITERAL,
    PLUS,
    MINUS,
    MULT,
    DIV,
    MOD,
    INC,
    DEC,
    EQ_OP,
    NE_OP,
    LT_OP,
    GT_OP,
    LE_OP,
    GE_OP,
    AND_OP,
    OR_OP,
    NOT_OP,
    ASSIGN,
    ADD_ASSIGN,
    SUB_ASSIGN,
    MUL_ASSIGN,
    DIV_ASSIGN,
    MOD_ASSIGN,
    LPAREN,
    RPAREN,
    LBRACE,
    RBRACE,
    LBRACKET,
    RBRACKET,
    SEMI,
    COMMA,
    COLON,
    IDENTIFIER
};

#endif
