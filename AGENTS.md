# Instrucciones para agentes — DatoPublico (harness interno)

Este repositorio (`.harness/`) contiene el **harness de desarrollo y el material
interno/privado** del proyecto DatoPublico: descubrimiento, diseño, roadmap y el
estado de features. **El código de producto no vive aquí**, sino en el
repositorio público, un nivel por encima (`..`).

**DatoPublico** explica en lenguaje claro **qué se ha publicado** en el BOE
(todo el sumario: normas, nombramientos, empleo público, becas
y subvenciones, premios, convenios, información pública…) por **categoría** y **a
quién afecta**, con enlace siempre a la fuente oficial, un feed diario con
destacados y un chat que verifica afirmaciones contra el BOE. Es gratuito, de
código abierto, sin cuentas ni datos personales. Stack Kotlin end-to-end: backend
**Ktor** + **PostgreSQL/pgvector**, cliente **Compose Multiplatform** (Android,
Web Wasm, iOS).

## Léelo primero (rutas relativas a `.harness/`)

- `CONTEXT.md` — glosario y lenguaje del dominio.
- `docs/build-brief.md` — problema, usuarios, objetivos y MVP.
- `docs/domain-model.md` — entidades, relaciones y estados.
- `docs/risks-and-open-questions.md` — riesgos y dudas abiertas.

Léelos solo cuando apliquen:

- `docs/technical-discovery.md` — stack, datos, integraciones, despliegue u
  operación.
- `DESIGN.md` — dirección visual, tokens y pantallas.
- `docs/roadmap.md` — plan detallado por versiones (`0.1.0` → `1.0.0`).
- `docs/git-workflow.md` — ramas, *claim*, commits y PR (dos repos).
- `docs/feature-ids.md` — registro de identificadores `FTxxxxx`.
- `docs/specs/` y `docs/validations/` — specs y validaciones por feature.
- `.opencode/agents/` — subagentes `planner`, `implementer`, `validator`.
- `ARCHITECTURE.md` — mapa de módulos y fronteras.
- `CONSTRAINTS.md` — reglas operativas MUST/MUST NOT.

**Namespace del código:** `es.aviferdev.datopublico` (backend en
`es.aviferdev.datopublico.backend`).

## Flujo de features

Para una feature concreta existe `feature-flow` con tres roles (`planner` →
`implementer` → `validator`) y sus skills. Antes de ejecutarlo:

1. La feature debe tener `ft_id` (`docs/feature-ids.md`).
2. Sigue el protocolo de `docs/git-workflow.md` (rama en el repo de producto,
   *claim* por push, commits con `FT` como scope, PR).
3. Los specs viven en `docs/specs/<feature-id>.md` y las validaciones en
   `docs/validations/<feature-id>.md`.

## Flujo de arranque

Antes de escribir código:

1. Confirma con `pwd` que estás en `.harness/` (el harness). El código de
   producto está en `..`.
2. Lee `PROGRESS.md` para conocer el estado verificado y el siguiente paso.
3. Lee `feature_list.json` y elige la **primera feature lista** aún no terminada,
   en el orden del fichero.
4. Ejecuta `./init.sh`.
5. Si la verificación base falla, arréglala antes de añadir trabajo de feature.

## Reglas de trabajo

- Trabaja en **una sola feature** a la vez.
- No marques una feature como terminada solo porque hayas añadido código.
- Mantén los cambios dentro del alcance de la feature elegida salvo bloqueo que
  exija un arreglo de soporte acotado.
- No cambies las reglas de verificación durante la implementación.
- Actualiza los artefactos del repo en lugar de fiarte de resúmenes de chat.

## Artefactos obligatorios

- `feature_list.json` — fuente de verdad del estado de las features.
- `PROGRESS.md` — estado verificado actual y bitácora ligera de sesiones.
- `init.sh` — camino estándar de arranque y verificación.

## Definición de terminado

Una feature está terminada solo si:

- el comportamiento objetivo está implementado,
- la verificación requerida se ejecutó de verdad,
- la evidencia queda registrada en `feature_list.json` o `PROGRESS.md`,
- el repositorio sigue arrancable por el camino estándar,
- la documentación relevante se actualizó si cambió el comportamiento, las
  reglas de dominio, la API o la verificación.

## Fin de sesión

Antes de cerrar una sesión:

1. Actualiza `PROGRESS.md`.
2. Actualiza `feature_list.json`.
3. Registra riesgos o bloqueos sin resolver.
4. Deja el repo lo bastante limpio para que la siguiente sesión ejecute
   `./init.sh` de inmediato.
