# ADR 0021: Feed diario por fecha, solo resúmenes publicados y destacados *on-the-fly*

## Estado

Aceptado (2026-10-13). Decisión del dueño del proyecto. Complementa el ADR 0008
(destacados *on-the-fly*) y el ADR 0018 (disposición del resumen); no supersede
ninguno.

## Contexto

FT00026 expone el **primer endpoint de lectura de datos** de `:backend` (tarea
`0.5-T01`): el feed diario. Hay que fijar decisiones durables que condicionan al
cliente y a las features de API siguientes: cómo se selecciona el día, qué
resúmenes se sirven, cómo se explican los destacados, cómo se pagina y cómo se
comparte la conexión a base de datos sin que el arranque dependa de ella.

## Decisión

- El feed es de **solo lectura y público** (sin cuentas ni datos personales) y se
  consulta **por fecha** obligatoria (ISO-8601 `YYYY-MM-DD`). Los filtros de
  categoría/rango de fechas son de `api-busqueda` (FT00028); el feed no filtra por
  categoría.
- Se sirven **solo** las publicaciones con `resumen.estado = 'publicado'` (token
  que escribe la disposición de FT00023), mediante un `JOIN publicacion ⋈ resumen`
  parametrizado. Los resúmenes `en_cola_revision`/`pendiente`/`descartado` no
  aparecen ni cuentan en `total`. `urlOficial`/`fuenteOficial` viajan siempre
  (trazabilidad).
- Los **destacados** se calculan ***on-the-fly*** sobre el día completo con el
  ranker puro `HighlightRanker` (ADR 0008); **no** se persisten. El contrato expone
  los **motivos** (`HighlightReasonDto`, ≥1 por destacado) y **no** la puntuación
  numérica (`score`).
- La **paginación** es por `pagina`/`tamanoPagina` (default `20`, máximo `100`) y
  se hace **en memoria**: se carga el día completo porque los destacados necesitan
  todo el conjunto y el volumen diario del BOE es de cientos. Empujar `LIMIT/OFFSET`
  a SQL queda como optimización futura.
- El composition root crea **un único pool JDBC** si la configuración de BD
  resuelve, lo comparte entre el feed (API) y la ingesta, y lo cierra **una sola
  vez** en `ApplicationStopped`. Sin BD no se crea pool, `/feed` **no** se registra
  (404) y `/health` sigue operativo.
- `fecha` es **obligatoria**: no se introduce reloj ni zona en el servidor (endpoint
  determinista y testeable); el cliente (FT00032) envía «hoy» calculado localmente.

## Alternativas consideradas

- **`fecha` por defecto = hoy**: obliga a fijar reloj/zona en el servidor y hace los
  tests no deterministas; descartada.
- **`fecha` por defecto = la más reciente con contenido**: requeriría `fecha`
  nullable y una consulta de máximo adicional; descartada por ahora.
- **Rankear y paginar en SQL (`LIMIT/OFFSET`)**: los destacados necesitan el día
  completo, no una página; el volumen diario hace trivial paginar en memoria.
- **Persistir los destacados** (columna/tabla/segunda pasada): contradice el ADR
  0008 y añadiría esquema y job.
- **Pool propio de la API**: duplica conexiones en el N100/8 GB y complica el
  cierre; se comparte un único pool.
- **Exponer `score`**: explicación opaca; se expone el motivo objetivo y no el
  ranking crudo.

## Consecuencias

- Habilita el contrato que consumirán la UI del feed (FT00032) y, reutilizando el
  mapeo, el detalle (FT00027) y la búsqueda (FT00028).
- El feed saldrá **vacío** en producción hasta que exista un cableado del pipeline
  generación → guardrails → disposición (FT00020–FT00023): gap de planificación
  fuera del alcance de esta feature.
- `ResumenDto.plazo` no se rellena desde `resumen` (la tabla no guarda plazo); el
  plazo fiable viaja en `PublicacionDto.plazo`.
- Una fila sin categoría (columna nullable en `V2`, siempre rellena por FT00012) se
  trata como **dato corrupto** y se **excluye** del feed sin inventar categoría.
- Sin migración (`V1`…`V5` intactas) y sin CORS, *rate limiting*, OpenAPI ni cuerpo
  de error consistente (FT00029/FT00030).
- La lectura JDBC (bloqueante) se ejecuta fuera del event loop
  (`Dispatchers.IO`); el SQL está parametrizado.
