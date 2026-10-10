---
name: sdd-propose
description: Crea una especificación SDD nueva (spec.md, design.md y tasks.md) para una feature en docs/sdd/<feature>/ sin escribir código. MANUAL-ONLY: úsala SOLO cuando el usuario nombre explícitamente `sdd-propose` (o `$sdd-propose`). No la actives sola ante peticiones genéricas de planificar, especificar o documentar una feature; para eso usa feature-spec.
---

# SDD Propose

Esta skill abre el flujo SDD manual. Su único objetivo es convertir una idea de feature
en una especificación revisable y aprobable. **No implementa código.**

Trabaja con el **harness como directorio de trabajo** (`.harness/`); el código de producto
está un nivel por encima (`..`).

## Rol y límites

- Sí: identificar la feature, entrevistar si falta información, escribir `spec.md`, `design.md` y `tasks.md`.
- No: escribir código de producto, tocar el código existente, ni crear archivos fuera de `docs/sdd/<feature>/`.
- No: inventar requisitos ni decisiones técnicas. Si algo no está claro, se pregunta.

## Cuándo activarse

Activa esta skill ante frases como:

- "Crea una spec para..."
- "Propón la spec de..."
- "Define la feature..."
- "Inicia el SDD de..."
- "Ejecuta sdd-propose para..."

## Entradas a leer primero

1. `AGENTS.md` — reglas y artefactos obligatorios del repositorio.
2. `CONSTRAINTS.md` — reglas operativas MUST/MUST NOT.
3. `CONTEXT.md` — lenguaje de dominio; usar los términos canónicos.
4. `docs/build-brief.md`, `docs/domain-model.md`, `docs/risks-and-open-questions.md` — contexto de producto.
5. `docs/technical-discovery.md` y `DESIGN.md` si la feature toca stack o interfaz.
6. `feature_list.json` — para no duplicar features y respetar dependencias.
7. `docs/adr/` — decisiones aceptadas que la feature no debe contradecir.
8. `docs/sdd/` y `docs/sdd/archive/` — para comprobar nombres ya usados.

## Procedimiento

1. **Identificar el nombre de la feature.** Extrae el nombre de la petición del usuario y normalízalo a `kebab-case` (minúsculas, guiones, sin acentos). Ejemplo: "Autenticación biométrica" → `autenticacion-biometrica`.
2. **Comprobar que no exista una spec con ese nombre.** Busca en `docs/sdd/<nombre>/` y en `docs/sdd/archive/<nombre>/`. Si ya existe, detente y pregunta si se quiere retomar, renombrar o crear otra.
3. **Revisar el contexto y las reglas del repositorio.** Lee las entradas de la sección anterior y respeta el lenguaje de dominio y las restricciones ya decididas.
4. **Detecta huecos de información y entrevista.** Si falta el motivo, el alcance o alguna restricción esencial, haz preguntas breves, de una en una, con una opción recomendada. **CHECKPOINT:** no escribas archivos hasta tener motivo, alcance y restricciones mínimos.
5. **Validar la verificabilidad de los requisitos.** Antes de escribir, comprueba que cada requisito se puede expresar con al menos un escenario `DADO / CUANDO / ENTONCES`. Si un requisito no se puede verificar, **detente** y pide al usuario que lo reformule (Por qué: un requisito no verificable no se puede aceptar ni archivar).
6. **Crear los tres archivos** con las plantillas de abajo: `docs/sdd/<feature>/spec.md`, `docs/sdd/<feature>/design.md`, `docs/sdd/<feature>/tasks.md`. No crees ningún otro archivo.
7. **Comprobar las tareas.** Verifica que estén numeradas, ordenadas por dependencia y que cada una referencie al menos un requisito entre paréntesis, por ejemplo `(R2)`.
8. **Mostrar un resumen de la propuesta**: nombre, motivo, requisitos, decisiones técnicas y número de tareas.
9. **Solicitar revisión y aprobación.** **CHECKPOINT:** espera la respuesta explícita del usuario. No implementes ni archives nada.
10. **No implementar código.** Aunque el usuario lo pida en el mismo mensaje, recuérdale que primero debe aprobar la spec y que la implementación se hace con `sdd-apply`.

