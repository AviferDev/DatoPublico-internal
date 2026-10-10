# Feature Implementation Spec: Almacenamiento vectorial en pgvector

## Source Feature

- `id`: pgvector-indexado
- `ft_id`: FT00016 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ~7 ficheros de producto, por debajo del límite de 30)
- `area`: rag
- `depends_on`: bootstrap-postgres-pgvector (FT00003, `accepted`), embeddings-locales-onnx (FT00015, `accepted`)
- `status`: not_started (al planificar; ya existe la rama `feat/ft00016-pgvector-indexado` con el *claim* de esta sesión)
- `source`: `feature_list.json`

> **Encaje con FT00008/FT00014/FT00015.** La tabla `fragmento` ya existe sin
> columna de embedding (FT00008, migración `V2`); el chunking (`ArticleChunker`) y
> el modelo de dominio `rag.Fragment` son de FT00014; el proveedor de embeddings
> (`EmbeddingProvider` + `E5EmbeddingProvider`, 384 dims normalizadas, E5 int8
> vía ONNX/CPU) es de FT00015. FT00016 añade **la columna `embedding vector(384)`,
> su índice HNSW** y el **almacenamiento/consulta por similitud** sobre
> `fragmento`, como **librería de `:backend`** (no se cablea en el arranque). No
> incluye recuperación híbrida con filtros (FT00017) ni evaluación (FT00018).

## Goal

Añadir en `:backend` el **almacenamiento vectorial** de los fragmentos en
PostgreSQL + **pgvector**: una migración Flyway que añade `fragmento.embedding
vector(384)` y su **índice HNSW** (distancia coseno), y la **extensión del
repositorio de fragmentos** para (a) **guardar/actualizar** el embedding de un
fragmento y (b) **consultar por similitud** (los `k` fragmentos más cercanos a un
vector de consulta, con su distancia). Es la tarea `0.3-T03` de
`docs/roadmap.md`.

La feature es una **librería verificable de forma aislada**: los tests del gate
comprueban el contrato SQL de la migración y la conversión pura del literal
vectorial; una prueba **opt-in** contra PostgreSQL real (patrón `DB_LIVE_TEST=1`)
guarda vectores sintéticos y comprueba la consulta por similitud y el uso del
índice HNSW. La generación real de embeddings (ONNX) y la composición
proveedor + repositorio se difieren a FT00017/el cableado.

## Non-Goals

- **Recuperación híbrida** (filtro SQL por metadatos —fecha, categoría, sección,
  organismo— combinado con similitud) y *top-k* con umbrales/reranking → FT00017.
- **Evaluación** de recuperación (precision/recall, recall@k, MRR) → FT00018.
- **Índice GIN/trigram sobre texto** o cualquier índice no vectorial.
- **Calibrar o inyectar el contador real de tokens en `ArticleChunker`** (ver
  *Risks*: los documentos durables lo asignan a FT00016, pero queda **diferido**;
  no se toca el chunker ni el modelo E5 en esta feature).
- **Cambiar el modelo de embeddings** (`-base`, 768 dims) o su proveedor: la
  columna se fija en **384** (ver *Risks*).
- **Generar embeddings** aquí: FT00016 no construye `E5EmbeddingProvider` ni
  descarga el modelo; el `EmbeddingProvider` de FT00015 queda intacto.
- **Wiring**: `Application.kt`, `ingesta/job/`, `ingesta/backfill/` intactos; sin
  endpoints ni UI.
- **Editar migraciones ya aplicadas** (`V1`, `V2`): solo se añade `V3`.
- **Lectura/escritura del vector por API pública o DTO** de `:shared`.

## Job Story

Cuando construyo el RAG base sobre el BOE,
quiero guardar los embeddings de los fragmentos en pgvector y consultar los más
similares a un vector,
para poder recuperar fragmentos relevantes (FT00017) sin reescribir SQL ni
duplicar la lógica de similitud, aprovechando el índice HNSW.

## Users And Permissions

