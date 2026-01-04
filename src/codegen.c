#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "codegen.h"

#define MAX_QUADS 1000

static int temp_counter = 1;
static Quad code_memory[MAX_QUADS];
static int next_quad = 1; /* empezar por línea 1 */

void cg_init() {
    temp_counter = 1;
    next_quad = 1;
}

int cg_next_quad() {
    return next_quad;
}

char* cg_new_temp() {
    char buffer[16];
    sprintf(buffer, "$t%02d", temp_counter++);
    return strdup(buffer);
}

void cg_emit(char *op, char *arg1, char *arg2, char *res) {
    if (next_quad >= MAX_QUADS) {
        fprintf(stderr, "Error: Límite de instrucciones excedido.\n");
        exit(1);
    }
    
    /* guardar copia de los strings por integridad */
    code_memory[next_quad].op = op ? strdup(op) : NULL;
    code_memory[next_quad].arg1 = arg1 ? strdup(arg1) : NULL;
    code_memory[next_quad].arg2 = arg2 ? strdup(arg2) : NULL;
    code_memory[next_quad].res = res ? strdup(res) : NULL;
    
    next_quad++;
}

void cg_print_all(FILE *out) {
    for (int i = 1; i < next_quad; i++) {
        Quad q = code_memory[i];
        fprintf(out, "%d: ", i);
        
        /* PRIORIDAD: mirar IF/HALT antes que operaciones genéricas */ 
        if (q.op && strncmp(q.op, "IF", 2) == 0) {
            /* IF t1 LTI t2 GOTO 10 */
            fprintf(out, "%s %s %s GOTO %s\n", q.op, q.arg1, q.arg2, q.res);
        }
        else if (q.op && strcmp(q.op, "HALT") == 0) {
            fprintf(out, "HALT\n");
        }
        else if (q.op && strcmp(q.op, "GOTO") == 0) {
            fprintf(out, "GOTO %s\n", q.res);
        }
        /* CASO: CALL/PARAM */
        else if (q.op && strcmp(q.op, "PARAM") == 0) {
            fprintf(out, "PARAM %s\n", q.arg1);
        }
        else if (q.op && strcmp(q.op, "CALL") == 0) {
            fprintf(out, "CALL %s, %s\n", q.arg1, q.arg2);
        }
        /* CASO: Asignación simple (x := y) */
        else if (q.op && strcmp(q.op, ":=") == 0) {
            fprintf(out, "%s := %s\n", q.res, q.arg1);
        }
        /* CASO: Operación binaria */
        else if (q.arg1 && q.arg2 && q.res) {
            /* binaria: res := arg1 op arg2 */
            fprintf(out, "%s := %s %s %s\n", q.res, q.arg1, q.op, q.arg2);
        }
        /* CASO: Unario*/
        else if (q.arg1 && q.res) {
            /* unaria: res := op arg1 (ej: I2F, CHSI) */
            fprintf(out, "%s := %s %s\n", q.res, q.op, q.arg1);
        }
        else {
            /* Fallback */
            fprintf(out, "%s %s %s %s\n", q.op, q.arg1 ? q.arg1 : "", q.arg2 ? q.arg2 : "", q.res ? q.res : "");
        }
    }
}

char* type_to_opcode(char *base_op, C3AType t) {
    static char buffer[16];
    char suffix = (t == T_FLOAT) ? 'F' : 'I';
    sprintf(buffer, "%s%c", base_op, suffix);
    return strdup(buffer);
}