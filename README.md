# Práctica 2: Compilador de Lenguaje Sencillo a Código de Tres Direcciones (C3A)

## Descripción del Proyecto

Este proyecto consiste en la implementación de un compilador (Frontend y Backend) para un lenguaje imperativo sencillo. El objetivo principal es realizar el análisis léxico, sintáctico y semántico del código fuente para generar **Código de Tres Direcciones (C3A)** conforme a las especificaciones estrictas del enunciado.

El compilador soporta tipos de datos básicos (`int`, `float`), estructuras de control iterativas (`repeat`), manipulación de arrays unidimensionales y operaciones aritméticas con conversión implícita de tipos.

## Estructura de Directorios

* **`src/`**: Contiene el código fuente del compilador.
* `scanner.l`: Especificación del analizador léxico (Flex).
* `parser.y`: Gramática y generación de código (Bison).
* `codegen.c/h`: Módulo del Backend encargado de la gestión de temporales y emisión de instrucciones.
* `symtab.c/h`: Tabla de símbolos para la gestión de variables y tipos.
* `values.c/h`: Estructuras auxiliares para el manejo de tipos.
* `main.c`: Punto de entrada del programa.


* **`test/in/`**: Ficheros de prueba con código fuente (`.txt`).
* **`test/out/`**: Resultados generados tras la ejecución (`.out`).

## Compilación y Ejecución

### Requisitos

* GCC
* Flex
* Bison
* Make

### Instrucciones

Para compilar el proyecto, navega a la carpeta `src/` y ejecuta:

```bash
make
```

Esto generará el ejecutable `calculadora`.

Para limpiar los archivos generados:

```bash
make clean
```

### Ejecución de Tests

Para ejecutar el compilador sobre un archivo específico:

```bash
./calculadora ../test/in/nombre_archivo.txt

```

Para ejecutar la **batería completa de pruebas** automática:

```bash
make test
```

Los resultados se guardarán en la carpeta `test/out/`.


## Decisiones de Diseño y Funcionalidades

### 1. Generación de Código C3A

Se ha implementado un módulo de *Backend* (`codegen.c`) que almacena las instrucciones en una lista interna antes de imprimirlas. Esto permite:

* Gestionar correctamente el orden de las instrucciones.
* Formatear salidas especiales como `IF ... GOTO` o `HALT` al final del programa.
* Asegurar que la salida cumple estrictamente con el formato del PDF `C3A.pdf`.

### 2. Estructura de Control `REPEAT`

El bucle `repeat n do ... done` se ha implementado mediante un **contador interno oculto**.

* Se genera una variable temporal (ej. `$t06`) inicializada a 0.
* Se calcula el límite de iteraciones en otra variable temporal.
* Al final del bloque, se incrementa el contador y se emite un salto condicional inverso: `IF contador LTI limite GOTO inicio`.
* Esto evita la necesidad de *backpatching* complejo, ya que la etiqueta de inicio es conocida al momento de generar el salto.

### 3. Arrays Unidimensionales

Se soporta la declaración (`int a[10]`) y el acceso mediante índices (`a[i]`).

* **Cálculo de Offset:** Dado que el C3A trabaja con direcciones de memoria, el compilador calcula el desplazamiento multiplicando el índice por el tamaño del tipo de dato (4 bytes para `int` y `float`).
* Instrucción generada: `$tXX := indice MULI 4`.


* **Acceso Desplazado:** Se generan las instrucciones específicas de asignación y consulta desplazada:
* Escritura: `a[$tXX] := valor`
* Lectura: `destino := a[$tXX]`



### 4. Sistema de Tipos y Conversiones

El compilador realiza comprobaciones semánticas estrictas pero permite flexibilidad mediante **Casting Implícito**:

* Si se opera un `int` con un `float`, el compilador inyecta automáticamente la instrucción `I2F` (Integer to Float) para promover el entero.
* El resultado de operaciones mixtas es siempre `float`.
* Se soportan operadores unarios (`-a` genera `CHSI` o `CHSF`) y módulo (`%` genera `MODI`, exclusivo para enteros).


## Limitaciones y Comentarios

### 1. Operador Potencia (`**`)

Aunque la gramática reconoce el operador de potencia para respetar la precedencia correcta, **no se genera código expandido** (como un bucle de multiplicaciones) ni existe una instrucción `POW` en el estándar C3A proporcionado.

* **Comportamiento:** El compilador emite un aviso por *stderr* (`Warning: Power (**) operator used but not fully implemented`) y realiza una asignación simple del primer operando para no detener la ejecución.

### 2. Ámbito de Variables (Scope)

Siguiendo las especificaciones simplificadas de la práctica, se asume un **único ámbito global**. No se permite la redeclaración de variables con el mismo nombre.

### 3. Optimizaciones

El compilador genera código para todas las expresiones, incluidas aquellas formadas únicamente por literales (ej. `2 + 3` genera una instrucción `ADDI`). No se realiza *Constant Folding* (evaluación en tiempo de compilación), priorizando la correcta generación de instrucciones C3A sobre la optimización.

### 4. Instrucción HALT

El programa siempre finaliza inyectando la instrucción `HALT` en la última línea, asegurando la terminación correcta del flujo de ejecución simulado.



## Ejemplo de Salida (Factorial)

Entrada:

```text
repeat n - 1 do
    fact := fact * i
    i := i + 1
done

```

Salida Generada (C3A):

```text
11: $t05 := n SUBI 1        ; Cálculo del límite
12: $t06 := 0               ; Inicialización contador oculto
13: $t07 := fact MULI i     ; Cuerpo del bucle
14: fact := $t07
15: $t08 := i ADDI 1
16: i := $t08
17: $t06 := $t06 ADDI 1     ; Incremento contador oculto
18: IF $t06 LTI $t05 GOTO 13 ; Salto condicional

```