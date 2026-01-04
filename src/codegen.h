#ifndef CODEGEN_H
#define CODEGEN_H

#include <stdio.h>

typedef enum {
    T_INT,
    T_FLOAT,
    T_BOOL,
    T_ERROR
} C3AType;

/* Estructura para subir info por el parser ($$) */
typedef struct {
    char *addr;     /* Dirección: "x", "$t1", "5" */
    C3AType type;   /* Tipo para chequeo: T_INT... */
    int label_idx;  /* Para bucles: índice de la instrucción de inicio */
    char *ctr_var;  /* Para bucles: nombre de la variable contador oculta */
} C3A_Info;

/* Estructura de una instrucción C3A */
typedef struct {
    char *op;       /* Operación: ADDI, MULF, GOTO... */
    char *arg1;     /* Operando 1 */
    char *arg2;     /* Operando 2 */
    char *res;      /* Resultado o destino */
} Quad;

/* Funciones */
void cg_init();
char* cg_new_temp();
int cg_next_quad(); /* devuelve el número de la siguiente instrucción (para saltos) */

/* Emitir instrucciones a la lista interna */
void cg_emit(char *op, char *arg1, char *arg2, char *res);

/* Volcar todo a disco/pantalla al final */
void cg_print_all(FILE *out);

/* Helper de tipos */
char* type_to_opcode(char *base_op, C3AType t);

#endif