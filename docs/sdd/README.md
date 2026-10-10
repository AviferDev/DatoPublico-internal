# Specs SDD (flujo manual)

> Flujo **SDD** manual y **opcional**, alternativo al flujo de features
> (`feature-flow` → `docs/specs/<feature-id>.md`). Se activa solo si se nombran
> explícitamente las skills `sdd-propose` → `sdd-apply` → `sdd-archive`.

## Layout

- Una carpeta por feature: `docs/sdd/<feature>/`, con **tres** ficheros:
  - `spec.md` — el **qué** (requisitos `R1`, `R2`… con escenario `DADO/CUANDO/ENTONCES`).
  - `design.md` — el **cómo** (arquitectura, librerías, seguridad, BD, decisiones cerradas).
  - `tasks.md` — checklist de tareas numeradas, ordenadas por dependencia, cada una con su `(R<n>)`.
- Al cerrar (`sdd-archive`), la carpeta se mueve a `docs/sdd/archive/<feature>/`.

## Reglas

- `<feature>` va en `kebab-case` (minúsculas, sin acentos).
- No se mezcla con el flujo por feature para la **misma** feature: usa uno u otro.
- El flujo no escribe código de producto salvo en `sdd-apply`, y nunca archiva sin la
  validación funcional explícita del usuario.
- Las decisiones durables que salgan de una spec SDD se registran como **ADR** en
  `docs/adr/`.
