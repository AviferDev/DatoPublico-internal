# ADR 0011: Almacenamiento vectorial en pgvector con columna `vector(384)` nullable e índice HNSW coseno

## Estado

Aceptado (2026-10-10). Decisión del dueño del proyecto. No supersede ningún ADR.

## Contexto

El pipeline RAG (ingesta → chunking → embeddings ONNX → **pgvector** →
recuperación → generación con cita) ya tiene el chunking (`ArticleChunker`,
FT00014) y el proveedor de embeddings (`EmbeddingProvider`/`E5EmbeddingProvider`,
FT00015; E5 `-small` int8, **384 dims normalizadas**). Falta **almacenar** los
vectores y **consultarlos por similitud**. La tabla `fragmento` (FT00008, `V2`) no
tenía columna vectorial; la extensión `vector` ya se habilita en `V1`.

Restricciones: PostgreSQL + pgvector con **JDBC + HikariCP sin ORM** (ADR 0003);
migraciones Flyway versionadas que **nunca** se editan una vez aplicadas; el gate
y la CI corren **sin red ni base de datos**; los vectores son de **384 dims**
(fijos por el modelo E5 `-small`).

## Decisión

- **Columna nullable + índice HNSW coseno.** Migración nueva
  `V3__fragmento_embedding.sql`: `ALTER TABLE fragmento ADD COLUMN embedding
  vector(384)` (**nullable**) y `CREATE INDEX fragmento_embedding_hnsw_idx ON
  fragmento USING hnsw (embedding vector_cosine_ops) WITH (m = 16,
  ef_construction = 64)`. La columna es nullable porque los fragmentos se
  vectorizan **después** de crearse; `findNearest` filtra `embedding IS NOT NULL`.
  `vector_cosine_ops` (operador `<=>`) es la distancia que documenta la skill RAG
  (los vectores ya vienen normalizados L2).
- **Conversión pura en `persistence/PgVector`.** `DIMENSIONS = 384`,
  `toLiteral(FloatArray): String` y `parse(String?): FloatArray?`, con **fail-fast**
  (`IllegalArgumentException`) si la dimensión no es 384. Usa `Float.toString()`,
  **independiente del *locale*** (siempre `.` como separador decimal).
- **Repositorio ampliado, sin ORM ni `PGobject`.** `FragmentRepository` gana
  `saveEmbedding(publicationId, order, embedding): Boolean` (UPDATE … RETURNING
  `id`; la fila la crea `save`) y `findNearest(queryEmbedding, limit):
  List<FragmentMatch>` (ORDER BY `<=>` + LIMIT, excluyendo nulos). El vector se
  enlaza como **texto con *cast* `?::vector`** (`setString`), de modo que la API
  del repositorio sigue sobre `FloatArray`. `FragmentEntity` y `Fragment.toEntity()`
  quedan **intactos** (meter un `FloatArray` en la `data class` rompería
  `equals`/`hashCode`); `FragmentMatch` encapsula fragmento + distancia.
- **Librería sin wiring.** `Application.kt`, job, backfill, `ArticleChunker`,
  `rag/embeddings/` y `:shared` quedan intactos; **no** hay endpoints ni UI. **Sin**
  filtros de metadatos: la recuperación híbrida es de FT00017 y la evaluación, de
  FT00018.
- **Verificación *offline* + opt-in.** El gate cubre la conversión pura
  (`PgVectorTest`) y el contrato SQL de `V3` (`FragmentEmbeddingMigrationSqlTest`)
  **sin red ni BD**. La prueba real (vecino más cercano, exclusión de nulos e índice
  HNSW usado con `SET enable_seqscan = off`) es **opt-in** (`DB_LIVE_TEST=1`),
  fuera de `build`/`test`/`init.sh`/CI.
- **Contador real de tokens diferido.** La calibración/inyección del contador
  real de tokens de FT00015 en `ArticleChunker` **no** forma parte de FT00016
  (almacenamiento vectorial); queda diferida a una feature de calibración o a
  FT00017. No se expone `countTokens` por `EmbeddingProvider` ni se toca el chunker.

## Alternativas consideradas

- **`embedding` `NOT NULL`.** Descartado: obligaría a vectorizar en el mismo acto
  de crear el fragmento y a reescribir `save`; el indexado es un paso posterior
  (FT00017/backfill).
- **Índice IVFFlat.** Descartado: HNSW ofrece mejor recall/latencia sin entrenar
  centroides y es lo que fija la skill RAG.
- **Depender de `org.postgresql.util.PGobject` en la firma del repositorio.**
  Descartado: acopla la API al driver; el literal textual + `?::vector` no necesita
  dependencia nueva y mantiene la frontera sobre `FloatArray`.
- **Metadatos/filtros ya en `findNearest`.** Descartado: es recuperación híbrida
  (FT00017); aquí se acota a similitud pura.
- **Guardar el embedding dentro de `FragmentEntity`.** Descartado: `FloatArray` en
  una `data class` rompe `equals`/`hashCode`; `FragmentMatch` lo encapsula aparte.

## Consecuencias

- **Habilita** FT00017 (recuperación híbrida: filtros de metadatos + similitud) y
  FT00018 (evaluación) reutilizando `PgVector`, `findNearest` y `VectorMath`.
- **Cuesta** un paso opt-in para verificar la similitud/índice contra PostgreSQL
  real; el gate no lo cubre (limitación aceptada).
- **Riesgo abierto**: en tablas pequeñas el planificador puede preferir *seq scan*;
  la prueba opt-in fuerza `enable_seqscan = off` para comprobar el índice, pero el
  **uso real con volumen** llega con el corpus de FT00017.
- **Riesgo abierto**: cambiar de modelo (`-base`, 768 dims) exige **migración
  nueva** (no se edita `V3`) y **reindexar**; la construcción del índice HNSW en
  tablas grandes consume memoria/tiempo (valorar `maintenance_work_mem` o crear el
  índice tras el backfill).
- **Documentación/código**: `persistence/PgVector` y `findNearest` en
  `ARCHITECTURE.md`, regla MUST en `CONSTRAINTS.md` §«Almacenamiento vectorial»,
  estado actual en la skill `rag-datapublico`, sección en `docs/desarrollo-local.md`
  y este ADR.
- **Verificación**: `PgVectorTest`/`FragmentEmbeddingMigrationSqlTest` (gate, sin
  red ni BD) y `FragmentEmbeddingPersistenceLiveTest` (opt-in con PostgreSQL real).
