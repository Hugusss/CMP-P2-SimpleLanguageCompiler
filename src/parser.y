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
void install_var(char *name, C3AType type, int is_array, int length) {
    value_info *v;
    /* pasa &v porque sym_lookup espera value_info** */
    if (sym_lookup(name, &v) == SYMTAB_OK) {
        fprintf(stderr, "Error semántico: '%s' ya existe.\n", name);
        return;
    }
    v = create_value(type, is_array, length);
    sym_enter(name, &v);
}

C3AType get_var_type(char *name) {
    value_info *v;
    if (sym_lookup(name, &v) == SYMTAB_OK) return v->type;
    return T_ERROR;
}

int is_var_array(char *name) {
    value_info *v;
    if (sym_lookup(name, &v) == SYMTAB_OK) return v->is_array;
    return 0;
}

/* --- HELPER PARA OPERACIONES BINARIAS --- */
C3A_Info gen_binary_op(char *op_base, C3A_Info a, C3A_Info b) {
    C3A_Info res;
    res.type = T_ERROR;
    res.addr = NULL;
    res.ctr_var = NULL;

    /* 1. Comprobar tipos */
    if (a.type == T_ERROR || b.type == T_ERROR) return res;

    /* CASO ESPECIAL: MÓDULO (Solo enteros) */
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

    /* RESTO: mejora automática a Float si es necesario */
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
C3A_Info gen_unary_op(C3A_Info a) {
    C3A_Info res;
    res.type = T_ERROR;
    res.addr = NULL;
    res.ctr_var = NULL;

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
%token LBRACKET RBRACKET
%token KW_INT KW_FLOAT KW_STRING KW_BOOL STRUCT REPEAT DO DONE
%token KW_SIN KW_COS KW_TAN KW_LEN KW_SUBSTR

%token <literal> LIT_INT LIT_FLOAT LIT_BOOL LIT_STRING
%token <ident> ID 

%type <info> expressio term potencia factor repeat_header
%type <info> variable /* variable ahora devuelve info completa (addr + offset) */

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
               /* expressions sin asignacion se imprimen */
               cg_emit("PARAM", $1.addr, NULL, NULL);
               if ($1.type == T_FLOAT) cg_emit("CALL", "PUTF", "1", NULL);
               else cg_emit("CALL", "PUTI", "1", NULL);
            }
          | repeat_block EOL
          | error EOL { yyerrok; }
          ;

/* --- DECLARACIONES --- */
declaracion : KW_INT ID   { install_var($2.lexema, T_INT, 0, 0); }
            | KW_FLOAT ID { install_var($2.lexema, T_FLOAT, 0, 0); }
            
            /* ARRAY DECLARATION: int a[25]*/
            | KW_INT ID LBRACKET LIT_INT RBRACKET {
                install_var($2.lexema, T_INT, 1, atoi($4));
            }
            | KW_FLOAT ID LBRACKET LIT_INT RBRACKET {
                install_var($2.lexema, T_FLOAT, 1, atoi($4));
            }

            /* Inicializaciones (Syntactic sugar opcional) */
            | KW_INT ID ASSIGN expressio {
                install_var($2.lexema, T_INT, 0, 0);
                cg_emit(":=", $4.addr, NULL, $2.lexema);
            }
            | KW_FLOAT ID ASSIGN expressio {
                install_var($2.lexema, T_FLOAT, 0, 0);
                char *src = $4.addr;
                if ($4.type == T_INT) {
                    src = cg_new_temp();
                    cg_emit("I2F", $4.addr, NULL, src);
                }
                cg_emit(":=", src, NULL, $2.lexema);
            }
            ;

/* --- ASIGNACIONES --- */
asignacion : variable ASSIGN expressio {
                /* variable trae: addr="nombre", ctr_var="offset" (si es array) o NULL */
                
                C3AType varType = $1.type;
                if (varType == T_ERROR) {
                    fprintf(stderr, "Error: Variable '%s' desconocida o inválida.\n", $1.addr);
                } else {
                    char *src = $3.addr;
                    /* Conversión implícita */
                    if (varType == T_FLOAT && $3.type == T_INT) {
                        src = cg_new_temp();
                        cg_emit("I2F", $3.addr, NULL, src);
                    }
                    
                    if ($1.ctr_var == NULL) {
                        /* Asignación Simple: x := y */
                        cg_emit(":=", src, NULL, $1.addr);
                    } else {
                        /* Asignación Desplazada: a[offset] := y*/
                        /* se usa opcode interno "arr_set" que codegen traducirá */
                        cg_emit("arr_set", $1.addr, $1.ctr_var, src);
                    }
                }
             }
           ;

/* --- ESTRUCTURA REPEAT --- */
repeat_block : repeat_header lista_sentencias DONE {
    /* 1. Incrementar contador: cnt := cnt + 1 */
    cg_emit("ADDI", $1.ctr_var, "1", $1.ctr_var);
    
    /* 2. Salto: IF cnt < limite GOTO inicio */
    char label_str[16];
    sprintf(label_str, "%d", $1.label_idx);
    
    /* IF contador < limite GOTO inicio */
    cg_emit("IF LTI", $1.ctr_var, $1.addr, label_str);
}

repeat_header : REPEAT expressio DO {
    /* Contador a 0 */
    char *ctr = cg_new_temp();
    cg_emit(":=", "0", NULL, ctr);
    
    /* 3. Guardar etiqueta de inicio (siguiente instrucción) */
    $$.label_idx = cg_next_quad();
    $$.ctr_var = ctr;        /* guardar nombre contador */
    $$.addr = $2.addr;       /* guardar nombre límite */
}

/* --- EXPRESIONES ARITMÉTICAS --- */

/* Nivel 1: Suma, Resta y UNARIOS */
expressio : term
          | expressio PLUS term  { $$ = gen_binary_op("ADD", $1, $3); }
          | expressio MINUS term { $$ = gen_binary_op("SUB", $1, $3); }
          | MINUS term           { $$ = gen_unary_op($2); } /* Unario */
          | PLUS term            { $$ = $2; }
          ;

/* Nivel 2: Producto, División y Módulo */
term : potencia
     | term MULT potencia { $$ = gen_binary_op("MUL", $1, $3); }
     | term DIV potencia  { $$ = gen_binary_op("DIV", $1, $3); }
     | term MOD potencia  { $$ = gen_binary_op("MOD", $1, $3); }
     ;

/* Nivel 3: Potencia */
potencia : factor
         | factor POW potencia { 
             fprintf(stderr, "Warning: Power (**) operator used but not fully implemented.\n");
             $$ = $1; 
         }
         ;

/* Nivel 4: Átomos */
factor : LIT_INT { 
            $$.addr = strdup($1);
            $$.type = T_INT; 
            $$.ctr_var = NULL;
         }
       | LIT_FLOAT { 
            $$.addr = strdup($1); 
            $$.type = T_FLOAT;
            $$.ctr_var = NULL;
         }
       | variable {
            /* variable ya ha calculado el offset si es array */
            if ($1.ctr_var == NULL) {
                /* Acceso simple: x */
                $$.addr = $1.addr;
                $$.type = $1.type;
                $$.ctr_var = NULL;
            } else {
                /* Acceso Array: a[offset] -> Consulta desplazada */
                char *temp = cg_new_temp();
                cg_emit("arr_get", $1.addr, $1.ctr_var, temp);
                
                $$.addr = temp;
                $$.type = $1.type;
                $$.ctr_var = NULL; /* El resultado ya es un valor escalar en temp */
            }
         }
       | LPAREN expressio RPAREN { $$ = $2; }
       ;

/* Regla variable: Maneja identificadores simples y arrays */
variable : ID {
             $$.addr = strdup($1.lexema);
             $$.type = get_var_type($1.lexema);
             $$.ctr_var = NULL; /* NULL indica escalar */
          }
          | ID LBRACKET expressio RBRACKET {
             /* Consulta de Array: a[i] */
             
             /* 1. Verificar si es array */
             if (!is_var_array($1.lexema)) {
                 fprintf(stderr, "Error: '%s' no es un array.\n", $1.lexema);
             }
             
             /* 2. Índice debe ser entero */
             if ($3.type != T_INT) {
                 fprintf(stderr, "Error: Índice de array debe ser entero.\n");
             }
             
             /* 3. Calcular Offset: index * 4 bytes (int/float) */
             char *offset = cg_new_temp();
             cg_emit("MULI", $3.addr, "4", offset);
             
             $$.addr = strdup($1.lexema);
             $$.type = get_var_type($1.lexema);
             $$.ctr_var = offset; /* se guarda EL OFFSET EN ESTE CAMPO */
          }
          ;

%%

void yyerror(const char *s) {
    fprintf(stderr, "Error sintáctico en línea %d: %s\n", yylineno, s);
}