# ADR 0012: Recuperación híbrida con filtros SQL parametrizados por metadatos + similitud vectorial e indexado mínimo

## Estado

Aceptado (2026-10-10). Decisión del dueño del proyecto. No supersede ningún ADR.

## Contexto

El pipeline RAG ya tiene el chunking (`ArticleChunker`, FT00014), el proveedor de
embeddings (`EmbeddingProvider`/`E5EmbeddingProvider`, FT00015) y el
almacenamiento vectorial (`fragmento.embedding vector(384)` + índice HNSW coseno,
`PgVector` y `FragmentRepository.findNearest`/`saveEmbedding`, FT00016). Falta la
tarea `0.3-T04`: **recuperar** fragmentos relevantes acotados por **metadatos**
(fecha, categoría, sección, organismo) y, para poder probar la recuperación con
datos reales, **cerrar el aplazamiento** de FT00016 (generar los embeddings de los
fragmentos y componer proveedor + repositorio).

Restricciones: PostgreSQL + pgvector con **JDBC + HikariCP sin ORM** (ADR 0003);
migraciones Flyway versionadas que **nunca** se editan una vez aplicadas; el gate y
la CI corren **sin red ni base de datos**; los vectores son de **384 dims** (fijos
por el modelo E5 `-small`); `:backend` es una **librería sin wiring** hasta que la
API (FT00026+) y la operación la consuman.

## Decisión

- **Filtro de metadatos como valor interno puro.**
  `rag/retrieval/SearchFilter` (sin sufijo: no es `@Serializable` ni DTO) agrupa
  los campos opcionales `publishedFrom`/`publishedTo` (fechas ISO-8601 como
  `String`), `category` (`CategoriaDto`), `section` (`SeccionBoeDto`) y
  `organization` (`String`).
- **Traducción SQL pura y coherente.** `rag/retrieval/SearchFilterSql` expone
  `whereClause(filter)` (cláusula ` AND …` sobre el alias `p` de `publicacion`, o
  `""`) y `parameters(filter)` (valores en el **mismo orden documentado**:
  `publishedFrom`, `publishedTo`, `category`, `section`, `organization`). Todo va
  **parametrizado** con `?` (nunca se concatena entrada); las fechas se validan con
  `LocalDate.parse` y se enlazan como **texto con *cast* `?::date`** (mismo patrón
  que `?::vector`), así que todos los parámetros son `String`. Fecha no ISO-8601 =
  **fail-fast** (`IllegalArgumentException`) antes de tocar la base de datos.
- **Repositorio ampliado, sin ORM.** `FragmentRepository` gana
  `findNearest(queryEmbedding, filter, limit)` (un `JOIN publicacion` + `WHERE`
  dinámico, `embedding IS NOT NULL`, `ORDER BY <=>` y `LIMIT`) y
  `findEmbedding(publicationId, order)` (lee `embedding::text` y lo interpreta con
  `PgVector.parse`, cerrando su uso de producción). El `findNearest` de 2
  argumentos de FT00016 **delega** con `SearchFilter()`, conservando su contrato.
  Orden de *binding*: literal de consulta (`distance`) → parámetros del filtro →
  literal de consulta (`ORDER BY`) → `limit`. `limit >= 1` y dimensión 384 =
  **fail-fast**.
- **Servicio de recuperación.** `rag/retrieval/HybridSearch` (sin Ktor, sin SQL ni
  ONNX) valida `query.isNotBlank()` y `limit >= 1`, vectoriza la consulta con
  `embedQuery` (prefijo `query: `) y delega en `findNearest(vector, filter, limit)`.
- **Indexado mínimo.** `rag/indexing/FragmentIndexer` fragmenta con
  `ArticleChunker`, persiste cada fragmento (`save(fragment.toEntity())`) y guarda
  su embedding de *pasaje* (`embedPassage` + `saveEmbedding`); es **idempotente**
  por el *upsert* de `(publicacion_id, orden)`. **Sin** *batching*, sin transacción
  multi-repositorio y sin indexar el corpus completo.
