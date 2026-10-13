# ADR 0022: Detalle de publicación por identificador, solo resúmenes publicados y contrato reutilizado

## Estado

Aceptado (2026-10-13). Decisión del dueño del proyecto. Complementa el ADR 0021
(feed diario: pool único, solo `publicado`, contrato reutilizable) y el ADR 0018
(disposición del resumen); no supersede ninguno.

## Contexto

FT00027 expone el **segundo endpoint de lectura de datos** de `:backend` (tarea
`0.5-T02`): el detalle de una publicación por su identificador oficial del BOE.
Hay que fijar decisiones durables que condicionan al cliente y a las features de
API siguientes: cómo se identifica el recurso, qué resúmenes se sirven, qué
contrato devuelve, qué es `400`/`404` y cómo se comparte la conexión a base de
datos sin que el arranque dependa de ella. El detalle reutiliza lo ya construido
en FT00026 (contrato `PublicacionDto`, mapeo `FeedDtoMapper`, pool JDBC único).

## Decisión

- El detalle es de **solo lectura y público** (sin cuentas ni datos personales) y
  se consulta por el **identificador oficial** del BOE como **segmento de path**
  (`GET /publicacion/{id}`, p. ej. `BOE-A-2026-20979`): es un recurso estable y
  compartible. El versionado/OpenAPI del path es FT00029.
- Se sirve **solo** una publicación con `resumen.estado = 'publicado'` (token
  `SummaryState.PUBLISHED` que escribe la disposición de FT00023). Un
  identificador desconocido, un resumen no publicado (o ausente) y una publicación
  sin categoría (dato corrupto) responden `404`; **no** se inventa categoría ni
  resumen.
- Se **reutiliza** el contrato de wire `PublicacionDto` de `:shared` (ya lleva
  `categoria`, `urlOficial`, `resumen`, `plazo` y `avisoIA`) y el mapeo puro
  `feed/FeedDtoMapper.toPublicacionDto` de FT00026: **no** se crea ningún DTO nuevo.
- El `id` es un **segmento de path**; un `id` **en blanco** o más largo que
  `PublicationDetailService.MAX_ID_LENGTH` (128) responde `400` **sin cuerpo
  tipado** (el contrato de error consistente es FT00030). No se valida el **formato**
  del identificador: es **opaco** (la existencia decide `200`/`404`), para no rechazar
  identificadores legítimos de secciones con formatos distintos.
- El detalle compone `PublicationRepository.findById` + `SummaryRepository.findByPublication`
  (dos *lookups* por PK/FK, una fila) en un único `Dispatchers.IO`; **no** duplica el
  SQL del feed ni añade un `JOIN`.
- El composition root construye el servicio sobre el **pool JDBC único** ya
  compartido con el feed y la ingesta y registra la ruta **solo** si hay pool; sin
  BD, `/publicacion/{id}` **no** se registra (404) y `/health` sigue operativo.

## Alternativas consideradas

- **Query param `?id=`**: menos REST y enlaces menos canónicos; descartado.
- **Un `JOIN` nuevo en `FeedRepository`**: duplicaría columnas/SQL y arriesgaría
  CPD; se prefieren los dos *lookups* por clave de una sola fila.
- **DTO nuevo de detalle**: `PublicacionDto` ya es exactamente la respuesta;
  descartado para no duplicar contrato.
- **Validar el formato del identificador del BOE**: es opaco; se evitaría aceptar
  identificadores legítimos de secciones con formato distinto.
- **Lista completa de estados servibles**: solo `publicado`; revisar la cola manual
  es FT00033.
- **`500` para categoría nula**: se trata como **no servible** (`404`) siguiendo el
  patrón del feed; con el contrato de error (FT00030) podría revisarse.

## Consecuencias

- Habilita la pantalla de detalle (FT00033) sobre el **mismo** contrato que el feed.
- El `id` desmesurado se limita con `MAX_ID_LENGTH` (anti-abuso); el identificador
  no se valida semánticamente.
- El detalle devolverá `404` en producción hasta que exista un cableado del
  pipeline generación → guardrails → disposición (FT00020–FT00023): gap de
  planificación fuera del alcance de esta feature (igual que el feed).
- `ResumenDto.plazo` no se rellena desde `resumen` (la tabla no guarda plazo); el
  plazo fiable viaja en `PublicacionDto.plazo`, reutilizando el mapeo de FT00026.
- Sin migración (`V1`…`V5` intactas), sin cambios en el contrato de `:shared`, sin
  CORS/*rate limiting*/OpenAPI (FT00029/FT00030) ni UI (FT00033). La lectura JDBC
  (bloqueante) va fuera del event loop (`Dispatchers.IO`) y el SQL está
  parametrizado.
