---
name: feature-task-ids
description: Asigna y mantiene los identificadores de tarea FTxxxxx (feature) y FTxxxxx-PTn (parte) y los usa en ramas, PRs y commits. Úsala al seleccionar o crear una feature, al dividir una feature en varias partes (backend + cliente o más de 30 ficheros) o al abrir un PR. Se encadena desde feature-flow.
---

# Feature Task IDs

Define y mantiene el identificador corto de cada feature y de cada una de sus partes, y
lo hace aparecer en ramas, commits y títulos de PR. Es la versión operativa de
`docs/feature-ids.md`; este documento es la fuente de reglas y aquel mantiene la tabla.

## Cuándo se activa

- Al **seleccionar** una feature para trabajarla y crear su worktree/rama.
- Al **dividir** una feature en partes porque toca varias capas o supera los 30 ficheros.
- Al **abrir un PR** (o redactar su título/commit).
- Al **añadir o renombrar** una entrada en `feature_list.json`.

## Formato

- Feature: `FT` + 5 dígitos (`FT00001`). Se asigna una vez y **nunca** se reutiliza ni se
  renumera.
- Parte: `<FT>-PT<n>` (`FT00001-PT1`, `FT00001-PT2`), numeradas desde `1` por dependencia.
- Feature atómica (cabe en un PR): solo su `FTxxxxx`, sin `-PTn`.

## Fuente de verdad

- `feature_list.json`: campo `"ft_id"` en cada entrada, justo después de `"id"`; y el
  array opcional `"parts"` con `pt_id`/`area`/`scope`/`status` cuando la feature se divide.
- `docs/feature-ids.md`: convención, tabla de asignaciones y **siguiente FT libre**.

## Procedimiento: asignar un FT nuevo

1. Lee `docs/feature-ids.md` y toma el **siguiente número libre** (o el máximo de
   `feature_list.json` + 1 si el doc no lo indica).
2. Añade `"ft_id": "FTxxxxx"` a la entrada nueva en `feature_list.json`.
3. Actualiza la tabla y el contador *Siguiente FT libre* de `docs/feature-ids.md`.
4. Nunca cambies el `ft_id` de una entrada existente; si falta, asígnale el siguiente libre.

## Procedimiento: dividir en partes

1. Confirma que la feature necesita **más de un PR** (varias capas revisables por separado
   o más de 30 ficheros; ver `docs/git-workflow.md`). Si cabe en un PR, no la dividas.
2. Añade a la entrada de `feature_list.json` el array `parts` con un objeto por parte:
   `{ "pt_id": "FTxxxxx-PT1", "area": "backend", "scope": "...", "status": "not_started" }`.
3. Ordena las partes por dependencia (lo que debe existir antes, primero).
4. Cada parte se trabaja en su **propio worktree, rama y PR**, todas con el mismo `FT`.

## Procedimiento: nombrar rama, commit y PR

- **Rama**: `feat/<id-minúsculas>-<slug>` (p. ej. `feat/ft00101-pt1-search-savings-backend`).
  El identificador va primero.
- **Título del PR de una feature**: **MUST** empezar por su identificador y seguir con el
  Conventional Commit: `FT00101-PT1 feat(backend): ...`. Los PR de mantenimiento/docs que
  no correspondan a ninguna feature de `feature_list.json` no llevan FT.
- **Commit** (recomendado): `feat(FT00101-PT1): ...` o mencionar el identificador en el
  cuerpo.
- **Spec**: sigue en `docs/specs/<feature-id>.md`; anota el `ft_id` en su cabecera y el
  `pt_id` en las tareas que pertenezcan a una parte.

## Reglas

- Un `FT`/`PT` **nunca** se reutiliza ni se renumera, aunque la feature se cancele.
- No se inventan identificadores: se asignan en orden y se registran.
- El PR de una feature **siempre** lleva el identificador en el título; sin él no se abre.
  Los PR que no corresponden a ninguna feature de `feature_list.json` no llevan FT.
- Si una feature ya está en marcha sin `ft_id`, se le asigna el siguiente libre y se
  actualiza `feature_list.json` y `docs/feature-ids.md` en el mismo PR.

## Errores comunes

1. **Renumera un FT existente** (p. ej. al reordenar la lista). Antipatrón: cambiar
   `FT00020` porque se insertó una feature antes. Corrección: los FT son inmutables; la
   feature nueva toma el siguiente libre.
2. **Abre un PR sin el identificador en el título.** Antipatrón: `feat(backend): ...` a
   secas cuando la feature tiene `ft_id`. Corrección: `FT00020 feat(backend): ...`.
3. **Divide una feature que cabía en un PR.** Antipatrón: crear `PT1`/`PT2` por rutina.
   Corrección: solo se divide si hay varias capas revisables por separado o >30 ficheros.
4. **Olvida sincronizar el registro.** Antipatrón: añadir `ft_id` en `feature_list.json`
   sin tocar `docs/feature-ids.md`. Corrección: actualizar ambos en el mismo cambio.
