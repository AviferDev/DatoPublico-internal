# Feature Implementation Spec: Recuperación híbrida de fragmentos

## Source Feature

- `id`: recuperacion-hibrida
- `ft_id`: FT00017 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ~11 ficheros de producto, por debajo del límite de 30)
- `area`: rag
- `depends_on`: pgvector-indexado (FT00016, `accepted`)
- `status`: not_started (al planificar)
- `source`: `feature_list.json`
- `claim`: rama `feat/ft00017-recuperacion-hibrida` reclamada en `origin` (claim
  `b9560ad`); el usuario nombra la feature explícitamente y confirma el claim.
  FT00016 sigue en el **PR #17 abierto** (stack de PRs): esta rama parte de
  `feat/ft00016-pgvector-indexado`, aún **no** fusionada en `main`.

> **Encaje con FT00014/FT00015/FT00016.** El chunking (`ArticleChunker`) y el
> modelo `rag.Fragment` son de FT00014; el proveedor de embeddings
> (`EmbeddingProvider` + `E5EmbeddingProvider`, 384 dims normalizadas) es de
> FT00015; la columna `fragmento.embedding vector(384)`, el índice HNSW coseno,
> `PgVector` y `FragmentRepository.findNearest`/`saveEmbedding` son de FT00016.
> FT00016 **difirió expresamente** a FT00017 «la generación real de embeddings
> (ONNX) y la composición proveedor + repositorio»; FT00017 es el único
> propietario de esa pieza, así que **se incluye aquí** un indexado mínimo (ver
> *Goal* y *Non-Goals*), además de la recuperación híbrida (filtros SQL por
> metadatos + similitud).

## Goal

Añadir en `:backend`, como **librería sin wiring**, la **recuperación híbrida**
(tarea `0.3-T04`): dada una consulta y unos **filtros por metadatos** (rango de
fechas, categoría, sección, organismo), devolver los fragmentos más relevantes
combinando el filtro SQL sobre `publicacion` con la **similitud vectorial** sobre
`fragmento.embedding`, ordenados por distancia coseno ascendente. La
recuperación compone el `EmbeddingProvider` (vectoriza la consulta con el prefijo
`query: `) y el `FragmentRepository` (consulta por vecinos más cercanos con
filtro).

Para cerrar el aplazamiento de FT00016 y poder probar la recuperación con datos
reales, se incluye además un **indexado mínimo**: dada una `Publicacion`, el
`FragmentIndexer` la fragmenta (`ArticleChunker`), persiste cada fragmento
(`FragmentRepository.save`) y guarda su embedding de *pasaje*
(`EmbeddingProvider.embedPassage` + `saveEmbedding`). Es idempotente por el
*upsert* de `(publicacion_id, orden)`.

## Non-Goals

- **Evaluación** de recuperación (precision/recall, recall@k, MRR) → FT00018.
- **Generación de resúmenes/chat** y cualquier IA remota → FT00019+.
- **Endpoints/API/UI** de búsqueda o chat → FT00026+ (el `SearchFilter` no es un
  DTO de transporte: eso llegará con el endpoint de búsqueda).
- **Wiring en el arranque**: `Application.kt`, `ingesta/job/`,
  `ingesta/backfill/` intactos; el indexado del **corpus completo** por lotes
  (job/backfill) es una feature posterior de operación.
- **Reranking** (cross-encoder, fusión híbrida léxica BM25/trigram, `ef_search`
  tuning): la puerta queda abierta (skill RAG §4), pero no entra aquí.
- **Cambiar** el modelo de embeddings, la dimensión (384) o la migración `V3`;
  **no** se editan migraciones aplicadas ni se crea ninguna nueva.
- **Añadir** índice léxico (GIN/trigram) o columnas de metadatos nuevas.
- **Optimización de batching** de inferencia y control de coste (N100): el
  indexado procesa fragmento a fragmento con la API ya existente.
- **Leer el embedding almacenado por API pública/DTO** de `:shared`.