- Desarrollador / feature posterior de recuperación (interno): invoca el
  repositorio de fragmentos desde código de `:backend`, sobre el pool de
  `infra/Database`. Sin cuentas, sin datos personales, sin autenticación. La
  conexión usa `POSTGRES_*` (fuente única, fail-fast si falta la contraseña). La
  prueba real contra la base es **opt-in** (`DB_LIVE_TEST=1`).

## Acceptance Scenarios

### Scenario 1: guardar y consultar por similitud devuelve el fragmento más cercano

Given una base PostgreSQL con las migraciones aplicadas, una publicación y varios
fragmentos persistidos (`FragmentRepository.save`) y sus embeddings guardados
(`FragmentRepository.saveEmbedding`),
When se llama `findNearest(queryEmbedding, limit)` con un vector igual o muy
próximo al de un fragmento conocido,
Then ese fragmento aparece **primero**, con su `reference`/`content` íntegros y su
`distance` (coseno) menor que la de los demás.

### Scenario 2: el índice HNSW existe y lo usa la consulta

Given las migraciones aplicadas,
When se inspecciona el catálogo (`pg_indexes`/`pg_class`) y se ejecuta
`EXPLAIN` sobre la consulta de vecinos más cercanos,
Then existe un índice `hnsw` con `vector_cosine_ops` sobre `fragmento(embedding)`
y el plan **usa ese índice** (`Index Scan using … hnsw`, comprobado con
`SET enable_seqscan = off` para tablas pequeñas; ver *Risks*).

### Scenario 3: los fragmentos sin embedding se excluyen

Given una publicación con dos fragmentos guardados, solo uno con embedding,
When se consulta `findNearest`,
Then el fragmento sin embedding **no** se devuelve (la consulta filtra
`embedding IS NOT NULL`); no hay error.

### Scenario 4: validación de dimensión y límite (fail-fast)

Given un vector de consulta o de escritura cuya longitud no es **384**, o un
`limit < 1`,
When se llama `saveEmbedding`/`findNearest`,
Then falla con un **mensaje claro** (`IllegalArgumentException`) **antes** de
tocar la base de datos; no se escriben filas corruptas.

### Scenario 5: contrato SQL de la migración V3

Given el classpath de test,
When se lee `V3__fragmento_embedding.sql`,
Then declara `ALTER TABLE fragmento ADD COLUMN embedding vector(384)` y un índice
`USING hnsw (embedding vector_cosine_ops)`, y **no** anticipa lo diferido (no hay
filtros de metadatos de FT00017 ni cambios en `V1`/`V2`).

### Scenario 6: el gate sigue sin red ni base de datos

Given el runner de CI sin PostgreSQL y Docker parado,
When se ejecuta `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew
detekt` o `.harness/init.sh`,
Then todo está en verde; la prueba real de BD se omite sin `DB_LIVE_TEST=1` (un
`@Test` que no abre conexión) y no se descarga ningún artefacto.

## Repository Research

### Files Inspected

- `.harness/feature_list.json` (FT00016; FT00003/FT00015 `accepted`),
  `PROGRESS.md` (estado verificado: FT00014/FT00015 fusionadas), `docs/feature-ids.md`,
  `docs/roadmap.md` §0.3.0 (`0.3-T03`), `docs/technical-discovery.md` (Data and
  Storage: `fragmento` con embedding, índices vectoriales + filtros),
  `docs/domain-model.md` (Fragmento), `CONTEXT.md` §Embedding, `ARCHITECTURE.md`
  (frontera Backend → PostgreSQL; `rag/`), `CONSTRAINTS.md` (§«Persistencia y base
  de datos», §«Embeddings locales», §«RAG / fragmentación», §«Estilo», §«Nombres»),
  `docs/adr/0003`, `docs/adr/0010` y la skill **`rag-datapublico`** §1–§3.
