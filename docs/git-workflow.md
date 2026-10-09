# Git workflow — DatoPublico

> Protocolo de ramas, *claim*, commits y PR para el flujo de features
> (`feature-flow`). Adaptado a la realidad de **dos repositorios**.

## Repositorios

| Rol | Ruta local | Remoto | Contenido |
| --- | --- | --- | --- |
| **Producto** (público) | `.harness/..` (raíz del checkout) | `DatoPublico.git` | Código de producto (módulos Gradle, app). |
| **Harness** (privado) | `.harness/` | `DatoPublico-internal.git` | `feature_list.json`, `PROGRESS.md`, specs, validaciones, diseño y docs. |

El harness vive **dentro** del checkout del producto, pero el repo público lo
ignora (`.git/info/exclude`: `.harness/`, `.agents`, `.opencode`).

## Reglas

- Rama troncal: **`main`** en ambos repos.
- **Código de producto:** nunca se commitea en `main`. Se usa una rama
  `feat/<ft-id-minúsculas>[-ptn]-<slug>` y un **PR**. El identificador va primero.
- **Harness privado:** es coordinación **single-user**; sus cambios se commitean
  en `main` del harness. Esta es la **excepción documentada** a «no commit en
  `main`»: la regla estricta aplica solo al repo de producto.
- Todo paso de spec/validación se ejecuta con el harness como directorio de
  trabajo. El código se toca en la raíz del producto (un nivel por encima).

## Selección y *claim*

1. Selecciona la feature (ver `feature-flow`).
2. Asegura su `ft_id` (`docs/feature-ids.md`; skill `feature-task-ids`).
3. Crea la rama en el **repo de producto** desde `origin/main`:
   `feat/<ft-id-minúsculas>[-ptn]-<slug>`.
4. **Reclama de inmediato**: commit vacío `chore(<FT>): claim` y
   `git push -u origin <branch>`. El primer push gana. Si te lo rechazan, la
   feature ya está reclamada: descarta la rama local y reelege.
5. No hace falta claim en el harness (privado, un solo usuario).

## Rama vs. worktree

- **Por defecto:** trabaja en una **rama del checkout principal**. Es lo
  recomendado aquí porque el checkout principal contiene `.harness/`, y un
  worktree del repo de producto **no** incluiría el harness.
- **Worktrees:** solo si necesitas sesiones en paralelo. En ese caso, el worktree
  del producto no tendrá `.harness`; aporta el harness aparte (p. ej. otro
  checkout del repo interno) y usa la ruta que corresponda.

## Commits

- Conventional Commits con el identificador como *scope*:
  - `feat(FTxxxxx[-PTn]): complete <feature-id>` — feature de producto.
  - `docs(FTxxxxx): complete <feature-id>` — solo documentación.
  - `chore(FTxxxxx): complete <feature-id>` — tooling/flujo.
- Producto: en su rama `feat/...`. Harness: en `main`.

## Pull Request

- **Producto: obligatorio.** `gh pr create --base main --head <branch> --title "<FT> <tipo>(<scope>): <resumen>"`.
  El título **debe** empezar por el identificador. Incluye la evidencia de
  verificación en el cuerpo. No se fusiona sin revisión explícita.
- **Harness:** no requiere PR.

## Cierre tras `accept`

1. El orquestador actualiza `feature_list.json` (harness): estado `accepted` +
   evidencia concisa; opcionalmente `docs/validations/<feature-id>.md`.
2. Commit del harness en `main`.
3. Commit/PR del producto si hubo cambios de código.
4. Reporta el handoff al usuario.

## Detección de features reclamadas

Una feature está reclamada si existe en el remoto del **producto** una rama
`feat/<ft-id-minúsculas>*` o un PR abierto cuyo título empiece por su `FT`.

```sh
git fetch origin --prune
git ls-remote --heads origin 'refs/heads/feat/ft<nnnnn>*'
gh pr list --state open --json number,headRefName,title
```