## Job Story

Cuando construyo el RAG base sobre el BOE,
quiero recuperar fragmentos relevantes de una consulta **acotados por metadatos**
(fecha, categoría, sección, organismo) y ordenados por similitud,
para poder alimentar resúmenes y chat con fragmentos correctos y trazables sin
reimplementar SQL ni duplicar la lógica de similitud.

## Users And Permissions

- Desarrollador / feature posterior de RAG (interno): invoca el indexado y la
  recuperación desde código de `:backend`, sobre el pool de `infra/Database` y el
  proveedor de FT00015. Sin cuentas, sin datos personales, sin autenticación.
  Conexión derivada de `POSTGRES_*` (fail-fast si falta la contraseña). Las
  pruebas reales contra PostgreSQL y contra el modelo E5 son **opt-in**
  (`DB_LIVE_TEST=1` / `EMBEDDING_LIVE_TEST=1`).

## Acceptance Scenarios

### Scenario 1: filtro de categoría devuelve solo fragmentos de esa categoría

Given una base con publicaciones de categorías distintas, fragmentos con
embedding y un `SearchFilter(category = …)`,
When se llama `HybridSearch.search(query, filter, limit)` (o
`FragmentRepository.findNearest(queryEmbedding, filter, limit)`),
Then solo se devuelven fragmentos cuya publicación cumple la categoría, ordenados
por distancia coseno ascendente; se excluyen los de otras categorías y los que no
tienen embedding.

### Scenario 2: filtro de rango de fechas (inclusivo)

Given publicaciones en fechas distintas,
When se filtra con `publishedFrom`/`publishedTo`,
Then solo se devuelven fragmentos de publicaciones con
`publishedFrom <= fecha_publicacion <= publishedTo`, ordenados por relevancia.

### Scenario 3: filtro vacío equivale a la similitud pura (FT00016)

Given `SearchFilter()` (sin campos),
When se llama `findNearest(queryEmbedding, filter, limit)`,
Then se comporta como el `findNearest(queryEmbedding, limit)` de FT00016 (todos
los fragmentos con embedding, ordenados por distancia), sin romper su contrato.

### Scenario 4: varios filtros combinados con AND

Given un `SearchFilter` con fecha **y** sección **y** organismo,
When se recupera,
Then la cláusula SQL combina todas las condiciones con `AND` y se aplican todas
(solo pasan los fragmentos que cumplen todas).

### Scenario 5: fail-fast antes de tocar la base de datos

Given un `limit < 1`, un vector de consulta de dimensión ≠ 384 o una fecha de
filtro no ISO-8601,
When se llama `search`/`findNearest`,
Then falla con `IllegalArgumentException` y mensaje claro **antes** de abrir la
conexión.

### Scenario 6: indexar una publicación (fragmentos + embeddings)

Given una `Publicacion` con texto, un `EmbeddingProvider` y un
`FragmentRepository`,
When se llama `FragmentIndexer.index(publication)`,
Then cada fragmento del chunker se persiste (`save`) y su embedding de *pasaje*
se guarda (`saveEmbedding`); la operación es **idempotente** (reejecutarla
sobrescribe por `(publicacion_id, orden)` sin duplicar) y devuelve el número de
fragmentos indexados.

### Scenario 7: el gate sigue sin red ni base de datos ni modelo

Given el runner de CI sin PostgreSQL, sin Docker y sin el modelo E5,
When se ejecuta `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew
detekt` o `.harness/init.sh`,
Then todo está en verde; las pruebas opt-in se omiten sin abrir conexión ni
descargar artefactos.

### Scenario 8: extremo a extremo real (opt-in)

Given PostgreSQL migrado (Docker) y, para el caso real, el modelo E5 descargado,
When se ejecuta el test opt-in `DB_LIVE_TEST=1` (y `EMBEDDING_LIVE_TEST=1`),
Then la publicación de prueba se indexa y la recuperación filtrada devuelve el
fragmento relevante primero con su `distance`, cumpliendo los filtros.