- Producto `..`:
  - `backend/src/main/resources/db/migration/V1__esquema_base.sql` (extensión
    `vector` ya habilitada) y `V2__persistencia_publicaciones.sql` (tabla
    `fragmento` **sin** embedding y con `UNIQUE (publicacion_id, orden)`).
  - `backend/src/main/kotlin/…/backend/persistence/FragmentRepository.kt`
    (`FragmentRepository` + `FragmentEntity` + `FragmentRepositoryJdbc` + `save`/
    `listByPublication`; `Fragment.toEntity()`).
  - `backend/src/main/kotlin/…/backend/persistence/Jdbc.kt` (helpers `queryRows`,
    `executeUpdate`), `PublicationRepository.kt` (patrón de repositorio),
    `infra/Database.kt` / `infra/DatabaseConfig.kt` (pool Hikari + `POSTGRES_*`).
  - `backend/src/main/kotlin/…/backend/rag/Fragment.kt` y
    `rag/embeddings/EmbeddingProvider.kt` (`FloatArray`, 384 dims normalizadas).
  - `backend/src/test/kotlin/…/backend/persistence/MigrationSqlTest.kt` (contrato
    SQL sin BD) y `PublicationPersistenceLiveTest.kt` (opt-in `DB_LIVE_TEST=1`,
    lee `POSTGRES_*` del entorno o de `.env`).
  - `gradle/libs.versions.toml` (`postgresql = 42.7.14`, HikariCP) y
    `config/detekt/detekt.yml`.
- Git: rama `feat/ft00016-pgvector-indexado` con `chore(FT00016): claim`
  (`a2df1f3`) ya en `origin`; sin PR abierto.

### Existing Patterns To Follow

- **Migraciones Flyway** versionadas, **nunca** se edita una aplicada; nombres
  `V<n>__<slug>.sql` en `backend/src/main/resources/db/migration/`.
- **JDBC + HikariCP sin ORM**: interfaz + `...Entity` + `...RepositoryJdbc` en el
  mismo fichero, SQL parametrizado y helpers de `Jdbc.kt` (`queryRows`,
  `executeUpdate`); cada método abre y cierra su conexión (autocommit).
- **Config por entorno con fail-fast** (`DatabaseConfig.fromEnv`); `POSTGRES_*`
  como fuente única; sin credenciales versionadas.
- **Tests opt-in por variable de entorno** fuera del gate (`DB_LIVE_TEST=1`,
  patrón `BOE_LIVE_TEST`/`EMBEDDING_LIVE_TEST`); un `@Test` que se omite sin
  abrir conexión.
- **Componentes puros** + test en espejo del paquete (patrón `VectorMathTest`,
  `ArticleChunkerTest`); `MagicNumber` desactivado pero constantes documentadas.
- **Identificadores en inglés; KDoc/comentarios en castellano**; **estilo MUST**:
  un solo `return`, sin `else if`, funciones ≤40 líneas; reutilizar antes de
  escribir.

### Current Gaps

- La tabla `fragmento` **no** tiene columna de embedding ni índice vectorial.
- `FragmentRepository` no sabe escribir/leer vectores ni consultar por similitud.
- No existe ninguna conversión entre `FloatArray` y el literal `vector` de
  pgvector (formato `[v1,v2,…]`).
- El driver PostgreSQL ya está en `implementation` (FT00008), por lo que **no**
  hacen falta dependencias nuevas para escribir el tipo `vector` si se usa el
  *cast* `?::vector`.

## Technical Approach

### Migración `V3__fragmento_embedding.sql` (nueva; `V1`/`V2` intactas)

```sql
-- Migración de indexado vectorial (FT00016).
-- Añade la columna de embedding a `fragmento` y su índice HNSW (distancia
-- coseno). V1/V2 no se editan (regla de migraciones Flyway).

ALTER TABLE fragmento ADD COLUMN embedding vector(384);

CREATE INDEX fragmento_embedding_hnsw_idx
    ON fragmento USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);
```

- `embedding` es **nullable**: los fragmentos se vectorizan después de crearse
  (FT00017/el indexado real), y `findNearest` filtra `embedding IS NOT NULL`.
- **Coseno** (`vector_cosine_ops`, operador `<=>`): los vectores de FT00015 están
  **normalizados** (L2 ≈1), así que la distancia coseno ordena igual que el
  producto interno y es la que documenta la skill RAG.