- **Librería sin wiring.** `Application.kt`, job, backfill, `ArticleChunker`,
  `rag/embeddings/`, `infra/`, `:shared` y `:composeApp` quedan intactos; **sin**
  migración nueva y **sin** dependencias Gradle nuevas. Dirección de dependencia:
  los servicios de `rag/` dependen de `persistence.FragmentRepository` y
  `rag.embeddings.EmbeddingProvider` (capa superior → repositorio, correcto).
- **Sin reranking ni índice léxico.** La puerta a *reranking*/fusión BM25 queda
  abierta (skill RAG §4) pero **no** entra aquí; tampoco se añade índice
  GIN/trigram ni columnas de metadatos nuevas.
- **Verificación *offline* + opt-in.** El gate cubre `SearchFilterSqlTest`,
  `HybridSearchTest` y `FragmentIndexerTest` con dobles deterministas, **sin red ni
  BD**. Las pruebas reales son **opt-in**: `HybridSearchLiveTest` (`DB_LIVE_TEST=1`,
  vectores sintéticos) y `FragmentIndexerLiveTest` (`DB_LIVE_TEST=1` +
  `EMBEDDING_LIVE_TEST=1`, modelo E5 real), fuera de `build`/`test`/`init.sh`/CI.

## Alternativas consideradas

- **Port nuevo en `rag/` en vez de ampliar `FragmentRepository`.** Descartado:
  duplicaría SQL; se sigue el patrón de FT00008/FT00016 (extender la interfaz
  existente en `persistence/`).
- **`SearchFilter` como DTO de transporte `@Serializable`.** Descartado: el DTO de
  la API de búsqueda llegará con FT00028; aquí es un valor interno sin sufijo.
- **Concatenar fechas en la cláusula.** Descartado: SQL parametrizado siempre; las
  fechas viajan como texto con `?::date`.
- **`findNearest` filtrado como método aparte con su propio SQL.** Descartado: se
  reutiliza una plantilla con un marcador (`{filterClause}`) que se sustituye por
  la cláusula pura, manteniendo un único SQL.
- **Indexar el corpus completo / *batching* aquí.** Descartado: es operación
  (job/backfill) y una feature posterior; FT00017 solo cierra el aplazamiento con
  un indexado mínimo.
- **Añadir `ef_search`/reranking ya.** Descartado: se decide con datos reales en la
  evaluación (FT00018) y la operación.

## Consecuencias

- **Habilita** FT00018 (evaluación de recuperación: precision/recall, recall@k,
  MRR) y FT00019+ (resúmenes/chat con fragmentos trazables), reutilizando
  `SearchFilter`/`HybridSearch` y el indexado.
- **Cuesta** un paso opt-in para verificar filtros y el extremo a extremo real; el
  gate no lo cubre (limitación aceptada). El indexado fragmento a fragmento es
  lento en el N100 (*batching* diferido).
- **Riesgo abierto**: con `JOIN` + `WHERE`, PostgreSQL puede elegir *seq scan* en
  tablas pequeñas; la verificación opt-in inspecciona el plan (`EXPLAIN`) y el
  ajuste con volumen real queda para FT00018/operación. Un filtro muy selectivo
  puede degradar el uso del índice HNSW.
- **Riesgo abierto**: el filtro por `organismo` es igualdad exacta (valores del
  BOE); la normalización *case-insensitive* es una decisión posterior de la API de
  búsqueda (FT00028).
- **Documentación/código**: `ARCHITECTURE.md` (`rag/retrieval/` y `rag/indexing/` y
  la frontera Backend → PostgreSQL con el `JOIN`), regla MUST en `CONSTRAINTS.md`
  §«Recuperación híbrida e indexado», estado actual en la skill `rag-datapublico`,
  sección en `docs/desarrollo-local.md` y este ADR.
- **Verificación**: `SearchFilterSqlTest`/`HybridSearchTest`/`FragmentIndexerTest`
  (gate) y `HybridSearchLiveTest`/`FragmentIndexerLiveTest` (opt-in).