## Repository Research

### Files Inspected

- `.harness/feature_list.json` (FT00017; FT00016 `accepted`), `PROGRESS.md`,
  `docs/feature-ids.md`, `docs/roadmap.md` §0.3.0 (`0.3-T04`),
  `docs/technical-discovery.md` (Data and Storage: índices vectoriales **y
  filtros SQL por metadatos**), `docs/domain-model.md` (Fragmento/Consulta),
  `CONTEXT.md` (Fragmento, Embedding), `ARCHITECTURE.md` (frontera Backend →
  PostgreSQL; `rag/`), `CONSTRAINTS.md` (§«Almacenamiento vectorial»,
  §«Embeddings locales», §«RAG / fragmentación», §«Estilo», §«Nombres»),
  `docs/specs/pgvector-indexado.md` (FT00016), skill **`rag-datapublico`** §3–§4.
- Producto `..`:
  - `backend/src/main/kotlin/…/backend/persistence/FragmentRepository.kt`
    (`FragmentRepository` + `FragmentEntity` + `FragmentRepositoryJdbc` + `save`/
    `listByPublication`/`saveEmbedding`/`findNearest`/`FragmentMatch`; SQL de
    `findNearest` con `?::vector`, `embedding IS NOT NULL`).
  - `backend/src/main/kotlin/…/backend/persistence/PgVector.kt` (`DIMENSIONS`,
    `toLiteral`, `parse` — este último **sin consumidor de producción** aún;
    deuda Low de FT00016).
  - `backend/src/main/kotlin/…/backend/persistence/Jdbc.kt` (`queryRows`,
    `executeUpdate`), `PublicationRepository.kt` (`PublicationEntity` con
    `fecha_publicacion`/`seccion`/`categoria`/`organismo`; índices SQL por esos
    campos en `V2`).
  - `backend/src/main/kotlin/…/backend/rag/Fragment.kt` (`Fragment`, sin sufijo),
    `rag/chunking/ArticleChunker.kt` (`chunk(Publicacion): List<Fragment>`),
    `rag/embeddings/EmbeddingProvider.kt` (`embedQuery`/`embedPassage`, 384 dims),
    `rag/embeddings/E5EmbeddingProvider.kt` (`from(modelPath, tokenizerPath)`).
  - `backend/src/main/kotlin/…/backend/ingesta/publicacion/Publicacion.kt`
    (modelo con `fechaPublicacion`, `seccion`, `categoria`, `organismo`, `texto`).
  - `backend/src/main/resources/db/migration/V2__persistencia_publicaciones.sql`
    (`publicacion` con índices `fecha_publicacion`/`seccion`/`categoria`/
    `organismo`; `fragmento` con `UNIQUE (publicacion_id, orden)`) y `V3`
    (`embedding vector(384)` + HNSW).
  - `backend/src/test/kotlin/…/backend/persistence/PgVectorTest.kt`,
    `FragmentEmbeddingPersistenceLiveTest.kt` (patrón opt-in `DB_LIVE_TEST=1` con
    vectores sintéticos y `EXPLAIN`), `rag/embeddings/E5EmbeddingLiveTest.kt`
    (patrón opt-in `EMBEDDING_LIVE_TEST=1`).
- Git: rama `feat/ft00017-recuperacion-hibrida` (claim `b9560ad`) ya en `origin`;
  sin PR propio; PR #17 (FT00016) abierto.

### Existing Patterns To Follow

- **Repositorios JDBC + HikariCP sin ORM** en `persistence/` (interfaz +
  `...Entity` + `...RepositoryJdbc` en el mismo fichero, SQL parametrizado,
  `queryRows`/`executeUpdate`); cada método abre y cierra su conexión.
- **Migraciones Flyway** versionadas; lo diferido no se anticipa (aquí **no** hay
  migración nueva).
- **Componentes puros** + test en espejo del paquete (`PgVectorTest`,
  `ArticleChunkerTest`); `MagicNumber` desactivado pero constantes documentadas.