- Parámetros HNSW por defecto (`m = 16`, `ef_construction = 64`) documentados;
  `ef_search` de consulta es una palanca de FT00017.
- `ALTER TABLE ADD COLUMN` nullable sin default es **solo metadato** en PostgreSQL
  ≥11; la creación del índice HNSW es la operación pesada (ver *Risks*).

### `persistence/PgVector.kt` (puro, testable sin BD)

Objeto con la conversión entre `FloatArray` y el literal textual de pgvector:

- `const val DIMENSIONS = 384`.
- `fun toLiteral(embedding: FloatArray): String` — valida `size == DIMENSIONS`
  (`require`, fail-fast) y produce `"[v1,v2,…]"` con `Float.toString()` (formato
  **independiente de *locale***, siempre `.` como separador decimal).
- `fun parse(literal: String?): FloatArray?` — `null`/en blanco → `null`; recorta
  `[`/`]`, separa por `,`, convierte a `Float` y valida `size == DIMENSIONS`.

No depende de librerías nuevas; evita depender de `org.postgresql.util.PGobject`
en la firma del repositorio.

### `persistence/FragmentRepository.kt` (modify: ampliar; entidad intacta)

Se **conserva** `FragmentEntity` (sin array) y `Fragment.toEntity()` de FT00014
(añadir `FloatArray` a una `data class` rompería `equals`/`hashCode`). Se amplía la
interfaz con dos operaciones y un tipo de resultado:

```kotlin
interface FragmentRepository {
    fun save(fragment: FragmentEntity): FragmentEntity
    fun listByPublication(publicationId: String): List<FragmentEntity>

    /** Guarda/actualiza el embedding del fragmento (publicationId, order). */
    fun saveEmbedding(publicationId: String, order: Int, embedding: FloatArray): Boolean

    /** Fragmentos más cercanos a [queryEmbedding] por distancia coseno. */
    fun findNearest(queryEmbedding: FloatArray, limit: Int): List<FragmentMatch>
}

/** Fragmento recuperado por similitud, con su distancia coseno (menor = mejor). */
data class FragmentMatch(val fragment: FragmentEntity, val distance: Double)
```

SQL de `FragmentRepositoryJdbc` (parametrizado; reutiliza `queryRows`):

```sql
-- saveEmbedding: UPDATE … RETURNING id  (isNotEmpty() ⇒ true)
UPDATE fragmento SET embedding = ?::vector
WHERE publicacion_id = ? AND orden = ?
RETURNING id

-- findNearest
SELECT id, publicacion_id, orden, referencia, contenido,
       embedding <=> ?::vector AS distance
FROM fragmento
WHERE embedding IS NOT NULL
ORDER BY embedding <=> ?::vector
LIMIT ?
```

- El vector se enlaza como **texto + cast** `?::vector` (`setString`), lo que
  evita `PGobject` y mantiene la API del repositorio sobre `FloatArray`.
- `findNearest` valida `limit >= 1` (`require`) y la dimensión vía `PgVector`;
  ordena por distancia ascendente (`ORDER BY` + `LIMIT` habilita el uso del índice
  HNSW).
- KDoc de la interfaz: `saveEmbedding` requiere que el fragmento exista
  (la fila la crea `save`, FT00008/FT00014); **sin** filtros de metadatos (FT00017).

**Estilo**: funciones con `return` único y ≤40 líneas; KDoc en castellano;
identificadores en inglés; constantes documentadas.

### Sin wiring y sin anticipar lo diferido

