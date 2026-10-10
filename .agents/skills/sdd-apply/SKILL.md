---
name: sdd-apply
description: Implementa todas las tareas pendientes de una spec SDD en docs/sdd/<feature>/, respetando orden y dependencias, ejecutando las comprobaciones técnicas disponibles y sin desviarse de la spec. MANUAL-ONLY: úsala SOLO cuando el usuario nombre explícitamente `sdd-apply` (o `$sdd-apply`). No la actives sola ante peticiones genéricas de implementar una feature; para eso usa feature-implementer.
---

# SDD Apply

Esta skill ejecuta una spec ya aprobada. Su objetivo es implementar **todas** las tareas
pendientes de `tasks.md` en una sola pasada, respetando la spec, y terminar pidiendo la
validación funcional del usuario.

Trabaja con el **harness como directorio de trabajo** (`.harness/`) para la spec y el
estado; el **código de producto** está un nivel por encima (`..`).

## Rol y límites

- Sí: leer los tres archivos de la spec, implementar las tareas, ejecutar comprobaciones y marcar tareas completadas.
- No: inventar requisitos, decisiones técnicas ni trabajo adicional.
- No: desviarse de `spec.md` ni de `design.md` sin proponer antes una enmienda y esperar aprobación.
- No: pedir validación al usuario tarea por tarea; la validación funcional es una sola al final.
- No: marcar `[x]` sin haber superado las comprobaciones técnicas disponibles.
- No: crear commits. El commit/PR del producto lo hace el orquestador (`docs/git-workflow.md`).

## Cuándo activarse

Activa esta skill ante frases como:

- "Implementa la feature X."
- "Aplica la spec de..."
- "Implementa todas las tareas de..."
- "Ejecuta sdd-apply para..."

## Entradas a leer primero

1. `docs/sdd/<feature>/spec.md`
2. `docs/sdd/<feature>/design.md`
3. `docs/sdd/<feature>/tasks.md`
4. `AGENTS.md`, `CONSTRAINTS.md`, `PROGRESS.md` y `feature_list.json` como reglas y estado del repositorio.
5. El código real que vayan a tocar las tareas, para respetar patrones existentes.

## Procedimiento

1. **Localizar `docs/sdd/<feature>/`.** Si el usuario no indica la feature, pide que la concrete. No adivines.
2. **Comprobar que existan los tres archivos** (`spec.md`, `design.md`, `tasks.md`).
3. **Si falta algún archivo**, detente y sugiere usar `sdd-propose`. No improvises el contenido que falta.
4. **Leer completamente los tres archivos.** No implementes con una lectura parcial.
5. **Validar la verificabilidad de los requisitos.** Comprueba que cada requisito de `spec.md` tenga al menos un escenario `DADO/CUANDO/ENTONCES`. Si alguno no lo tiene, detente y pide su reformulación.
6. **Comprobar que cada tarea esté vinculada a uno o varios requisitos.** Si una tarea no referencia ningún requisito, detente y pide corregir `tasks.md`.
7. **Revisar las reglas y patrones reales del repositorio.** Sigue el estilo y las librerías existentes; no introduzcas dependencias nuevas que `design.md` no autorice. Respeta las **MUST** de `CONSTRAINTS.md`.
8. **Resumir tu comprensión y esperar confirmación.** Presenta: objetivo de la feature, requisitos, decisiones técnicas, tareas pendientes y comprobaciones previstas. **CHECKPOINT:** espera la confirmación explícita del usuario antes de modificar código.
9. **Implementar todas las tareas pendientes en una única ejecución**, en el orden de `tasks.md` y respetando las dependencias. No pares a pedir validación intermedia.
10. **No inventar requisitos, decisiones ni trabajo extra.** Si algo no está en la spec, no lo hagas.
11. **Gestionar conflictos con la realidad del código.** Si la spec contradice el código, **detente**, explica el conflicto, propone una enmienda concreta a `spec.md` o `design.md` y espera aprobación antes de continuar. **CHECKPOINT.**
12. **Ejecutar las comprobaciones técnicas disponibles**: tests, compilación, lint u otras del repositorio. Registra los comandos y sus resultados.
13. **Marcar como `[x]`** en `tasks.md` solo las tareas implementadas que hayan superado sus comprobaciones.
14. **No marques como completadas** tareas fallidas, incompletas o no verificables; déjalas en `[ ]` y explícalo.
15. **Presentar el resultado completo**: resumen de la implementación, tareas completadas y pendientes, diff de los cambios, pruebas y comprobaciones ejecutadas, resultados obtenidos y limitaciones o validaciones no ejecutadas.
16. **Solicitar la validación funcional final del usuario.** **CHECKPOINT:** no des la feature por terminada ni la archives; `sdd-archive` requiere esa confirmación.

## Reglas sobre el marcado de tareas

- Una tarea solo es `[x]` cuando está implementada **y** ha superado las comprobaciones disponibles.
- Marcar `[x]` no sustituye la validación funcional del usuario.
- Si una comprobación no se pudo ejecutar, dilo explícitamente en lugar de asumir que pasa.

## Por qué de las reglas clave

- **La spec es la fuente de verdad.** Implementar de memoria o "mejorando" la spec rompe el contrato que el usuario aprobó.
- **Confirmación inicial.** Un resumen previo detecta malentendidos antes de gastar esfuerzo en código equivocado.
- **Enmienda ante conflictos.** Cambiar el alcance en silencio hace que la spec y el código diverjan sin control.
- **Una sola validación final.** Pedir validación tarea por tarea fragmenta el trabajo y agota al usuario; la spec se valida como un todo.

## Errores comunes

1. **Implementar antes de la confirmación inicial.** Antipatrón: empezar a escribir código nada más leer la spec. Corrección: presentar el resumen del paso 8 y esperar el "sí".
2. **Desviarse de la spec sin enmienda.** Antipatrón: cambiar el diseño sobre la marcha porque "quedaba mejor". Corrección: detenerse, proponer la enmienda y esperar aprobación.
3. **Inventar decisiones técnicas.** Antipatrón: añadir una librería que no está en `design.md`. Corrección: no usarla; preguntar si se necesita.
4. **Ignorar el orden o las dependencias de `tasks.md`.** Antipatrón: hacer la tarea 5 antes de la 2. Corrección: respetar la numeración y las dependencias.
5. **Marcar tareas como completadas sin comprobarlas.** Antipatrón: poner `[x]` sin ejecutar tests ni compilar. Corrección: ejecutar las comprobaciones y dejar en `[ ]` lo que falle o no se pueda verificar.
6. **Pedir validación tarea por tarea.** Antipatrón: interrumpir al usuario tras cada tarea. Corrección: implementar todas y pedir una sola validación final.
7. **Implementar sin `design.md`.** Antipatrón: si falta un archivo, rellenarlo de memoria. Corrección: detenerse y remitir a `sdd-propose`.

## Salida final

Muestra:

- resumen de la implementación y del diff,
- tareas completadas y pendientes,
- comprobaciones ejecutadas y sus resultados,
- limitaciones o validaciones no ejecutadas,
- solicitud explícita de validación funcional final del usuario.
