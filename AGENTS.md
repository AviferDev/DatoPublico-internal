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
- `docs/git-workflow.md` — ramas, *claim*, commits y PR (dos repos); incluye el
  límite de 30 ficheros, el mantenimiento del PR y las capturas de interfaz.
- `docs/feature-ids.md` — registro de identificadores `FTxxxxx`.
- `docs/adr/` — decisiones de arquitectura (ADR) e índice; consúltalo antes de
  contradecir una decisión aceptada.
- `docs/pr/` — convención de capturas antes/después en cambios de interfaz.
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

**Flujo SDD manual (alternativo, opcional).** Además del flujo por feature, existe un
flujo SDD manual con las skills `sdd-propose` → `sdd-apply` → `sdd-archive` (solo se
activan si se nombran explícitamente). Escribe una spec por feature en
`docs/sdd/<feature>/` con tres ficheros (`spec.md`, `design.md`, `tasks.md`), deja
constancia de la validación funcional del usuario y archiva en `docs/sdd/archive/<feature>/`.
Es un camino **independiente** del flujo `planner/implementer/validator`; no se mezclan
para la misma feature.

## Flujo de arranque

Antes de escribir código:

1. Confirma con `pwd` que estás en `.harness/` (el harness). El código de
   producto está en `..`.
2. Lee `PROGRESS.md` para conocer el estado verificado y el siguiente paso.
3. Lee `feature_list.json` y elige la **primera feature lista** aún no terminada,
   en el orden del fichero.
4. Ejecuta `./init.sh`.
5. Si la verificación base falla, arréglala antes de añadir trabajo de feature.

## Verificación y comandos

- **Gate estándar (SDK-free, no arranca servidores)**: `./init.sh` →
  `./gradlew build -PskipClient` + `./gradlew detekt` (Detekt + `:cpdCheck`).
- **Gate con cliente Android/Web**: `./init.sh --with-client` (exige el Android SDK).
- **Gate iOS** (framework de simulador): `./init.sh --with-ios` (exige Xcode);
  `--with-all` activa ambos. Ninguno arranca el simulador.
- **Tests**: `./gradlew test [-PskipClient]` agrega `:shared:jvmTest`, `:backend:test`
  y, sin `-PskipClient`, `:composeApp:jvmTest`.
- **Calidad**: `./gradlew detekt` (Detekt por módulo) y `./gradlew :cpdCheck`
  (duplicación). Son **bloqueantes**: `check`/`build` los arrastran.
- **Backend**: `./gradlew :backend:run` (no lo arranca el gate).
- **Migraciones**: `./gradlew :backend:flywayMigrate` (tarea explícita, **fuera** de
  `build`/`check`; la CI corre sin base de datos).
- `-PskipClient` excluye `:composeApp` del build y deja `:shared`/`:backend` sin exigir
  el Android SDK (lo reutilizará la imagen del backend).

## Reglas de trabajo

- Trabaja en **una sola feature** a la vez.
- No marques una feature como terminada solo porque hayas añadido código.
- Mantén los cambios dentro del alcance de la feature elegida salvo bloqueo que
  exija un arreglo de soporte acotado.
- No cambies las reglas de verificación durante la implementación.
- Actualiza los artefactos del repo en lugar de fiarte de resúmenes de chat.
- **Documenta con KDoc** todo el Kotlin que añadas o modifiques (ver `CONSTRAINTS.md`
  §«Documentación de código»).
- Escribe **todo el código en inglés**: los **identificadores** (paquetes, tipos,
  funciones, propiedades, constantes y tests) van en inglés; el **KDoc y los
  comentarios** van en castellano (`CONSTRAINTS.md` §«Nombres y contratos»).
- Respeta las reglas **MUST** de estilo y UI de `CONSTRAINTS.md`: **un solo `return`**
  por función, **sin `else if`**, máximo **40 líneas** por función, **reutilizar** antes
  de escribir, **crear la capa que falte**, `@Preview` en toda función `@Composable`,
  **nunca provocar un crash**, textos de UI desde **recursos (i18n)**, **Material Icons**
  y colores **solo** de `MaterialTheme.colorScheme`.
- Registra las **decisiones durables** como **ADR** en `docs/adr/` (ver
  `docs/adr/README.md`).
- Un cambio de **interfaz** lleva **capturas antes/después** (`docs/pr/README.md`); ningún
  PR supera los **30 ficheros**.

## Artefactos obligatorios

- `feature_list.json` — fuente de verdad del estado de las features.
- `PROGRESS.md` — estado verificado actual y bitácora ligera de sesiones.
- `init.sh` — camino estándar de arranque y verificación.

## Definición de terminado

Una feature está terminada solo si:

- el comportamiento objetivo está implementado,
- todo el código añadido o modificado está documentado con **KDoc**,
- el código respeta las **MUST** de `CONSTRAINTS.md` (un solo `return`, sin `else if`,
  máximo 40 líneas/función, reutilización, capa correcta, `@Preview`, sin crashes
  deliberados, i18n, Material Icons, colores del tema, `@SerialName` explícito),
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
