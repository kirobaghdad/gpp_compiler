/* A Bison parser, made by GNU Bison 3.8.2.  */

/* Bison interface for Yacc-like parsers in C

   Copyright (C) 1984, 1989-1990, 2000-2015, 2018-2021 Free Software Foundation,
   Inc.

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <https://www.gnu.org/licenses/>.  */

/* As a special exception, you may create a larger work that contains
   part or all of the Bison parser skeleton and distribute that work
   under terms of your choice, so long as that work isn't itself a
   parser generator using the skeleton or a modified version thereof
   as a parser skeleton.  Alternatively, if you modify or redistribute
   the parser skeleton itself, you may (at your option) remove this
   special exception, which will cause the skeleton and the resulting
   Bison output files to be licensed under the GNU General Public
   License without this special exception.

   This special exception was added by the Free Software Foundation in
   version 2.2 of Bison.  */

/* DO NOT RELY ON FEATURES THAT ARE NOT DOCUMENTED in the manual,
   especially those whose name start with YY_ or yy_.  They are
   private implementation details that can be changed or removed.  */

#ifndef YY_YY_PARSER_YACC_TAB_H_INCLUDED
# define YY_YY_PARSER_YACC_TAB_H_INCLUDED
/* Debug traces.  */
#ifndef YYDEBUG
# define YYDEBUG 0
#endif
#if YYDEBUG
extern int yydebug;
#endif

/* Token kinds.  */
#ifndef YYTOKENTYPE
# define YYTOKENTYPE
  enum yytokentype
  {
    YYEMPTY = -2,
    YYEOF = 0,                     /* "end of file"  */
    YYerror = 256,                 /* error  */
    YYUNDEF = 257,                 /* "invalid token"  */
    INT_TYPE = 258,                /* INT_TYPE  */
    FLOAT_TYPE = 259,              /* FLOAT_TYPE  */
    DOUBLE_TYPE = 260,             /* DOUBLE_TYPE  */
    CHAR_TYPE = 261,               /* CHAR_TYPE  */
    BOOL_TYPE = 262,               /* BOOL_TYPE  */
    VOID_TYPE = 263,               /* VOID_TYPE  */
    CONST_KW = 264,                /* CONST_KW  */
    IF = 265,                      /* IF  */
    ELSE = 266,                    /* ELSE  */
    WHILE = 267,                   /* WHILE  */
    DO = 268,                      /* DO  */
    FOR = 269,                     /* FOR  */
    SWITCH = 270,                  /* SWITCH  */
    CASE = 271,                    /* CASE  */
    DEFAULT = 272,                 /* DEFAULT  */
    BREAK = 273,                   /* BREAK  */
    CONTINUE = 274,                /* CONTINUE  */
    RETURN = 275,                  /* RETURN  */
    TRUE_KW = 276,                 /* TRUE_KW  */
    FALSE_KW = 277,                /* FALSE_KW  */
    FLOAT_LITERAL = 278,           /* FLOAT_LITERAL  */
    INTEGER_LITERAL = 279,         /* INTEGER_LITERAL  */
    CHAR_LITERAL = 280,            /* CHAR_LITERAL  */
    STRING_LITERAL = 281,          /* STRING_LITERAL  */
    PLUS = 282,                    /* PLUS  */
    MINUS = 283,                   /* MINUS  */
    MULT = 284,                    /* MULT  */
    DIV = 285,                     /* DIV  */
    MOD = 286,                     /* MOD  */
    INC = 287,                     /* INC  */
    DEC = 288,                     /* DEC  */
    EQ_OP = 289,                   /* EQ_OP  */
    NE_OP = 290,                   /* NE_OP  */
    LT_OP = 291,                   /* LT_OP  */
    GT_OP = 292,                   /* GT_OP  */
    LE_OP = 293,                   /* LE_OP  */
    GE_OP = 294,                   /* GE_OP  */
    AND_OP = 295,                  /* AND_OP  */
    OR_OP = 296,                   /* OR_OP  */
    NOT_OP = 297,                  /* NOT_OP  */
    ASSIGN = 298,                  /* ASSIGN  */
    ADD_ASSIGN = 299,              /* ADD_ASSIGN  */
    SUB_ASSIGN = 300,              /* SUB_ASSIGN  */
    MUL_ASSIGN = 301,              /* MUL_ASSIGN  */
    DIV_ASSIGN = 302,              /* DIV_ASSIGN  */
    MOD_ASSIGN = 303,              /* MOD_ASSIGN  */
    LPAREN = 304,                  /* LPAREN  */
    RPAREN = 305,                  /* RPAREN  */
    LBRACE = 306,                  /* LBRACE  */
    RBRACE = 307,                  /* RBRACE  */
    LBRACKET = 308,                /* LBRACKET  */
    RBRACKET = 309,                /* RBRACKET  */
    SEMI = 310,                    /* SEMI  */
    COMMA = 311,                   /* COMMA  */
    COLON = 312,                   /* COLON  */
    IDENTIFIER = 313,              /* IDENTIFIER  */
    UMINUS = 314,                  /* UMINUS  */
    LOWER_THAN_ELSE = 315          /* LOWER_THAN_ELSE  */
  };
  typedef enum yytokentype yytoken_kind_t;
#endif

/* Value type.  */
#if ! defined YYSTYPE && ! defined YYSTYPE_IS_DECLARED
union YYSTYPE
{
#line 17 "parser/parser.y"

    int ival;
    float fval;
    char* str;

#line 130 "parser/yacc_tab.h"

};
typedef union YYSTYPE YYSTYPE;
# define YYSTYPE_IS_TRIVIAL 1
# define YYSTYPE_IS_DECLARED 1
#endif


extern YYSTYPE yylval;


int yyparse (void);


#endif /* !YY_YY_PARSER_YACC_TAB_H_INCLUDED  */