`Application.kt`, `ingesta/job/`, `ingesta/backfill/`, `ArticleChunker`, el
proveedor de embeddings (FT00015), `:shared`, `:composeApp`, `.github/workflows/ci.yml`
e `init.sh` quedan **intactos**. No se añaden dependencias de Gradle (el driver
PostgreSQL y HikariCP ya están en `implementation`).

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico/backend` se abrevia
como `…/backend`:

- `backend/src/main/resources/db/migration/V3__fragmento_embedding.sql` — create;
  `embedding vector(384)` + índice HNSW (coseno).
- `backend/src/main/kotlin/…/backend/persistence/PgVector.kt` — create; literal
  `[v1,v2,…]` ↔ `FloatArray`, dimensión 384 (puro).
- `backend/src/main/kotlin/…/backend/persistence/FragmentRepository.kt` — modify;
  `saveEmbedding`, `findNearest` y `FragmentMatch` (`FragmentEntity` intacta).
- `backend/src/test/kotlin/…/backend/persistence/PgVectorTest.kt` — create; gate,
  round-trip, nulos, dimensión y *locale*.
- `backend/src/test/kotlin/…/backend/persistence/FragmentEmbeddingMigrationSqlTest.kt`
  — create; gate, contrato SQL de V3 (y no-anticipación de FT00017).
- `backend/src/test/kotlin/…/backend/persistence/FragmentEmbeddingPersistenceLiveTest.kt`
  — create; **opt-in** `DB_LIVE_TEST=1` (guardar/consultar + índice).
- `docs/desarrollo-local.md` — modify; sección de indexado vectorial (migración V3,
  prueba opt-in de similitud e índice).

Harness (privado): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0011` + índice,
`.agents/skills/rag-datapublico/SKILL.md`, `feature_list.json`, `PROGRESS.md`
(ver *Durable Documentation Impact*).

**Sin cambios** en `ArticleChunker`, `rag/embeddings/`, `infra/`, el resto de
`persistence/`, `Application.kt`, `ingesta/`, `:shared`, `:composeApp`, la raíz
del build, `settings.gradle.kts`, CI e `init.sh`.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI.

## Durable Documentation Impact

- `ARCHITECTURE.md`: update — `fragmento` gana `embedding vector(384)` + índice
  HNSW; `persistence/` añade `PgVector` y la consulta por similitud; subrayar que
  queda **sin filtros** (FT00017) y **sin wiring**.
- `CONSTRAINTS.md`: update — nueva sección o ampliación de «RAG / fragmentación»
  con MUST: la columna es `embedding vector(384)` **nullable**; índice **HNSW**
  `vector_cosine_ops`; el vector se guarda como **literal con cast `?::vector`**
  (sin ORM); `PgVector` valida la dimensión 384 (fail-fast); los fragmentos sin
  embedding se excluyen; **nunca** se edita una migración aplicada; la prueba real
  de similitud/índice es **opt-in** (`DB_LIVE_TEST=1`).
- `AGENTS.md`: not needed — no cambia el flujo ni el camino de arranque.
- **ADR `docs/adr/0011-pgvector-columna-hnsw.md`** (recomendado): decisión durable «almacenamiento
  vectorial en pgvector: columna `vector(384)` nullable + índice HNSW coseno,
  literal textual con cast y `PgVector` puro; sin recuperación híbrida (FT00017)».
  El planner **no** lo crea; lo escribe el implementador/orquestador e inscribe el
  índice en `docs/adr/README.md`.
- `.agents/skills/rag-datapublico/SKILL.md`: update — §3 «Estado actual del
  producto (FT00016)» (columna, índice, API del repositorio, verificación opt-in).
- `docs/desarrollo-local.md` (producto): update — migración V3, consulta de
  similitud y comando opt-in `DB_LIVE_TEST=1`.
- `feature_list.json`/`PROGRESS.md`: los cierra el orquestador.

## Implementation Plan

1. Escribir `V3__fragmento_embedding.sql` (`ADD COLUMN embedding vector(384)` +
   índice HNSW coseno) y verificar con `:backend:flywayMigrate`/`:flywayInfo`.
2. Crear `PgVector.kt` (puro) y `PgVectorTest` (gate): round-trip, nulos,
   dimensión y *locale*.
3. Ampliar `FragmentRepository` con `saveEmbedding`, `findNearest` y
   `FragmentMatch` sobre `FragmentRepositoryJdbc` (cast `?::vector`).