- **Tests opt-in por variable de entorno** fuera del gate (`DB_LIVE_TEST=1`,
  `EMBEDDING_LIVE_TEST=1`); sin la variable, el `@Test` se omite sin abrir
  sockets ni cargar el modelo.
- **Identificadores en inglés; KDoc/comentarios en castellano**; **estilo MUST**:
  un solo `return`, sin `else if`, funciones ≤40 líneas; reutilizar antes de
  escribir (`toEntity`, `PgVector`, `ArticleChunker`, `EmbeddingProvider`).

### Current Gaps

- `FragmentRepository.findNearest` **no** acepta filtros de metadatos (no hay
  `JOIN publicacion` ni `WHERE` dinámico).
- No existe ninguna composición de `EmbeddingProvider` + `FragmentRepository`
  (ni para indexar *pasajes* ni para vectorizar la *consulta*).
- No existe un tipo que represente el filtro por metadatos ni un constructor de
  SQL puro y testeable sin BD.
- `PgVector.parse` no tiene consumidor de producción (deuda Low de FT00016).

## Technical Approach

### `rag/retrieval/SearchFilter.kt` (puro, valor interno, sin sufijo)

```kotlin
/** Filtro de metadatos de una recuperación; todos los campos son opcionales. */
data class SearchFilter(
    val publishedFrom: String? = null,  // fecha ISO-8601 inclusiva
    val publishedTo: String? = null,    // fecha ISO-8601 inclusiva
    val category: CategoriaDto? = null,
    val section: SeccionBoeDto? = null,
    val organization: String? = null,
)
```

No es `@Serializable` ni DTO (modelo interno): el DTO de la API de búsqueda
llegará con FT00028. Sin prefijos ni sufijo (`CONSTRAINTS.md` §«Nombres»).

### `rag/retrieval/SearchFilterSql.kt` (puro, testable sin BD)

Objeto con dos funciones puras y coherentes en orden (documentado):
`whereClause(filter): String` (cláusula ` AND …` con placeholders `?` sobre el
alias `p` de `publicacion`, o `""`) y `parameters(filter): List<String>` (valores
enlazados en el mismo orden). Condiciones: `p.fecha_publicacion >= ?::date`,
`p.fecha_publicacion <= ?::date`, `p.categoria = ?`, `p.seccion = ?`,
`p.organismo = ?`. Las fechas se validan con `LocalDate.parse` (fail-fast
`IllegalArgumentException` si no son ISO-8601) y se enlazan como **texto con cast
`?::date`** (mismo patrón que `?::vector`), así todos los parámetros son `String`.

### `persistence/FragmentRepository.kt` (modify: ampliar; entidad intacta)

Se **conserva** `FragmentEntity`/`FragmentMatch`/`save`/`listByPublication`/
`saveEmbedding` y el `findNearest(queryEmbedding, limit)` de FT00016 (que pasa a
delegar en el filtrado con `SearchFilter()`). Se añade:

```kotlin
/** Vecinos más cercanos que cumplen [filter] (fecha/categoría/sección/organismo). */
fun findNearest(queryEmbedding: FloatArray, filter: SearchFilter, limit: Int): List<FragmentMatch>

/** Embedding almacenado de (publicationId, order), o `null` si no existe. */
fun findEmbedding(publicationId: String, order: Int): FloatArray?
```

SQL filtrado (parametrizado; `{filterClause}` = `SearchFilterSql.whereClause`):

```sql
SELECT f.id, f.publicacion_id, f.orden, f.referencia, f.contenido,
       f.embedding <=> ?::vector AS distance
FROM fragmento f
JOIN publicacion p ON p.id = f.publicacion_id
WHERE f.embedding IS NOT NULL {filterClause}
ORDER BY f.embedding <=> ?::vector
LIMIT ?
```

