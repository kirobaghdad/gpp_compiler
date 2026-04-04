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

.PHONY: all clean run-valid run-parse-errors run-lex-errors

all: $(TARGET)

$(PARSER_C) $(PARSER_H): $(PARSER_SRC)
	$(BISON) -d $(PARSER_SRC)

$(LEXER_C): $(LEXER_SRC) $(PARSER_H)
	$(FLEX) -o $(LEXER_C) $(LEXER_SRC)

$(TARGET): $(PARSER_C) $(LEXER_C)
	$(CC) $(CFLAGS) -o $@ $(PARSER_C) $(LEXER_C) -lfl

run-valid: $(TARGET)
	./$(TARGET) test/valid.gpp

run-parse-errors: $(TARGET)
	./$(TARGET) test/parsing_test.gpp

run-lex-errors: $(TARGET)
	./$(TARGET) test/lex_err.gpp

clean:
	rm -f $(TARGET) parser_test my_lexer.o $(PARSER_C) $(PARSER_H) $(LEXER_C)
