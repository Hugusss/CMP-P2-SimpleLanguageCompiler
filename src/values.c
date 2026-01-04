#include <stdlib.h>
#include "values.h"

value_info* create_value(C3AType t) {
    value_info *v = (value_info*)malloc(sizeof(value_info));
    v->type = t;
    return v;
}