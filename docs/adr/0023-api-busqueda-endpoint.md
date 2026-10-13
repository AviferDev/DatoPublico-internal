# ADR 0023: Búsqueda sobre el corpus con `HybridSearch`, resultado a nivel de publicación y wiring condicional del proveedor de embeddings

## Estado

Aceptado (2026-10-13). Decisión del dueño del proyecto. Reutiliza el ADR 0012
(recuperación híbrida) y complementa el ADR 0021/0022 (feed y detalle); no
supersede ninguno.

## Contexto

FT00028 expone el **endpoint de búsqueda** (`GET /buscar`, tarea `0.5-T03`): dada
una consulta `q` y filtros opcionales de categoría (`categoria`) y rango de fechas
(`desde`/`hasta`), devuelve las publicaciones más relevantes del corpus. Hay que
fijar decisiones durables que condicionan al cliente y a las features de API
siguientes (chat FT00031, CORS/OpenAPI FT00029/FT00030): qué unidad se devuelve,
qué contratos se reutilizan, cómo se filtra, cómo se ordena y acota el resultado, y
cómo se cablea por primera vez el proveedor de embeddings locales (ONNX) sin que el
arranque dependa de él.

## Decisión

- La búsqueda es de **solo lectura y pública** (sin cuentas ni datos personales) y
  se consulta con `q` **obligatoria** (no vacía) más filtros **opcionales**:
  `categoria` (token de wire de `CategoriaDto`, resuelto por el contrato de
  serialización `@SerialName`, no por el nombre del enum), `desde`/`hasta` (fechas
  ISO-8601 `YYYY-MM-DD` **inclusivas**) y `limite` (default `10`, máximo `50`).
- La **unidad de resultado es la publicación**, no el fragmento: el cliente navega
  al detalle y renderiza la tarjeta del feed. Cada resultado es el **mismo**
  `PublicacionDto` de `:shared` que sirven el feed y el detalle (con su `resumen`,
  `categoria`, `urlOficial` y `plazo`), reutilizando el mapeo puro
  `feed/FeedDtoMapper`; no se crea un DTO por ítem.
- Se sirven **solo** publicaciones con `resumen.estado = 'publicado'` (token tipado
  `SummaryState.PUBLISHED` que escribe FT00023). Las no publicadas **no** aparecen
  (aunque el fragmento exista), manteniendo coherencia con `/feed` y
  `/publicacion/{id}`. El filtro vive en SQL (`FeedRepository.listPublishedByIds`),
  no en memoria.
- La **recuperación** la hace `rag/retrieval` (FT00017) **sin modificarla**:
  `HybridSearch.search(query, SearchFilter, candidateLimit)` vectoriza la consulta
  con `embedQuery` y consulta `FragmentRepository.findNearest` con los filtros de
  metadatos ya parametrizados (`SearchFilterSql`).
- El resultado es **top-k (ANN), sin paginación**: `limite` acota el número de
  publicaciones; no se expone `total` ni paginación profunda porque no son
  significativos con un índice aproximado. Se sobre-recuperan
  `limite * CANDIDATE_FACTOR` (`CANDIDATE_FACTOR = 5`) fragmentos para que la
  deduplicación por publicación y el recorte a `publicado` no dejen la lista por
  debajo de `limite`. Es una **heurística** documentada: un `DISTINCT ON
  (publicacion_id)` en SQL queda como optimización futura (no se toca el SQL de
  FT00017).
- Un rango `desde > hasta` **no** es error: responde `200` con `resultados` vacío
  (`SearchFilterSql` es coherente). Parámetros inválidos (`q` ausente/en blanco,
  `categoria` no válida, fecha no ISO, `limite` no entero/fuera de rango) responden
  `400` **sin cuerpo tipado** (el contrato de error es FT00030).
- El composition root **cablea por primera vez** el proveedor de embeddings
  locales (`E5EmbeddingProvider`, FT00015) de forma **condicional**: si falta el
  modelo, el tokenizador o su configuración, se registra un aviso y se arranca
  **sin** proveedor. `/buscar` se registra **solo** si hay pool JDBC y proveedor;
  sin ninguno de los dos la ruta es `404` y `/health` sigue operativo. El proveedor
  y el pool se cierran **una sola vez** en `ApplicationStopped`.
- La inferencia ONNX y la lectura JDBC (bloqueantes) se ejecutan fuera del hilo de
  eventos HTTP (`Dispatchers.IO`); el SQL está **parametrizado** (lote con
  `ANY(?)`, sin concatenar entrada).

## Alternativas consideradas

- **Devolver el fragmento (con su `referencia`/snippet) en vez de la publicación**:
  el cliente quiere la tarjeta del feed y el detalle; devolver el fragmento crudo
  añadiría un contrato nuevo y rompería la coherencia con el feed. Diferido.
- **Filtrar `publicado` en memoria tras recuperar**: serviría de nada evitar SQL
  pero arriesgaría mezclar estados; el filtro vive en el repositorio como en FT00026.
- **Definir un `SearchRepository` nuevo con su propio SQL**: duplicaría la lectura
  `publicacion ⋈ resumen` y el mapeo de FT00026; se **extiende** `FeedRepository`
  con una lectura por lote.
- **Paginación con `total` (`pagina`/`tamanoPagina` como el feed)**: no es
  significativa sobre ANN; se elige `limite` top-k.
- **Rango `desde > hasta` ⇒ `400`**: añade una regla que el dominio no exige; el
  filtro SQL ya devuelve vacío, así que se responde `200`.
- **Cablear el proveedor de embeddings de forma incondicional (fail-fast del
  arranque si falta el modelo)**: obligaría a tener el modelo (~118 MB) para
  arrancar y a romper el arranque en entornos parciales; se cablea condicional.
- **Exponer `consulta` como nombre del parámetro**: se solapa con la entidad de
  dominio `Consulta` del chat; se usa `q` en el query string.

## Consecuencias

- Habilita el contrato que consumirá la UI de búsqueda (FT00032+) y reutiliza el
  contrato y el mapeo del feed/detalle.
- El feed saldrá **vacío** y `/buscar` **vacío** en producción hasta que exista un
  cableado del pipeline de resumen y del indexado del corpus completo
  (FT00020–FT00023 y operación): gap de planificación, no un fallo.
- `ARCHITECTURE.md`, `CONSTRAINTS.md` (§«API pública: búsqueda»), las skills
  `ktor-backend-architecture`/`rag-datapublico` y `docs/desarrollo-local.md`
  registran la nueva ruta y el wiring condicional.
- Sin migración (`V1`…`V5` intactas), sin dependencias Gradle nuevas y sin CORS,
  *rate limiting*, OpenAPI ni cuerpo de error consistente (FT00029/FT00030).
- La prueba real de la búsqueda (extremo a extremo con modelo y PostgreSQL) es
  **opt-in** (`DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`); el gate corre sin red,
  BD ni modelo con dobles deterministas.