Orden de *binding*: literal de consulta (`distance`) → parámetros del filtro →
literal de consulta (`ORDER BY`) → `limit`. `findEmbedding` selecciona
`embedding::text` y lo interpreta con `PgVector.parse` (cierra la deuda Low de
FT00016 y verifica el *round-trip* real). `findNearest` valida dimensión vía
`PgVector.toLiteral` y `limit >= 1` (fail-fast antes de tocar la BD). El `JOIN` a
`publicacion` solo aporta los filtros; sin filtros el resultado coincide con
FT00016.

### `rag/retrieval/HybridSearch.kt` (servicio, sin Ktor)

```kotlin
/** Recuperación híbrida: vectoriza la consulta y busca con filtros de metadatos. */
class HybridSearch(
    private val embeddingProvider: EmbeddingProvider,
    private val fragmentRepository: FragmentRepository,
) {
    fun search(query: String, filter: SearchFilter = SearchFilter(), limit: Int = DEFAULT_LIMIT): List<FragmentMatch>
}
```

`search` valida `query.isNotBlank()` y `limit >= 1` (fail-fast), vectoriza la
consulta (`embedQuery`, prefijo `query: `) y delega en
`fragmentRepository.findNearest(vector, filter, limit)`. No conoce Ktor, SQL ni
ONNX.

### `rag/indexing/FragmentIndexer.kt` (servicio, sin Ktor; cierra FT00016)

```kotlin
/** Indexa una publicación: fragmenta, persiste y guarda el embedding de cada fragmento. */
class FragmentIndexer(
    private val embeddingProvider: EmbeddingProvider,
    private val fragmentRepository: FragmentRepository,
    private val chunker: ArticleChunker = ArticleChunker(),
) {
    fun index(publication: Publicacion): Int
}
```

`index` fragmenta (`chunker.chunk`), y por cada `Fragment`: `save(fragment.toEntity())`
(mapea con la extensión pura ya existente) y `saveEmbedding(publicationId, order,
embeddingProvider.embedPassage(content))`. Devuelve el número de fragmentos.
Idempotente por el *upsert* de `(publicacion_id, orden)`. **Sin** batching, sin
transacción multi-repositorio y sin wiring.

### Sin wiring y sin anticipar lo diferido

`Application.kt`, `ingesta/`, `ArticleChunker`, `rag/embeddings/`, `infra/`,
`:shared`, `:composeApp`, `.github/workflows/ci.yml` e `init.sh` quedan
**intactos**. Sin dependencias Gradle nuevas. Sin migración nueva. Dirección de
dependencia: los servicios (`rag/retrieval`, `rag/indexing`) dependen de
`persistence.FragmentRepository` y `rag.embeddings.EmbeddingProvider` (capa
superior → repositorio, correcto); `persistence` ya depende de `rag.Fragment`
(dominio). Se **extiende** la interfaz existente en `persistence/` (patrón de
FT00008/FT00016) en vez de declarar un *port* nuevo, para no duplicar.

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico/backend` se abrevia
como `…/backend`:

- `backend/src/main/kotlin/…/backend/rag/retrieval/SearchFilter.kt` — create;
  valor del filtro de metadatos (interno, sin sufijo).
- `backend/src/main/kotlin/…/backend/rag/retrieval/SearchFilterSql.kt` — create;
  cláusula SQL + parámetros (puro, fail-fast de fechas).
- `backend/src/main/kotlin/…/backend/rag/retrieval/HybridSearch.kt` — create;
  servicio `search` (embedQuery + findNearest filtrado).
- `backend/src/main/kotlin/…/backend/rag/indexing/FragmentIndexer.kt` — create;
  indexado mínimo (chunk + save + embedPassage + saveEmbedding).
- `backend/src/main/kotlin/…/backend/persistence/FragmentRepository.kt` — modify;
  `findNearest(queryEmbedding, filter, limit)` + `findEmbedding`; el 2-arg
  delega.
- `backend/src/test/kotlin/…/backend/rag/retrieval/SearchFilterSqlTest.kt` —
  create; gate, cláusula/parámetros/orden y fechas inválidas.
- `backend/src/test/kotlin/…/backend/rag/retrieval/HybridSearchTest.kt` — create;
  gate, con dobles (embedQuery una vez; pasa vector+filtro+límite; fail-fast).
- `backend/src/test/kotlin/…/backend/rag/indexing/FragmentIndexerTest.kt` —
  create; gate, con dobles (persiste y vectoriza; idempotencia).
- `backend/src/test/kotlin/…/backend/rag/retrieval/HybridSearchLiveTest.kt` —
  create; **opt-in** `DB_LIVE_TEST=1` (filtros reales sobre PostgreSQL con
  vectores sintéticos).
- `backend/src/test/kotlin/…/backend/rag/indexing/FragmentIndexerLiveTest.kt` —
  create; **opt-in** `DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1` (modelo E5 real +
  PostgreSQL).
- `docs/desarrollo-local.md` — modify; sección de recuperación híbrida e indexado
  (comandos opt-in).

Harness (privado): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0012` + índice,
`.agents/skills/rag-datapublico/SKILL.md`, `feature_list.json`, `PROGRESS.md`
(ver *Durable Documentation Impact*).