4. Añadir `FragmentEmbeddingMigrationSqlTest` (contrato SQL de V3, gate).
5. Añadir `FragmentEmbeddingPersistenceLiveTest` (opt-in `DB_LIVE_TEST=1`):
   guardar vectores sintéticos, comprobar el más cercano, excluir el sin
   embedding y verificar el uso del índice con `EXPLAIN`.
6. Ejecutar el gate sin red ni BD y la prueba real opt-in; actualizar
   `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0011 + índice, skill RAG y
   `docs/desarrollo-local.md`. `PROGRESS.md`/`feature_list.json` los cierra el
   orquestador.

## Implementation Tasks

- [ ] `V3__fragmento_embedding.sql`: `embedding vector(384)` + HNSW
      `vector_cosine_ops` (`m = 16`, `ef_construction = 64`).
- [ ] `PgVector.kt`: `DIMENSIONS`, `toLiteral`, `parse` (puros, fail-fast).
- [ ] `FragmentRepository`: `saveEmbedding`, `findNearest`, `FragmentMatch`
      (SQL `?::vector`; entidad y `toEntity()` intactas).
- [ ] `PgVectorTest` (gate): round-trip, nulo/blanco, dimensión inválida, `.` de
      decimal.
- [ ] `FragmentEmbeddingMigrationSqlTest` (gate): contrato SQL de V3 sin
      anticipar FT00017.
- [ ] `FragmentEmbeddingPersistenceLiveTest` (opt-in): vecino más cercano,
      exclusión de nulos e índice HNSW usado.
- [ ] Docs durables: ARCHITECTURE, CONSTRAINTS, ADR 0011 + índice, skill RAG,
      `docs/desarrollo-local.md`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red ni BD (obligatorio)**: `./gradlew :backend:test --rerun-tasks` →
  BUILD SUCCESSFUL con `PgVectorTest` y `FragmentEmbeddingMigrationSqlTest` en
  verde (0 fallos) y el resto de `:backend` intacto. `./gradlew build --no-daemon
  -PskipClient` (incluye `:backend:detekt` y `:cpdCheck`), `./gradlew test`,
  `./gradlew detekt` y `env -u JAVA_HOME .harness/init.sh` → exit 0.
- **Offline confirmado**: el test opt-in se **omite** sin `DB_LIVE_TEST` (un
  `@Test` que no abre conexión); ningún test del gate toca la BD ni la red.
- **Migración (BD arriba)**:
  ```sh
  cp .env.example .env && docker compose up -d
  ./gradlew :backend:flywayMigrate && ./gradlew :backend:flywayInfo
  ```
  Esperado: `V1`+`V2`+`V3` en **Success**; `\d fragmento` muestra `embedding
  vector(384)`; `\di` (o `pg_indexes`) muestra `fragmento_embedding_hnsw_idx`
  `USING hnsw (embedding vector_cosine_ops)`.
- **Escenarios 1–4 (opt-in, fuera del gate y de la CI)**:
  ```sh
  DB_LIVE_TEST=1 ./gradlew :backend:test --tests '*FragmentEmbeddingPersistenceLiveTest'
  ```
  Esperado: el fragmento más cercano al vector de consulta aparece primero con la
  `distance` menor; el fragmento sin embedding se excluye; un vector de dimensión
  ≠384 o `limit < 1` falla antes de tocar la BD. Escenario 2: `EXPLAIN` con
  `SET enable_seqscan = off` muestra `Index Scan using fragmento_embedding_hnsw_idx`.
- **E2E**: no aplica — librería sin flujo de usuario ni endpoint nuevo (el repo no
  tiene un comando E2E; el cliente es Compose Multiplatform).
- `init.sh` (harness): **no** se modifica; no se le añade ningún paso de BD.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con `PgVectorTest`/`FragmentEmbeddingMigrationSqlTest`
  (recuento, 0 fallos) y del gate (`build -PskipClient`, `test`, `detekt`, `init.sh`
  exit 0).
- `flywayInfo` con `V1`+`V2`+`V3` en `Success`; `\d fragmento` y `pg_indexes` con
  el índice HNSW.
- Salida del test **opt-in**: orden por similitud y `distance` del vecino más
  cercano; exclusión de fragmentos nulos; plan `EXPLAIN` que usa el índice HNSW.
- Ficheros del commit `FT00016`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `V3` + `PgVector` + `FragmentRepository` y sus tests;
      **sin** filtros híbridos (FT00017), **sin** evaluación (FT00018), **sin**
      generar embeddings ni cableado en `Application.kt`/job/backfill; `V1`/`V2`,
      `ArticleChunker`, `rag/embeddings/` y `infra/` intactos.
- [ ] Escenarios 1–6 pasan; **todo el gate corre sin red ni BD** y el opt-in se
      omite sin `DB_LIVE_TEST`.
- [ ] La columna es `embedding vector(384)` **nullable** e índice HNSW
      `vector_cosine_ops`; `findNearest` filtra los nulos y ordena por distancia.
- [ ] `PgVector` valida la dimensión 384 (fail-fast); el literal usa `.` decimal
      (sin *locale*); el *binding* usa cast `?::vector`.
- [ ] La prueba real (similitud + índice) se ejecutó y está etiquetada como
      opt-in (límite documentado).
- [ ] `return` único, sin `else if`, funciones ≤40 líneas, KDoc en castellano con
      identificadores en inglés.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0011 + índice, skill RAG,
      `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] No unrelated product behavior or extra feature work was added.

