#ifndef VALUES_H
#define VALUES_H

#include "codegen.h" //para tener C3AType

/* struct para symtab.h */
typedef struct {
    C3AType type;
} value_info;

/* funciones auxiliares mínimas */
value_info* create_value(C3AType t);

#endif