**Sin cambios** en migraciones (`V1`/`V2`/`V3`), `PgVector`, `ArticleChunker`,
`rag/embeddings/`, `infra/`, `Application.kt`, `ingesta/`, `:shared`,
`:composeApp`, la raíz del build, CI e `init.sh`.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI.

## Durable Documentation Impact

- `ARCHITECTURE.md`: update — `rag/` gana `retrieval/` (`SearchFilter`,
  `HybridSearch`) e `indexing/` (`FragmentIndexer`); la frontera Backend →
  PostgreSQL incorpora el `JOIN publicacion` con filtros de metadatos; subrayar
  que sigue **sin wiring**.
- `CONSTRAINTS.md`: update — nueva sección **«Recuperación híbrida e indexado»**
  con MUST: filtros solo por metadatos existentes (fecha/categoría/sección/
  organismo) y parametrizados; `findNearest` filtra nulos y ordena por distancia;
  la composición proveedor + repositorio vive en `rag/` (no en `persistence/`);
  el indexado es idempotente por *upsert*; pruebas reales **opt-in**; sin
  reranking ni índice léxico en esta feature.
- `AGENTS.md`: not needed — no cambia el flujo ni el camino de arranque.
- **ADR `docs/adr/0012-recuperacion-hibrida-filtros.md`** (recomendado): decisión
  durable «recuperación híbrida: filtros SQL parametrizados por metadatos
  combinados con similitud vectorial (`JOIN publicacion`), `SearchFilter` puro e
  indexado mínimo proveedor + repositorio; sin wiring ni reranking». El planner
  **no** lo crea; lo escribe el implementador/orquestador y lo inscribe en
  `docs/adr/README.md`.
- `.agents/skills/rag-datapublico/SKILL.md`: update — §4 «Estado actual del
  producto (FT00017)» (filtros, `HybridSearch`, `FragmentIndexer`, verificación
  opt-in).
- `docs/desarrollo-local.md` (producto): update — comandos opt-in de recuperación
  híbrida e indexado.
- `feature_list.json`/`PROGRESS.md`: los cierra el orquestador.

## Implementation Plan

1. Crear `SearchFilter` y `SearchFilterSql` (puros) y su test de gate
   (`SearchFilterSqlTest`).
2. Ampliar `FragmentRepository` con `findNearest(queryEmbedding, filter, limit)`
   (JOIN + WHERE dinámico + *binding* ordenado) y `findEmbedding`; hacer que el
   2-arg delegue en el filtrado.
3. Crear `HybridSearch` (servicio) y su test de gate con dobles
   (`HybridSearchTest`).
4. Crear `FragmentIndexer` (servicio) y su test de gate con dobles
   (`FragmentIndexerTest`).
