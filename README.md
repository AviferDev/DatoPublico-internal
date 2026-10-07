# DatoPublico — interno (PRIVADO)

Este repositorio contiene material **interno** del proyecto DatoPublico:
descubrimiento, diseño, roadmap detallado y, en el futuro, el harness de
desarrollo (`AGENTS.md`, `PROGRESS.md`, `feature_list.json`, specs…).

**Nunca se publica.** El repositorio público (`DatoPublico`) ignora esta carpeta
mediante `.gitignore` (`.harness/`).

## Contenido

- `CONTEXT.md` — glosario y lenguaje del dominio.
- `DESIGN.md` — dirección visual.
- `docs/build-brief.md` — problema, usuarios, objetivos y MVP.
- `docs/domain-model.md` — modelo de dominio.
- `docs/technical-discovery.md` — stack, datos, integraciones y operación.
- `docs/risks-and-open-questions.md` — riesgos y dudas abiertas.
- `docs/roadmap.md` — roadmap detallado por versiones.

## Cómo usarlo en un equipo nuevo

```sh
git clone <url-repo-publico> DatoPublico
git clone <url-repo-privado> DatoPublico/.harness
```