## Risks / Open Questions

- **El índice puede no usarse en tablas pequeñas.** Con pocos fragmentos, el
  planificador puede preferir un *seq scan*. Mitigación: la prueba opt-in ejecuta
  `EXPLAIN` con `SET enable_seqscan = off` y comprueba `Index Scan using
  fragmento_embedding_hnsw_idx`; **confirmar este límite** (el uso real con
  volumen llega con el corpus de FT00017). La mera existencia del índice también
  se verifica por catálogo.
- **Calibración del contador real de tokens en `ArticleChunker` (diferida).**
  `CONSTRAINTS.md` (§«RAG / fragmentación») y la skill `rag-datapublico` (§2)
  asignan a FT00016 la inyección/calibración del contador real de FT00015. Sin
  embargo, `countTokens` vive en un `TextTokenizer` **internal** y no está expuesto
  por `EmbeddingProvider`; exponerlo y cablearlo es un cambio acotado pero ajeno al
  alcance de almacenamiento vectorial que pide esta feature. **Se difiere**: no se
  toca `ArticleChunker`. El orquestador debería **confirmar** que se traslada a una
  feature nueva (p. ej. un `FTxxxxx` de calibración) o a FT00017.
- **Binding del tipo `vector`.** Se propone `setString(literal)` + `?::vector`
  (sin dependencia nueva). Si el driver no aceptara el cast en algún caso, el
  *fallback* es `setObject(PGobject)` (el driver ya está en `implementation`).
  Verificarlo en el test opt-in.
- **Formato del literal y *locale*.** `Float.toString()` es independiente del
  *locale* (siempre `.`); el test debe cubrir explícitamente que no aparece `,`
  decimal (riesgo típico en entornos `es_ES`).
- **Dimensión fija 384.** Cambiar de modelo (`-base`, 768) exigiría **nueva
  migración** (no se edita `V3`) y **reindexar**; documentado en ADR 0011/skill.
- **Coste de crear el índice HNSW.** En tablas grandes la construcción consume
  memoria/tiempo; en esta feature la tabla está vacía o casi, pero el **backfill**
  de vectores (FT00017/producción) debe valorar crear el índice tras la carga o
  ajustar `maintenance_work_mem`.
- **`FloatArray` en `data class`.** Se evita meter el embedding en `FragmentEntity`
  (rompería `equals`/`hashCode`); `FragmentMatch` encapsula fragmento + distancia.
  No comparar arrays con `assertEquals` en los tests.
- **Sin recuperación todavía.** FT00016 guarda y consulta por similitud **sin**
  filtros de metadatos; si FT00017 necesita reutilizar `findNearest` con filtros,
  extenderá el repositorio sin duplicar SQL.
