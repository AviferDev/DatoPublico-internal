---
name: sdd-archive
description: Verifica y archiva una spec SDD terminada moviendo docs/sdd/<feature>/ a docs/sdd/archive/<feature>/ solo si no quedan tareas pendientes y el usuario confirma la validación funcional final. MANUAL-ONLY: úsala SOLO cuando el usuario nombre explícitamente `sdd-archive` (o `$sdd-archive`). No la actives sola ante peticiones genéricas de cerrar o archivar una feature.
---

# SDD Archive

Esta skill cierra el flujo SDD. Comprueba que la spec esté realmente terminada, registra
el cierre y la archiva. **Nunca archiva sin la confirmación de validación funcional del
usuario.**

Trabaja con el **harness como directorio de trabajo** (`.harness/`).

## Rol y límites

- Sí: revisar tareas y escenarios, recopilar evidencias, pedir confirmación, añadir la cabecera de cierre y mover la carpeta.
- No: archivar con tareas pendientes.
- No: archivar sin que el usuario confirme la validación funcional final.
- No: borrar ni reescribir el contenido de los tres archivos; solo se añade la cabecera de cierre a `spec.md`.

## Cuándo activarse

Activa esta skill ante frases como:

- "Archiva la spec de..."
- "Cierra la feature X."
- "Consolida la spec terminada de..."
- "Ejecuta sdd-archive para..."

## Procedimiento

1. **Localizar `docs/sdd/<feature>/`.** Si el usuario no indica la feature, pide que la concrete. No adivines.
2. **Comprobar que existan los tres archivos** (`spec.md`, `design.md`, `tasks.md`). Si falta alguno, detente y explícalo.
3. **Revisar todas las tareas de `tasks.md`.**
4. **Si alguna tarea sigue marcada como `[ ]`**: lista las tareas pendientes y **detente**. No archives. **CHECKPOINT.**
5. **Revisar los escenarios de todos los requisitos de `spec.md`.** Comprueba que cada requisito tiene al menos un escenario verificable.
6. **Comprobar que exista evidencia de cumplimiento**: tests, resultados técnicos, o evidencia documentada en `PROGRESS.md`, `feature_list.json` o notas de la spec. Si no hay evidencia, señálalo antes de continuar.
7. **Mostrar un resumen de las evidencias encontradas y de cualquier limitación.** Indica claramente qué escenarios no tienen evidencia directa.
8. **Solicitar confirmación explícita de que el usuario realizó y aprobó la validación funcional final.** Pregunta de forma directa. **CHECKPOINT.**
9. **No archives la spec sin esa confirmación.** Si el usuario no confirma, detente y explica que la feature queda implementada pero sin archivar.
10. **Añadir al principio de `spec.md` una cabecera de cierre** con este formato:

```md
> **Fecha de cierre:** <AAAA-MM-DD>
> **Estado final:** completada
> **Validación funcional:** confirmada por el usuario el <AAAA-MM-DD>
```

11. **Mover la carpeta** `docs/sdd/<feature>/` a `docs/sdd/archive/<feature>/`.
12. **Comprobar el resultado**: el directorio original ya no existe y el archivado conserva los tres archivos (`spec.md`, `design.md`, `tasks.md`).
13. **Mostrar un resumen final del archivado**: ruta de origen, ruta de destino, fecha de cierre y estado.

## Reglas de archivado

- El destino es siempre `docs/sdd/archive/<feature>/`.
- Si ya existe `docs/sdd/archive/<feature>/`, detente y pregunta cómo resolver el conflicto; no sobrescribas.
- Conserva los tres archivos intactos (salvo la cabecera añadida a `spec.md`).
- No renombres la feature al archivar; mantén el mismo `kebab-case`.

## Por qué de las reglas clave

- **Nada de archivar con tareas pendientes.** Una tarea `[ ]` significa que el trabajo no está hecho; archivar la ocultaría.
- **Confirmación de validación funcional obligatoria.** Las comprobaciones técnicas no sustituyen la comprobación de que la feature funciona para el usuario.
- **Cabecera de cierre.** Deja constancia de cuándo y con qué validación se cerró, para futuras consultas.
- **Conservar los tres archivos.** El archivo sigue siendo la memoria de la feature; no es una papelera.

## Errores comunes

1. **Archivar una spec con tareas pendientes.** Antipatrón: mover la carpeta aunque queden `[ ]`. Corrección: listar las pendientes y detenerse.
2. **Archivar sin la confirmación de validación funcional final.** Antipatrón: asumir que el usuario ya validó porque los tests pasan. Corrección: pedir confirmación explícita y no archivar sin ella.
3. **Perder archivos al mover.** Antipatrón: mover solo `spec.md` o sobrescribir el destino. Corrección: comprobar que los tres archivos llegan y que el destino no existía.
4. **Reescribir la spec al archivar.** Antipatrón: "limpiar" contenido durante el cierre. Corrección: solo añadir la cabecera; el resto se conserva.
5. **Archivar la feature equivocada.** Antipatrón: adivinar la carpeta por parecido. Corrección: pedir el nombre exacto si hay ambigüedad.

## Salida final

Muestra:

- feature archivada y rutas de origen y destino,
- evidencias encontradas y limitaciones,
- fecha de cierre y estado final,
- confirmación de que el directorio original ya no existe y de que se conservan los tres archivos.
