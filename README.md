# GPP Compiler - Phase I

This repository contains the Phase I submission for the CMP(N)403 compiler project. In this phase, the delivered components are the Flex lexer and the Bison parser for a simplified C++-like language subset.

## Included in Phase I

- Lexical analysis in [lexer/lexer.l](./lexer/lexer.l)
- Syntax analysis in [parser/parser.y](./parser/parser.y)
- Sample input files in [test](./test)
- Submission report in [Phase_I_Report.md](./Phase_I_Report.md)

## Supported Language Features

- Primitive data types: `int`, `float`, `double`, `char`, `bool`, `void`
- Variable and `const` declarations
- Arithmetic, relational, logical, unary, and assignment expressions
- Nested blocks and declarations inside blocks
- `if`, `if-else`, `while`, `do-while`, `for`, and `switch`
- `break`, `continue`, and `return`
- Function definitions, function declarations, default parameters, and function calls
- Array-style indexing and prefix/postfix increment and decrement

## Build

Build from the repository root:

```bash
make
```

This generates `gpp_compiler` using:

- `bison` for the parser
- `flex` for the lexer
- `gcc` for compilation and linking

## Run

```bash
./gpp_compiler test/valid.gpp
```

Useful helper targets:

```bash
make run-valid
make run-parse-errors
make run-lex-errors
make clean
```

## Notes

- Phase I focuses on lexer and parser delivery only.
- Symbol table generation, quadruples, semantic analysis, and extended error recovery are reserved for Phase II.
- The parser accepts function prototypes and declarations directly inside `switch` cases to better match the required language subset.