## Plantillas de archivos

### `spec.md` — el QUÉ

```md
# Spec: <nombre de la feature>

## Por qué

<Motivo y valor de la feature. Qué problema resuelve y para quién.>

## Requisitos

### R1 — <título corto>

El sistema DEBE <comportamiento>.

**Escenario:** DADO <situación inicial> / CUANDO <acción> / ENTONCES <resultado esperado>.

### R2 — <título corto>

El usuario PUEDE <comportamiento>.

**Escenario:** DADO <situación inicial> / CUANDO <acción> / ENTONCES <resultado esperado>.
```

Reglas del `spec.md`:

- Cada requisito se identifica como `R1`, `R2`, etc.
- Cada requisito usa `DEBE`, `PUEDE` o `NO DEBE`.
- Cada requisito incluye al menos un escenario verificable.
- Describe el qué, nunca el cómo (el cómo va en `design.md`).

### `design.md` — el CÓMO

```md
# Design: <nombre de la feature>

## Arquitectura

<Componentes, responsabilidades y flujo.>

## Librerías

<Librerías permitidas y por qué.>

## Restricciones de seguridad

<Qué está prohibido, dónde viven los secretos, qué nunca se expone.>

## Cambios de base de datos

<Migraciones, tablas, columnas o "ninguno".>

## Decisiones de implementación

<Decisiones cerradas que el agente no puede reinventar.>
```

Reglas del `design.md`:

- Contiene solo decisiones cerradas; nada de opciones abiertas.
- Si una decisión no se conoce, se pregunta antes de escribir.

### `tasks.md` — el CÓMO paso a paso

```md
# Tasks: <nombre de la feature>

- [ ] 1. <tarea pequeña> (R1)
- [ ] 2. <tarea pequeña> (R1, R2)
- [ ] 3. <tarea pequeña> (R2)
```

Reglas del `tasks.md`:

- Checklist Markdown, tareas pequeñas y numeradas.
- Ordenadas por dependencia (lo que debe existir antes, primero).
- Cada tarea referencia el requisito o requisitos que implementa.

## Checkpoints obligatorios

- Tras el paso 4: si falta información esencial, detenerse y esperar respuestas.
- Tras el paso 5: si un requisito no es verificable, detenerse y pedir reformulación.
- Tras el paso 9: esperar la aprobación explícita del usuario antes de dar la spec por cerrada.

## Por qué de las reglas clave

- **La spec es la fuente de verdad.** Si el código puede desviarse en silencio, la spec deja de servir como contrato.
- **Escenarios verificables obligatorios.** Sin un escenario `DADO/CUANDO/ENTONCES`, no hay forma objetiva de saber si el requisito se cumplió.
- **Prohibido implementar en propose.** Separar el qué del cómo evita que el diseño se decida "por accidente" al escribir código.

## Errores comunes

1. **Implementar código durante el propose.** Antipatrón: el usuario pide "crea la spec y ya la implementas" y el agente escribe código. Corrección: crear solo los tres archivos y remitir la implementación a `sdd-apply`.
2. **Requisitos sin escenario verificable.** Antipatrón: "El sistema DEBE ser rápido" sin escenario. Corrección: detenerse y pedir que se reformule con `DADO/CUANDO/ENTONCES`.
3. **Inventar decisiones técnicas.** Antipatrón: el agente elige una librería "que le suena bien" porque `design.md` no la fija. Corrección: preguntar antes de escribir el diseño.
4. **Tareas sin requisito asociado.** Antipatrón: tareas sueltas que no llevan `(R1)`. Corrección: vincular cada tarea a uno o varios requisitos.
5. **Duplicar una spec existente.** Antipatrón: crear `docs/sdd/login/` cuando ya existe con otro nombre casi igual. Corrección: comprobar `docs/sdd/` y `docs/sdd/archive/` antes de crear.

## Salida final

Muestra:

- ruta de la carpeta creada,
- resumen de motivo, requisitos, decisiones y tareas,
- petición explícita de aprobación antes de pasar a `sdd-apply`.
