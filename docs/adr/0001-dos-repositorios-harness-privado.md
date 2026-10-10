# ADR 0001: Dos repositorios (producto público + harness privado)

## Estado

Aceptado (2026-10-08). Decisión del dueño del repositorio. Es la decisión fundacional
de la topología del proyecto; la describen y aplican `README.md`, `AGENTS.md` y
`docs/git-workflow.md`.

## Contexto

El proyecto es **gratuito y de código abierto**, pero necesita material interno que
**no debe publicarse**:

- descubrimiento y diseño (problema, usuarios, modelo de dominio, riesgos);
- la hoja de ruta detallada y el **estado de las features** (con evidencia y notas);
- las **specs** y **validaciones** por feature y los **identificadores** de tarea.

A la vez, un agente de código necesita reglas de arranque, estado verificado y una lista
de features **en el directorio de trabajo**, no dispersos. Y el build (Gradle multi-módulo,
CI sin base de datos, etc.) exige que los artefactos de producto vivan en la raíz del
checkout.

Restricción: publicar el repositorio sin filtrar material interno, sin duplicar la
planificación en dos sitios y sin romper el descubrimiento estándar de skills y subagentes
de OpenCode (`.agents/skills/`, `.opencode/agents/`).

## Decisión

1. **Dos repositorios**:
   - **Producto** (público, `DatoPublico.git`): código, `README.md`, `ROADMAP.md`, CI y
     `docs/desarrollo-local.md` públicos.
   - **Harness** (privado, `DatoPublico-internal.git`): `AGENTS.md`, `CONSTRAINTS.md`,
     `PROGRESS.md`, `feature_list.json`, `CONTEXT.md`, `DESIGN.md`, `ARCHITECTURE.md`,
     `init.sh`, `docs/` internos (incluidas `adr/`, `specs/`, `validations/`, `git-workflow.md`,
     `feature-ids.md`) y `.agents/skills/`.
2. El **harness se clona dentro** del checkout del producto, en `.harness/`, y el repo
   público lo **ignora** vía `.git/info/exclude` (`.harness/`, `.agents`, `.opencode`).
3. Las skills y los subagentes se exponen en la raíz del producto con **symlinks**:
   `.agents -> .harness/.agents` y `.opencode -> .harness/.opencode`, de modo que OpenCode
   los descubre sin versionarlos en el repo público.
4. El **directorio de trabajo del harness es `.harness/`**; el código de producto se toca
   un nivel por encima (`..`). Los comandos de build se ejecutan desde el producto.
5. El **flujo de Git difiere por repo**: el producto usa rama + *claim* + PR; el harness es
   single-user y commitea en `main` (excepción documentada). Ver `docs/git-workflow.md`.

## Alternativas consideradas

- **Un solo repo privado**: imposible; el producto debe ser público.
- **Un solo repo público con todo dentro**: filtraría material interno o exigiría un
  `.gitignore` frágil y disciplina manual; la planificación no es publicable.
- **Harness como repo hermano (no dentro del checkout)**: evita anidar repos, pero pierde
  el descubrimiento estándar de skills/subagentes y obliga a rutas absolutas «mágicas» en
  cada sesión.
- **Harness como submódulo git**: versiona el anidamiento, pero añade fricción (init,
  updates, desincronización) sin aportar nada al flujo single-user.

## Consecuencias

- El material interno **no se publica** y el producto queda limpio.
- Un worktree del producto **no** incluye el harness; el flujo por defecto trabaja en rama
  sobre el checkout principal (que sí lo contiene). Ver `docs/git-workflow.md`.
- Los agentes deben saber que su directorio de trabajo es `.harness/` y que el código está
  en `..`; lo fijan `AGENTS.md` y los subagentes.
- Riesgo aceptado: el check-out del producto **no compila solo** con `git clone` del repo
  público (falta `.harness/`); el onboarding de equipo lo resuelve `README.md`
  («Cómo usarlo en un equipo nuevo»).
