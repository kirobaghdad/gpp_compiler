CC := gcc
BISON := bison
FLEX := flex
CFLAGS := -Wall -Wextra -std=c11 -D_POSIX_C_SOURCE=200809L

TARGET := gpp_compiler
PARSER_SRC := parser/parser.y
PARSER_C := parser/yacc_tab.c
PARSER_H := parser/yacc_tab.h
LEXER_SRC := lexer/lexer.l
LEXER_C := lexer/lex.yy.c
SYMBOL_TABLE_SRC := semantic/symbol_table.c
QUADRUPLES_SRC := quadruples/quadruples.c

.PHONY: all clean run-valid run-parse-errors run-lex-errors run-symbol-table run-symbol-table-errors run-quadruples run-quadruples-control run-syntax-recovery

all: $(TARGET)

$(PARSER_C) $(PARSER_H): $(PARSER_SRC)
	$(BISON) -d $(PARSER_SRC)

$(LEXER_C): $(LEXER_SRC) $(PARSER_H)
	$(FLEX) -o $(LEXER_C) $(LEXER_SRC)

$(TARGET): $(PARSER_C) $(LEXER_C) $(SYMBOL_TABLE_SRC) $(QUADRUPLES_SRC)
	$(CC) $(CFLAGS) -o $@ $(PARSER_C) $(LEXER_C) $(SYMBOL_TABLE_SRC) $(QUADRUPLES_SRC) -lfl

run-valid: $(TARGET)
	./$(TARGET) test/valid.gpp

run-parse-errors: $(TARGET)
	./$(TARGET) test/parsing_test.gpp

run-lex-errors: $(TARGET)
	./$(TARGET) test/lex_err.gpp

run-symbol-table: $(TARGET)
	./$(TARGET) test/symbol_table_scopes.gpp

run-symbol-table-errors: $(TARGET)
	./$(TARGET) test/symbol_table_errors.gpp

run-quadruples: $(TARGET)
	./$(TARGET) test/valid.gpp

run-quadruples-control: $(TARGET)
	./$(TARGET) test/quadruples_control.gpp

run-syntax-recovery: $(TARGET)
	./$(TARGET) test/syntax_recovery.gpp

clean:
	rm -f $(TARGET) parser_test my_lexer.o $(PARSER_C) $(PARSER_H) $(LEXER_C)
