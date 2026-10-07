# Instrucciones para agentes — DatoPublico (harness interno)

Este repositorio (`.harness/`) contiene el **harness de desarrollo y el material
interno/privado** del proyecto DatoPublico: descubrimiento, diseño, roadmap y el
estado de features. **El código de producto no vive aquí**, sino en el
repositorio público, un nivel por encima (`..`).

**DatoPublico** explica en lenguaje claro **qué cambia** una norma publicada en
la Sección I del BOE y **a quién afecta**, con enlace siempre a la fuente
oficial. Es gratuito, de código abierto, sin cuentas ni datos personales. Stack
Kotlin end-to-end: backend **Ktor** + **PostgreSQL/pgvector**, cliente **Compose
Multiplatform** (Android, Web Wasm, iOS).

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
