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

## Límite de tamaño de los cambios (30 ficheros)

Para que la revisión sea viable, ningún PR puede superar los **30 ficheros modificados**:

- **Antes** de empezar una tarea, estimar cuántos ficheros va a tocar.
- Si la estimación supera **30**, dividirla en varias **partes** independientes, cada una
  con su rama/PR y su `FTxxxxx-PTn` (ver la skill `feature-task-ids`).
- El límite cuenta ficheros modificados en el PR (añadidos, editados o borrados), no líneas.
- Si al terminar se excede, partir el PR en trozos coherentes que se revisen por separado.

### Excepción: renombrados mecánicos atómicos

Los **renombrados de identificadores** (p. ej. `FT00047 english-identifiers-rename`)
son **atómicos por símbolo**: renombrar un tipo obliga a actualizar todas sus
referencias en el **mismo** PR, y varios símbolos superan por sí solos los 30
ficheros. Para estos casos se admite una **excepción documentada** al límite de 30
ficheros:

- El PR debe ser **puramente mecánico**: solo renombrados de identificadores, sin
  cambios de comportamiento ni de contrato (JSON/`@SerialName`, columnas SQL,
  migraciones y tokens de wire **invariantes**).
- Se divide en **partes** `FTxxxxx-PTn` (una por grupo atómico de símbolos), cada
  una su rama/PR, encadenadas desde el estado mergeado de la anterior.
- La excepción se anota en el spec de la feature y en el PR (motivo + recuento de
  ficheros), y el gate (`build`/`test`/`detekt`/`init.sh`) debe quedar verde en
  cada parte.
- El resto de features siguen sujetas al límite de 30 ficheros.

## Mantener el PR actualizado

**Siempre que se haga `git push`** a una rama que ya tiene PR (commit nuevo, rebase,
`--force-with-lease`), hay que **comprobar la información del PR y actualizarla si quedó
obsoleta**. Un push que cambia el diff sin refrescar el PR lo deja mintiendo.

```sh
gh pr view <n> --json title,body,state,baseRefName,headRefName   # revisar
gh pr edit <n> --title "..." --body "..."                        # actualizar si hace falta
```

- **Título**: si cambió el alcance, el `FTxxxxx-PTn`, el número de ADR o el tipo/scope.
- **Cuerpo**: debe corresponder al diff actual (qué cambia, cómo se verificó —comandos y
  resultado— y, si aplica, capturas antes/después). Tras un rebase, comprobar que las
  referencias (rutas, ADRs, ficheros) siguen existiendo.
- **Base y cabecera**: `main` y la rama correcta.
- Aplica a **cualquier** push, no solo al inicial.

## Capturas en cambios de interfaz

Cuando el PR **modifica la interfaz** del cliente (`:composeApp`) o el diseño
(`DESIGN.md`), es obligatorio adjuntar **capturas del antes y el después**. La
convención completa (dónde se guardan, cómo se enlazan y qué hacer si no se puede
capturar) está en [`docs/pr/README.md`](pr/README.md).

- **Antes**: capturar el estado base **antes** de tocar el código.
- **Después**: capturar al **final**, con el cambio aplicado y la app reconstruida.
- La UI es común (`commonMain`): basta **una** plataforma representativa (Android en el
  emulador o Web en el navegador).
- Se commitean en `docs/pr/<slug-de-rama>/` y se enlazan en el PR con **URL absoluta a la
  rama**.
- Un cambio visual sin capturas (o sin justificar por qué no se pudo) no se mergea.

## Evitar problemas (uso seguro de Git)

### Antes de empezar

- Actualiza la referencia base y limpia ramas remotas borradas:
  `git fetch origin --prune`.
- Comprueba dónde estás antes de tocar nada: `git status -sb`.
- El harness (privado) es single-user: sus cambios van en `main`. El **producto** nunca se
  commitea en `main` (rama + *claim* + PR).

### Problemas frecuentes

- **Trabajé en `main` del producto por descuido.** Si aún no has commiteado, muévete a una
  rama nueva con los cambios encima: `git switch -c feat/<ft-id>-<slug>`. Si ya commiteaste
  en `main` local, crea la rama apuntando al commit y deja `main` en el remoto:
  `git branch feat/<ft-id>-<slug>` y `git reset --hard origin/main`.
- **La rama está desactualizada respecto a `main`.** Antes de abrir el PR:
  `git fetch origin` y `git rebase origin/main`. Resuelve conflictos, `git add` y
  `git rebase --continue`. El repo usa **rebase**, no `merge` de `main` dentro de la rama.
- **Push rechazado (`non-fast-forward`).** Tras un rebase, en una rama de feature es
  `git push --force-with-lease` (nunca `--force` a pelo y **jamás** a `main`).
- **Se me coló un secreto o un artefacto.** `.env`, claves, `build/`, `local.properties`…
  nunca se commitean (ver `.gitignore`). Revisa `git status` y `git diff --cached` antes de
  commitear. Si un secreto llega a un commit, **no basta** con borrarlo después: hay que
  **rotarlo**.
- **Dos sesiones eligen la misma feature y se pisan.** Seleccionar por orden no reserva
  nada: reclama con el push inmediato de la rama antes de planificar; si el push se
  rechaza, la feature ya está cogida (ver *Selección y claim*).
- **El PR pasa de 30 ficheros.** Divídelo (ver *Límite de tamaño de los cambios*).
- **El título del PR no empieza por el identificador.** Añádelo (`FT00005-PT1 feat(...): ...`).
- **El PR quedó desactualizado tras un push o un rebase.** Revísalo y actualízalo
  (`gh pr view` / `gh pr edit`).
- **Merge sin verificación.** Ningún PR se fusiona sin el gate en verde
  (`./init.sh`, o los flags del cliente/iOS según el cambio) y sin la revisión explícita del
  dueño.

### Nunca

- Nunca commitear directamente en `main` del **producto**.
- Nunca `git push --force` a `main` (en una rama de feature, solo `--force-with-lease`).
- Nunca commitear secretos (`.env`, claves, tokens).
- Nunca fusionar un PR sin revisión explícita ni sin capturas si cambia la interfaz.
- Nunca un PR de más de 30 ficheros ni con el título sin su `FTxxxxx`/`FTxxxxx-PTn`.
- Nunca reutilizar ni renumerar un identificador de tarea.
- Nunca empezar sin reclamar la feature (push de su rama) ni borrar la rama de claim de
  otra sesión sin confirmarlo con el dueño.

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
