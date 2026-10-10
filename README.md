# DatoPublico — interno (PRIVADO)

Este repositorio contiene material **interno** del proyecto DatoPublico:
descubrimiento, diseño, roadmap detallado y, en el futuro, el harness de
desarrollo (`AGENTS.md`, `PROGRESS.md`, `feature_list.json`, specs…).

**Nunca se publica.** El repositorio público (`DatoPublico`) ignora esta carpeta
y el symlink `.agents` mediante una exclusión local no versionada
(`.git/info/exclude`).

## Contenido

- `CONTEXT.md` — glosario y lenguaje del dominio.
- `DESIGN.md` — dirección visual.
- `docs/build-brief.md` — problema, usuarios, objetivos y MVP.
- `docs/domain-model.md` — modelo de dominio.
- `docs/technical-discovery.md` — stack, datos, integraciones y operación.
- `docs/risks-and-open-questions.md` — riesgos y dudas abiertas.
- `docs/roadmap.md` — roadmap detallado por versiones.
- `docs/adr/` — decisiones de arquitectura (ADR) e índice.
- `docs/sdd/` — specs del flujo SDD manual (`spec.md`/`design.md`/`tasks.md` por feature).
- `docs/pr/` — convención de capturas antes/después para los PR de interfaz.
- `docs/git-workflow.md` — flujo de ramas, *claim*, commits y PR (dos repos).
- `docs/feature-ids.md` — registro de identificadores `FTxxxxx`.
- `docs/specs/` y `docs/validations/` — specs y validaciones por feature.
- `.agents/skills/` — skills para agentes (RepoSkills), versionadas aquí.
- `.opencode/agents/` — subagentes `planner`, `implementer`, `validator`.

## Licencia

El proyecto público **DatoPublico** se distribuye bajo la **Mozilla Public
License 2.0 (MPL-2.0)**; el fichero `LICENSE` vive en el repositorio público.
Este repositorio interno no se licencia para terceros: es material privado de
desarrollo.

## Repositorios

- Público: `https://github.com/AviferDev/DatoPublico`
- Privado (este): `https://github.com/AviferDev/DatoPublico-internal`

## Cómo usarlo en un equipo nuevo

```sh
git clone https://github.com/AviferDev/DatoPublico.git DatoPublico
git clone https://github.com/AviferDev/DatoPublico-internal.git DatoPublico/.harness

# Enlazar las skills a la ubicación estándar que descubre OpenCode
cd DatoPublico
ln -s .harness/.agents .agents
```
