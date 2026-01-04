%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "codegen.h"
#include "symtab.h"
#include "values.h"

extern int yylex();
extern int yylineno;
extern char *yytext;
extern FILE *yyin;
void yyerror(const char *s);

/* --- GESTIÓN DE LA TABLA DE SÍMBOLOS --- */
void install_var(char *name, C3AType type) {
    value_info *v;
    if (sym_lookup(name, &v) == SYMTAB_OK) {
        fprintf(stderr, "Error semántico: '%s' ya existe.\n", name);
        return;
    }
    v = create_value(type);
    sym_enter(name, &v);
}

C3AType get_var_type(char *name) {
    value_info *v;
    if (sym_lookup(name, &v) == SYMTAB_OK) return v->type;
    return T_ERROR;
}

/* --- HELPER PARA OPERACIONES BINARIAS --- */
C3A_Info gen_binary_op(char *op_base, C3A_Info a, C3A_Info b) {
    C3A_Info res;
    res.type = T_ERROR;
    res.addr = NULL;

    /* 1. Comprobar tipos */
    if (a.type == T_ERROR || b.type == T_ERROR) return res;

    /* MODULO: solo enteros */
    if (strcmp(op_base, "MOD") == 0) {
        if (a.type == T_FLOAT || b.type == T_FLOAT) {
            fprintf(stderr, "Error semántico: Módulo solo acepta enteros.\n");
            return res;
        }
        res.type = T_INT;
        res.addr = cg_new_temp();
        cg_emit("MODI", a.addr, b.addr, res.addr);
        return res;
    }

    /* RESTO: actualización automática a Float si es necesario */
    char *addr_a = a.addr;
    char *addr_b = b.addr;
    C3AType final_type = T_INT;

    /* Si alguno es float, el resultado es float */
    if (a.type == T_FLOAT || b.type == T_FLOAT) {
        final_type = T_FLOAT;
        
        /* si A es int, hay que convertirlo */
        if (a.type == T_INT) {
            char *temp = cg_new_temp();
            cg_emit("I2F", a.addr, NULL, temp);
            addr_a = temp;
        }
        /* si B es int, hay que convertirlo */
        if (b.type == T_INT) {
            char *temp = cg_new_temp();
            cg_emit("I2F", b.addr, NULL, temp);
            addr_b = temp;
        }
    }

    /* 3. Generar la instrucción */
    res.type = final_type;
    res.addr = cg_new_temp();
    
    /* type_to_opcode convierte "ADD" en "ADDI" o "ADDF" */
    cg_emit(type_to_opcode(op_base, final_type), addr_a, addr_b, res.addr);
    return res;
}

/* --- HELPER PARA UNARIOS --- */
C3A_Info gen_unary_op(char *op_type, C3A_Info a) {
    C3A_Info res;
    res.type = T_ERROR;
    res.addr = NULL;
    if (a.type == T_ERROR) return res;

    res.type = a.type;
    res.addr = cg_new_temp();
    
    /* CHSI o CHSF */
    char *opcode = (a.type == T_INT) ? "CHSI" : "CHSF";
    cg_emit(opcode, a.addr, NULL, res.addr);
    return res;
}
%}

%union {
    struct {
        char *lexema;
        int line;
    } ident;
    char *literal; 
    C3A_Info info;
}

%token ASSIGN PLUS MINUS MULT DIV MOD POW
%token AND OR NOT EQ NEQ GT GE LT LE
%token LPAREN RPAREN LBRACE RBRACE SEMICOLON COMMA DOT EOL
%token KW_INT KW_FLOAT KW_STRING KW_BOOL STRUCT REPEAT DO DONE
%token KW_SIN KW_COS KW_TAN KW_LEN KW_SUBSTR

%token <literal> LIT_INT LIT_FLOAT LIT_BOOL LIT_STRING
%token <ident> ID 

%type <info> expressio term potencia factor repeat_header
%type <ident> variable

%start programa

%%

programa : { cg_init(); } lista_sentencias { 
                cg_emit("HALT", NULL, NULL, NULL);
                cg_print_all(stdout); 
           }
         ;

lista_sentencias : /* vacio */
                 | lista_sentencias sentencia
                 | lista_sentencias EOL 
                 ;

sentencia : declaracion EOL
          | asignacion EOL
          | expressio EOL { 
               /* Expresión suelta: asumir que se quiere imprimir (PUTI/PUTF) */
               cg_emit("PARAM", $1.addr, NULL, NULL);
               if ($1.type == T_FLOAT) cg_emit("CALL", "PUTF", "1", NULL);
               else cg_emit("CALL", "PUTI", "1", NULL);
            }
          | repeat_block EOL
          | error EOL { yyerrok; }
          ;