5. Añadir los tests opt-in `HybridSearchLiveTest` (`DB_LIVE_TEST=1`) y
   `FragmentIndexerLiveTest` (`DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`).
6. Ejecutar el gate sin red ni BD y las pruebas reales opt-in; actualizar
   `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0012 + índice, skill RAG y
   `docs/desarrollo-local.md`. `PROGRESS.md`/`feature_list.json` los cierra el
   orquestador.

## Implementation Tasks

- [ ] `SearchFilter`: campos fecha/categoría/sección/organismo (todos opcionales).
- [ ] `SearchFilterSql`: `whereClause` + `parameters` (orden documentado;
      `?::date`; fail-fast de fecha no ISO).
- [ ] `FragmentRepository`: `findNearest(queryEmbedding, filter, limit)` y
      `findEmbedding` (el 2-arg delega con `SearchFilter()`).
- [ ] `HybridSearch`: `search(query, filter, limit)` (embedQuery + findNearest;
      fail-fast de `query`/`limit`).
- [ ] `FragmentIndexer`: `index(publication)` (chunk + save + embedPassage +
      saveEmbedding; idempotente).
- [ ] `SearchFilterSqlTest` y `HybridSearchTest` y `FragmentIndexerTest` (gate,
      dobles deterministas, sin red/BD).
- [ ] `HybridSearchLiveTest` (`DB_LIVE_TEST=1`) y `FragmentIndexerLiveTest`
      (`DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`).
- [ ] Docs durables: ARCHITECTURE, CONSTRAINTS, ADR 0012 + índice, skill RAG,
      `docs/desarrollo-local.md`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red ni BD (obligatorio)**: `./gradlew :backend:test --rerun-tasks` →
  BUILD SUCCESSFUL con `SearchFilterSqlTest`, `HybridSearchTest` y
  `FragmentIndexerTest` en verde (0 fallos) y el resto de `:backend` intacto.
  `./gradlew build --no-daemon -PskipClient` (incluye `:backend:detekt` y
  `:cpdCheck`), `./gradlew test`, `./gradlew detekt` y
  `env -u JAVA_HOME .harness/init.sh` → exit 0.
- **Offline confirmado**: los tests opt-in se **omiten** sin `DB_LIVE_TEST` /
  `EMBEDDING_LIVE_TEST` (un `@Test` que no abre conexión ni carga el modelo);
  ningún test del gate toca la BD, la red o los artefactos.
- **Escenarios 1–4 (opt-in, fuera del gate y de la CI)**:
  ```sh
  cp .env.example .env && docker compose up -d
  ./gradlew :backend:flywayMigrate
  DB_LIVE_TEST=1 ./gradlew :backend:test --tests '*HybridSearchLiveTest'
  ```
  Esperado: con filtro de categoría/fecha/sección solo se devuelven los fragmentos
  que cumplen el filtro, ordenados por `distance` ascendente; sin filtro el
  resultado coincide con FT00016; los fragmentos sin embedding se excluyen.
- **Escenario 8 (extremo a extremo real, opt-in)**:
  ```sh
  backend/tools/download-embedding-model.sh
  DB_LIVE_TEST=1 EMBEDDING_LIVE_TEST=1 ./gradlew :backend:test --tests '*FragmentIndexerLiveTest'
  ```
  Esperado: la publicación se indexa con el modelo E5 real y la consulta devuelve
  el fragmento relevante primero; el filtro de metadatos se aplica.
- **E2E**: no aplica — librería sin flujo de usuario ni endpoint nuevo (el repo no
  tiene comando E2E; el cliente es Compose Multiplatform).
- `init.sh` (harness): **no** se modifica; no se le añade ningún paso de BD ni de
  modelo.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con los tests nuevos de gate (recuento, 0
  fallos) y del gate (`build -PskipClient`, `test`, `detekt`, `init.sh` exit 0).
- Salida de los tests opt-in: filtros aplicados y orden por `distance`; indexado
  con el modelo real y recuperación del fragmento relevante primero.
- Ficheros del commit `FT00017`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `rag/retrieval/` + `rag/indexing/` +
      `FragmentRepository` y sus tests; **sin** evaluación (FT00018), **sin**
      resúmenes/chat (FT00019+), **sin** endpoints/UI ni wiring en
      `Application.kt`/job/backfill; migraciones, `PgVector`, `ArticleChunker`,
      `rag/embeddings/` e `infra/` intactos.
- [ ] Escenarios 1–8 pasan; **todo el gate corre sin red, BD ni modelo** y los
      opt-in se omiten sin sus variables.
- [ ] `findNearest(queryEmbedding, filter, limit)` filtra por metadatos vía
      `JOIN publicacion`, excluye nulos y ordena por distancia; el 2-arg de
      FT00016 sigue funcionando.
- [ ] Fail-fast: `limit < 1`, dimensión ≠384 y fecha no ISO fallan **antes** de
      tocar la BD; SQL parametrizado (sin concatenar entrada de usuario).
- [ ] El indexado es idempotente por *upsert* y guarda embedding de *pasaje*
      (`embedPassage`); la consulta usa `embedQuery`.
- [ ] `return` único, sin `else if`, funciones ≤40 líneas, KDoc en castellano con
      identificadores en inglés; `@SerialName` no aplica (sin tipos `@Serializable`).
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0012 + índice, skill RAG,
      `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] No unrelated product behavior or extra feature work was added.

