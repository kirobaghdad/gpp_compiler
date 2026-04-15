# GPP Compiler

This repository contains the complete compiler project, featuring a simplified C++ compiler fully implemented with Lex/Yacc, accompanied by an interactive Web Graphical User Interface.

## Project Features

- **Lexer & Parser:** Full lexical and syntax analysis using Flex and Bison.
- **Symbol Table:** Dynamically scoping variable tracking.
- **Quadruples:** Integrated Intermediate Representation emitted directly from AST traversal.
- **Semantic Analyzer:** Detects initialization failures, scope errors, return types, and mutability constraints.
- **Syntax Error Recovery:** Graceful parser continuation upon unexpected symbols.

## Supported Language Features

- Primitive data types: `int`, `float`, `double`, `char`, `bool`, `void`
- Variable, `const` declarations, nested block scoping
- Arithmetic, relational, logical, unary, and assignment expressions
- Control flow: `if`, `if-else`, `while`, `do-while`, `for`, `switch`, `break`, `continue`, `return`
- Function definitions with default properties and parameters.

## CLI Build & Run

Build the core `gpp_compiler` executable natively from the root:

```bash
make
./gpp_compiler test/valid.gpp
```

## Interactive Web GUI 🚀

The project also includes an aesthetic GUI wrapper allowing you to write code in a live editor and quickly visualize Quadruples, Symbol Tables, and generated Errors side-by-side.

1. Ensure [Node.js](https://nodejs.org) is installed.
2. Initialize and run the GUI backend:

```bash
cd gui
npm install
node server.js
```

3. Open your browser and navigate to `http://localhost:3000`