declaracion : KW_INT variable   { install_var($2.lexema, T_INT); }
            | KW_FLOAT variable { install_var($2.lexema, T_FLOAT); }
            | KW_INT variable ASSIGN expressio {
                install_var($2.lexema, T_INT);
                cg_emit(":=", $4.addr, NULL, $2.lexema);
            }
            | KW_FLOAT variable ASSIGN expressio {
                install_var($2.lexema, T_FLOAT);
                char *src = $4.addr;
                if ($4.type == T_INT) {
                    src = cg_new_temp();
                    cg_emit("I2F", $4.addr, NULL, src);
                }
                cg_emit(":=", src, NULL, $2.lexema);
            }
            ;

asignacion : variable ASSIGN expressio {
                C3AType varType = get_var_type($1.lexema);
                if (varType == T_ERROR) {
                    fprintf(stderr, "Error: Variable '%s' no declarada.\n", $1.lexema);
                } else {
                    char *src = $3.addr;
                    /* conversión implícita en asignación */
                    if (varType == T_FLOAT && $3.type == T_INT) {
                        src = cg_new_temp();
                        cg_emit("I2F", $3.addr, NULL, src);
                    }
                    cg_emit(":=", src, NULL, $1.lexema);
                }
             }
           ;

/* --- ESTRUCTURA REPEAT --- */
/* "repeat n-1 do" */
repeat_block : repeat_header lista_sentencias DONE {
    /* al encontrar DONE, cerrar el bucle */
    /* 1. Incrementar contador: $cnt := $cnt ADDI 1 */
    cg_emit("ADDI", $1.ctr_var, "1", $1.ctr_var);
    
    /* 2. Salto condicional: IF $cnt LTI limit GOTO start_label */
    char label_str[16];
    sprintf(label_str, "%d", $1.label_idx);
    
    /* IF contador < limite GOTO inicio */
    cg_emit("IF LTI", $1.ctr_var, $1.addr, label_str);
}

repeat_header : REPEAT expressio DO {
    /* 1. Evaluar límite (ya está en $2.addr) */
    /* 2. Crear contador a 0 */
    char *ctr = cg_new_temp();
    cg_emit(":=", "0", NULL, ctr);
    
    /* 3. Guardar etiqueta de inicio (siguiente instrucción) */
    $$.label_idx = cg_next_quad();
    $$.ctr_var = ctr;        /* guardar nombre contador */
    $$.addr = $2.addr;       /* guardar nombre límite */
}

/* --- PRECEDENCIA --- */

/* Nivel 1: Suma, Resta y Unarios */
expressio : term
          | expressio PLUS term  { $$ = gen_binary_op("ADD", $1, $3); }
          | expressio MINUS term { $$ = gen_binary_op("SUB", $1, $3); }
          | MINUS term           { $$ = gen_unary_op("MINUS", $2); } /* Unario */
          | PLUS term            { $$ = $2; }
          ;

/* Nivel 2: Multipli, Div y Mod */
term : potencia
     | term MULT potencia { $$ = gen_binary_op("MUL", $1, $3); }
     | term DIV potencia  { $$ = gen_binary_op("DIV", $1, $3); }
     | term MOD potencia  { $$ = gen_binary_op("MOD", $1, $3); }
     ;

/* Nivel 3: Potencia */
potencia : factor
         | factor POW potencia { 
             /* PENDENT: Implementar bucle de potència */
             fprintf(stderr, "Warning: Power operator not implemented yet (requires loop)\n");
             $$ = $1; /* Dummy per ara */
         }
         ;

/* Nivel 4: átomos */
factor : LIT_INT { 
            $$.addr = strdup($1);
            $$.type = T_INT; 
         }
       | LIT_FLOAT { 
            $$.addr = strdup($1); 
            $$.type = T_FLOAT;
         }
       | variable {
            $$.addr = strdup($1.lexema);
            $$.type = get_var_type($1.lexema);
            if ($$.type == T_ERROR) fprintf(stderr, "Error: Variable %s desconocida\n", $1.lexema);
         }
       | LPAREN expressio RPAREN { $$ = $2; }
       ;

variable : ID ;

%%

void yyerror(const char *s) {
    fprintf(stderr, "Error sintáctico en línea %d: %s\n", yylineno, s);
}