## Risks / Open Questions

- **Alcance del indexado.** FT00017 incluye un `FragmentIndexer` **mínimo** para
  cerrar el aplazamiento explícito de FT00016 y poder probar la recuperación con
  el modelo real; **no** indexa el corpus completo (eso es operación/job/backfill).
  Si el orquestador prefiere separarlo, puede dividirse en `FT00017-PTn` o crear
  una feature nueva; el spec lo acota para no bloquear.
- **Uso del índice HNSW con filtros.** Con `JOIN` + `WHERE`, PostgreSQL puede
  elegir un plan que combine el filtro por metadatos y el índice vectorial (o un
  *seq scan* en tablas pequeñas). La verificación opt-in debe **inspeccionar el
  plan** (`EXPLAIN`) y documentar el comportamiento; el ajuste de `ef_search` y la
  elección de plan con volumen real quedan para la evaluación (FT00018) y la
  operación.
- **Selectividad del filtro.** Un filtro muy selectivo sobre un corpus grande
  puede degradar el uso del índice HNSW; sin datos reales (corpus de FT00018) no
  se optimiza. La puerta a *reranking*/fusión léxica queda abierta.
- **`organismo` exacto.** El filtro por organismo es igualdad exacta (valores del
  BOE); la normalización/case-insensitive es una decisión posterior de la API de
  búsqueda (FT00028), no de esta feature.
- **Fechas como `String` ISO.** `SearchFilter` usa cadenas ISO-8601 (convención
  interna ya existente en `PublicationRepository`); la conversión a `LocalDate`
  y el fail-fast viven en `SearchFilterSql`. Si la API futura usa otro formato, se
  adapta en su capa.
- **Dirección de dependencia `rag/` → `persistence/`.** La composición
  proveedor + repositorio vive en `rag/` (servicio) y extiende la interfaz de
  `persistence/` (patrón FT00008/FT00016) en vez de declarar un *port* nuevo; se
  documenta para no duplicar SQL.
- **`PgVector.parse`.** Se consume en `findEmbedding` (lectura usada por las
  pruebas reales y disponible para reranking/evaluación), cerrando la deuda Low
  de FT00016; si finalmente no se usara, quedaría como deuda Low aceptada.
- **Coste del indexado en N100.** Vectorizar fragmento a fragmento es lento; el
  batching y el control de coste quedan fuera de esta feature (operación).
- **`FloatArray` y `equals`.** `FragmentMatch` encapsula el fragmento y la
  distancia (sin embedding); no comparar arrays con `assertEquals` en los tests.
