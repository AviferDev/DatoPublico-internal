# Feature Implementation Spec: Servicio de embeddings locales (ONNX)

## Source Feature

- `id`: embeddings-locales-onnx
- `ft_id`: FT00015 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ~17 ficheros de producto, por debajo del límite de 30)
- `area`: rag
- `depends_on`: chunking-articulos (FT00014, `accepted` y fusionada)
- `status`: not_started (al planificar)
- `source`: `feature_list.json`
- `claim`: rama `feat/ft00015-embeddings-locales-onnx` creada desde `origin/main`
  con un commit vacío `chore(FT00015): claim`; el usuario nombra la feature y
  confirma que el claim es de esta sesión.

> **Encaje con FT00014/FT00016.** `rag/Fragment` y `rag/chunking/ArticleChunker`
> ya existen (FT00014). FT00015 aporta el **proveedor de embeddings** (E5 int8
> vía ONNX/CPU) como **librería pura de `:backend`**, sin escribir en PostgreSQL,
> sin tocar la columna `embedding vector(384)` ni el índice HNSW (FT00016), sin
> recuperación (FT00017) y **sin wiring** en `Application.kt`. FT00015 cierra el
> **contador de tokens provisional** de FT00014 exponiendo el tokenizador real
> (para que FT00016 valide el presupuesto ≤512), pero **no** modifica
> `ArticleChunker` (ver *Non-Goals* y *Technical Approach*).

## Goal

Añadir en `:backend` un **servicio de embeddings locales** que vectoriza texto en
castellano con **`intfloat/multilingual-e5-small` cuantizado int8** ejecutado por
**ONNX Runtime en CPU**, detrás de una **interfaz de proveedor intercambiable**
(`EmbeddingProvider`). El servicio aplica los **prefijos obligatorios** `query: ` y
`passage: `, hace *mean pooling* con la máscara de atención, **normaliza** los
vectores (L2) y devuelve **384 dimensiones**. Es la tarea `0.3-T06`/`0.3-T02` de
`docs/roadmap.md`.

El proveedor es una **librería** (no se cablea en el arranque ni en el job): lo
consumirán FT00016 (indexado) y FT00017 (recuperación). Expone además el
**tokenizador real** (XLM-R) para cerrar la estimación provisional de FT00014 y
un `countTokens` reutilizable. El **modelo y el tokenizador no se commitean**: se
obtienen en un **paso explícito de red fuera del gate**, desde una ruta
configurable por entorno con **fail-fast**.

## Non-Goals

- **Columna `embedding vector(384)` + índice HNSW**, migración e *upsert* de
  vectores → FT00016. `persistence/` y Flyway **no** se tocan.
- **Recuperación híbrida / búsqueda** → FT00017; **evaluación** (precision/recall,
  recall@k, MRR) → FT00018.
- **Resúmenes, guardrails, chat, OpenCode** → FT00019+.
- **Wiring**: `Application.kt`, `ingesta/job/`, `ingesta/backfill/` intactos.
- **Modificar `ArticleChunker`/`CHARS_PER_TOKEN`**: el chunker se mantiene **puro**
  (sin dependencia nativa ONNX). FT00015 **expone** el contador real; la
  inyección/calibración en el chunker es responsabilidad de FT00016.
- **Batching real multi-secuencia** en ONNX: se ofrece `embedPassages(List)` como
  `map` secuencial; la optimización por lotes de inferencia queda para FT00016.
- **Descarga del modelo en `build`/`test`/`init.sh`/CI** y **commitear** el `.onnx`
  (~120 MB) o el `tokenizer.json`.
- **Cambiar el modelo por defecto** (`-base`, 768 dims): solo tras la interfaz.
- **Endpoints/UI, `:shared`, `:composeApp`** y la raíz del build (salvo el version
  catalog y `:backend/build.gradle.kts`, ver *Expected File Changes*).

## Job Story

Cuando implemento el RAG base sobre el BOE,
quiero vectorizar texto con un modelo multilingüe pequeño ejecutado localmente
(ONNX/CPU) detrás de una interfaz, con prefijos y vectores normalizados de 384
dimensiones,
para poder indexar fragmentos y consultas (FT00016/FT00017) y recuperarlos por
similitud coseno sin depender de un servicio de embeddings remoto.

## Users And Permissions

- Desarrollador / job de ingesta (interno): construye el proveedor desde una ruta
  local y lo invoca desde código de `:backend`. Sin cuentas, sin datos personales,
  sin autenticación. Sin red en el gate; el modelo se aprovisiona en un paso
  manual.

## Acceptance Scenarios

### Scenario 1: dimensión esperada del vector (384)

Given un `EmbeddingProvider` E5 construido (real u doble determinista),
When se vectoriza un texto como *query* y como *passage*,
Then se obtiene un `FloatArray` de **exactamente 384** elementos
(`provider.dimensions == 384`). El proveedor **rechaza con error claro** una salida
del modelo cuya última dimensión no sea 384.

### Scenario 2: similitud coseno mayor entre textos relacionados

Given dos pares de textos (*relacionados* vs *no relacionados*),
When se embeben como *passage* y se calcula la similitud coseno,
Then `cos(relacionados) > cos(no_relacionados)`. Con el **modelo real E5** se
verifica además con textos del dominio BOE (p. ej. dos paráfrasis de una
convocatoria frente a una norma no relacionada); con el **doble determinista** se
verifica la aritmética del pipeline.

### Scenario 3: prefijos obligatorios `query: `/`passage: `

Given un proveedor E5,
When se llama `embedQuery(texto)` o `embedPassage(texto)`,
Then la entrada que recibe el tokenizador real/observado es exactamente
`"query: " + texto` o `"passage: " + texto` (constantes documentadas).

### Scenario 4: vectores normalizados

Given un texto cualquiera,
When se embebe,
Then la **norma L2** del vector resultante es ≈1 (`abs(norma - 1) < 1e-4`); un
vector de norma 0 se devuelve sin dividir (guarda `EPS`).

### Scenario 5: fail-fast si faltan el modelo o el tokenizador

Given que `EMBEDDING_MODEL_PATH`/`EMBEDDING_TOKENIZER_PATH` apuntan a un fichero
inexistente o no se definen,
When se construye el proveedor,
Then falla con un **mensaje claro** (excepción tipada), sin *fallback* silencioso
a un modelo descargado ni a una ruta por defecto versionada.

### Scenario 6: cierre de recursos

Given un proveedor construido,
When se llama `close()` (una o dos veces),
Then se cierran la sesión ONNX y el tokenizador sin excepción (idempotente).

### Scenario 7: contador real de tokens (cierre del provisional de FT00014)

Given el tokenizador E5 real/doble,
When se llama `countTokens(texto)` sobre un texto conocido,
Then devuelve el número de tokens del modelo (≤512 para un `passage`), disponible
para que FT00016 valide el presupuesto sin recalcular la fórmula provisional.

## Repository Research

### Files Inspected

- `.harness/feature_list.json` (FT00015; FT00014 `accepted`),
  `PROGRESS.md` (estado verificado), `docs/feature-ids.md` (FT00015 registrado),
  `docs/roadmap.md` §0.3.0 (`0.3-T02`/`0.3-T06`), `docs/technical-discovery.md`
  (E5 int8, 384 dims, 512 tokens, prefijos), `docs/risks-and-open-questions.md`
  (int8 vs fp32, N100), `docs/domain-model.md` (Fragmento, Embedding),
  `CONTEXT.md` §Embedding, `docs/build-brief.md` §vectorización, `ARCHITECTURE.md`,
  `CONSTRAINTS.md`, `docs/adr/README.md`, y la skill **`rag-datapublico`** §2.
- Producto `..`:
  - `backend/src/main/kotlin/.../rag/Fragment.kt` (`Fragment` sin sufijo).
  - `backend/src/main/kotlin/.../rag/chunking/ArticleChunker.kt` (puro;
    `maxTokens=512`, `charsPerToken=3`, inyectables; `estimateTokens`).
  - `backend/src/main/kotlin/.../persistence/FragmentRepository.kt`
    (`FragmentEntity` **sin** columna de embedding).
  - `backend/src/main/kotlin/.../ingesta/sumario/BoeSumarioClient.kt` +
    `BoeSumarioHttpClient.kt` (patrón **interfaz + impl** y excepción tipada
    `BoeSumarioException`).
  - `backend/src/main/kotlin/.../infra/AppConfig.kt`,
    `ingesta/job/IngestionConfig.kt`, `ingesta/backfill/BackfillConfig.kt`
    (patrón de **config por entorno con fail-fast**).
  - Tests: `BoeSumarioLiveTest`/`BoePublicacionLiveTest`/`BackfillLiveTest`
    (**opt-in por variable de entorno**), `HighlightRankerTest`/`ArticleChunkerTest`
    (puros, sin red).
  - `gradle/libs.versions.toml` (version catalog) y `backend/build.gradle.kts`.
  - `config/detekt/detekt.yml` (`ReturnCount max=1`, `MagicNumber` off,
    `TooManyFunctions` 15).
  - Caché de Gradle local `~/.gradle/caches`: **ya contiene**
    `com.microsoft.onnxruntime:onnxruntime:1.20.0`,
    `ai.djl.huggingface:tokenizers:0.33.0` y `ai.djl:api:0.33.0` (resolubles sin
    red nueva).

### Existing Patterns To Follow

- **Interfaz + implementación** en la frontera externa (`BoeSumarioClient` +
  `BoeSumarioHttpClient`): el proveedor de embeddings es `EmbeddingProvider`
  (interfaz) + `E5EmbeddingProvider` (impl).
- **Excepción tipada** de frontera (`BoeSumarioException`) → `EmbeddingException`.
- **Config por entorno con fail-fast** y mensaje claro (`AppConfig`,
  `IngestionConfig`, `BackfillConfig`); sin defaults sensibles.
- **Tests opt-in por variable de entorno** fuera de `build`/`test`/`init.sh`
  (`BOE_LIVE_TEST`, `DB_LIVE_TEST`); un `@Test` que se omite sin abrir sockets.
- **Componentes puros** + test en espejo del paquete (`HighlightRanker`,
  `ArticleChunker`); `MagicNumber` desactivado, pero se documentan las constantes.
- **Identificadores en inglés; KDoc/comentarios en castellano**.
- **Estilo MUST**: `return` único, sin `else if`, funciones ≤40 líneas; reutilizar
  antes de escribir; crear la capa que falte.
- **Fixtures/recursos** en `src/test/resources` cuando aplica.

### Current Gaps

- **No existe** `rag/embeddings/` ni ningún proveedor/tokenizador.
- El version catalog **no** declara ONNX Runtime ni DJL; `:backend` no los usa.
- **No hay** directorio de modelos ni script de descarga; el modelo no está en el
  repo.
- `ArticleChunker` usa la **estimación provisional** de tokens (pendiente de
  cierre por FT00015).

## Technical Approach

### Paquete y tipos (capa `rag/embeddings/`)

Nuevo subpaquete `es.aviferdev.datopublico.backend.rag.embeddings`:

- `EmbeddingProvider.kt` (**público**): la interfaz intercambiable.
  ```kotlin
  interface EmbeddingProvider : AutoCloseable {
      val dimensions: Int
      fun embedQuery(text: String): FloatArray
      fun embedPassage(text: String): FloatArray
      fun embedPassages(texts: List<String>): List<FloatArray> = texts.map { embedPassage(it) }
  }
  ```
  `AutoCloseable` para liberar la sesión ONNX; `embedPassages` es un `map`
  secuencial (batching real diferido). KDoc: contrato (dims, normalización,
  prefijos, no bloquea).
- `TextTokenizer.kt` (**internal**): `interface TextTokenizer { fun tokenize(text): TokenizedInput; fun countTokens(text): Int }`
  + `data class TokenizedInput(val inputIds: LongArray, val attentionMask: LongArray)`.
  *Seam* inyectable para poder probar el pipeline sin artefactos.
- `EmbeddingModel.kt` (**internal**): `interface EmbeddingModel : AutoCloseable { val dimensions: Int; fun forward(inputIds: LongArray, attentionMask: LongArray): Array<FloatArray> }`
  (devuelve `last_hidden_state` `[seq, dims]`). *Seam* sobre la sesión ONNX.
- `VectorMath.kt` (**internal**, puro): `meanPool(lastHiddenState, attentionMask)`,
  `l2Normalize(v)`, `cosineSimilarity(a, b)`. Reutilizable por FT00017.
- `E5Tokenizer.kt` (**internal**): `TextTokenizer` real, envuelve
  `ai.djl.huggingface.tokenizers.HuggingFaceTokenizer`
  (`newInstance(Path)` sobre `tokenizer.json`, `optMaxLength(512)`,
  `optTruncation(true)`, `optPadding(false)`). `countTokens` = `encode(text).ids.size`.
- `OnnxEmbeddingModel.kt` (**internal**): `EmbeddingModel` real sobre
  `ai.onnxruntime.OrtEnvironment`/`OrtSession`. Crea los tensores `input_ids` y
  `attention_mask` (`int64`, `[1, seq]`), ejecuta y lee la salida
  `last_hidden_state` (`[1, seq, 384]`, *mean pooling* manual) o, si el export
  emite ya el vector agrupado `sentence_embedding` (`[1, 384]`), lo usa tal cual.
  Valida `dims == 384` y falla en claro si no. `close()` cierra la sesión.
- `E5EmbeddingProvider.kt` (**público**): composición
  `E5EmbeddingProvider(tokenizer, model, dimensions = DIMENSIONS)` con
  `embedQuery = embed(QUERY_PREFIX + text)`, `embedPassage = embed(PASSAGE_PREFIX + text)`;
  `embed` = tokenizar → `forward` → `meanPool` (o usar el agrupado) → `l2Normalize`
  → validar dims. Constantes `QUERY_PREFIX = "query: "`, `PASSAGE_PREFIX = "passage: "`,
  `DIMENSIONS = 384`, `MAX_TOKENS = 512`. Factory
  `E5EmbeddingProvider.from(modelPath: Path, tokenizerPath: Path, maxTokens: Int = MAX_TOKENS)`
  que carga los dos artefactos con fail-fast. `close()` cierra modelo y tokenizador.
- `EmbeddingConfig.kt` (**internal**): resuelve `EMBEDDING_MODEL_PATH`,
  `EMBEDDING_TOKENIZER_PATH`, `EMBEDDING_MAX_TOKENS` (default 512) del entorno;
  si faltan o no existen, lanza `EmbeddingException` con mensaje claro. No se
  cablea en el arranque.

**Estilo**: cada función con `return` único y ≤40 líneas (descomponer `embed`,
`forward` y los tests); KDoc en castellano; identificadores en inglés; `MagicNumber`
desactivado, pero las constantes se documentan.

### Tokenizador XLM-R en JVM sin red en el gate (b)

Se resuelve con **`ai.djl.huggingface:tokenizers`** (`HuggingFaceTokenizer`), que
**empaqueta las librerías nativas** (`libtokenizers` para `linux-x86_64`,
`linux-aarch64`, `osx-aarch64`, `win-x86_64`) y **carga un `tokenizer.json` local**
(la conversión *SentencePiece*/Unigram de XLM-R viene en el mismo `tokenizer.json`
que publica el modelo E5). No hay llamada de red en tiempo de ejecución ni en el
gate: el fichero se aprovisiona en un **paso manual** (ver más abajo).

### Modelo ONNX (a)

- **Artefactos**: `model.onnx` (export ONNX **int8** de
  `intfloat/multilingual-e5-small`) y `tokenizer.json`. Entradas
  `input_ids`/`attention_mask` (`int64`, `[1, ≤512]`); salida `last_hidden_state`
  (`float`, `[1, seq, 384]`). Si el export trae el agrupado `sentence_embedding`,
  se consume y solo se normaliza. El script de descarga fija una URL concreta de
  Hugging Face (por defecto un export ONNX int8 *directamente cargable* de esos
  mismos pesos; el *upstream* de verdad es `intfloat/multilingual-e5-small`).
- **Desarrollo**: `backend/models/multilingual-e5-small/` (directorio
  **ignorado por git**), poblado por `backend/tools/download-embedding-model.sh`
  (`curl`, red, manual). Se documenta en `docs/desarrollo-local.md`.
- **Servidor (N100)**: mismo contenido provisionado *out-of-band* en el
  despliegue; ruta **absoluta** por entorno (`EMBEDDING_MODEL_PATH`,
  `EMBEDDING_TOKENIZER_PATH`). El proveedor **falla en claro** si no existen.
- El modelo **no** se commitea ni se descarga en `build`/`test`/`init.sh`/CI.

### Estrategia de verificación offline (tensión resuelta) (c)

**Decisión recomendada: *doble determinista* en las dos fronteras
(`TextTokenizer` y `EmbeddingModel`) para el gate + test *opt-in* para el modelo
real (opción 2, refinada).**

El gate **sí** verifica, sin red ni artefactos:
- el **contrato** de `EmbeddingProvider` (384 dims, rechazo de dims erróneas),
- la **aritmética** del pipeline con dobles: *mean pooling* con máscara,
  normalización L2, `cosineSimilarity` y su **ordenación** (escenario 2),
- la **aplicación de prefijos** (capturando el texto que recibe el tokenizador),
- la **resolución de config con fail-fast** y el **cierre** de recursos.

El test **opt-in** `EMBEDDING_LIVE_TEST=1` (fuera del gate) construye el proveedor
real desde las rutas locales y comprueba el **modelo E5 real**: 384 dims y
`cos(relacionados) > cos(no_relacionados)` sobre textos del BOE; es la evidencia
de los dos criterios de `verification` de `feature_list.json`.

**Alternativas evaluadas y descartadas**:
- **(1) `.onnx` diminuto + `tokenizer.json` mínimos en `src/test/resources`.**
  Ejercitaría la sesión ONNX real, pero: (i) en el entorno **no** hay `onnx`/
  `torch` (Python 3.9 sin esos paquetes) ni *builder* de protobuf ONNX en el jar de
  `onnxruntime` (`ai/onnxruntime/*`, sin clases `onnx.*`), así que generarlo exige
  instalar *toolchain* Python y **commitear un binario + script**, con
  regeneración frágil; (ii) el modelo diminuto **no** verifica la semántica de E5
  (el criterio 2 real queda igualmente en el opt-in); (iii) lo único que añade
  sobre la opción 2 es el *plumbing* de un tercero (`OrtSession`), que no es
  código nuestro. Coste/beneficio desfavorable para el límite de 30 ficheros.
- **(3) reimplementar el tokenizador SentencePiece/XLM-R en Kotlin.** Descartada:
  costosa, propensa a errores y fuera del propósito de la feature.

**Impacto en dependencias del catalog**: `onnxruntime = "1.20.0"` y
`djl = "0.33.0"`; librerías `onnxruntime`, `djl-tokenizers`, `djl-api`. **Tamaño
del modelo de test**: **ninguno** commiteado en la opción recomendada; el modelo
real (~120 MB) tampoco se commitea. (Con la opción 1 hipotética sería un `.onnx`
de unos pocos KB + un `tokenizer.json` mínimo.)

### Sin wiring y sin anticipar lo diferido

`Application.kt`, `ingesta/job/`, `ingesta/backfill/`, `:shared`, `:composeApp`,
migraciones Flyway, `.github/workflows/ci.yml` y `init.sh` quedan **intactos**.

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico/backend` se abrevia
como `…/backend`:

- `backend/src/main/kotlin/…/backend/rag/embeddings/EmbeddingProvider.kt` — create;
  interfaz + `embedPassages`.
- `backend/src/main/kotlin/…/backend/rag/embeddings/TextTokenizer.kt` — create;
  *seam* de tokenización + `TokenizedInput`.
- `backend/src/main/kotlin/…/backend/rag/embeddings/EmbeddingModel.kt` — create;
  *seam* de inferencia.
- `backend/src/main/kotlin/…/backend/rag/embeddings/VectorMath.kt` — create;
  *mean pooling*, normalización L2, coseno (puros).
- `backend/src/main/kotlin/…/backend/rag/embeddings/E5Tokenizer.kt` — create;
  tokenizador DJL real.
- `backend/src/main/kotlin/…/backend/rag/embeddings/OnnxEmbeddingModel.kt` —
  create; sesión ONNX real.
- `backend/src/main/kotlin/…/backend/rag/embeddings/E5EmbeddingProvider.kt` —
  create; composición + prefijos + factory.
- `backend/src/main/kotlin/…/backend/rag/embeddings/EmbeddingConfig.kt` — create;
  resolución de entorno con fail-fast + `EmbeddingException`.
- `backend/src/test/kotlin/…/backend/rag/embeddings/VectorMathTest.kt` — create;
  pooling/normalización/coseno (puros, sin red).
- `backend/src/test/kotlin/…/backend/rag/embeddings/E5EmbeddingProviderTest.kt` —
  create; dobles de tokenizer/modelo: prefijos, 384 dims, normalización, orden de
  coseno, rechazo de dims, cierre.
- `backend/src/test/kotlin/…/backend/rag/embeddings/EmbeddingConfigTest.kt` —
  create; default y fail-fast.
- `backend/src/test/kotlin/…/backend/rag/embeddings/E5EmbeddingLiveTest.kt` —
  create; **opt-in** `EMBEDDING_LIVE_TEST=1` contra el modelo real.
- `backend/tools/download-embedding-model.sh` — create; descarga manual (red,
  fuera del gate) del `.onnx` int8 + `tokenizer.json` a `backend/models/…`.
- `gradle/libs.versions.toml` — modify; `onnxruntime`, `djl` + 3 librerías.
- `backend/build.gradle.kts` — modify; `implementation` de las 3 dependencias.
- `.gitignore` — modify; ignorar `backend/models/`.
- `docs/desarrollo-local.md` — modify; sección «Embeddings locales (ONNX)».

Harness (privado): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0010` + índice,
`.agents/skills/rag-datapublico/SKILL.md`, `docs/adr/README.md`, `feature_list.json`,
`PROGRESS.md` (ver *Durable Documentation Impact*).

**Sin cambios** en `ArticleChunker`, `Fragment`, `persistence/`, migraciones,
`Application.kt`, `ingesta/`, `:shared`, `:composeApp`, CI e `init.sh`.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI.

## Durable Documentation Impact

- `ARCHITECTURE.md`: update — `:backend` añade **`rag/embeddings/`**
  (`EmbeddingProvider` + `E5EmbeddingProvider` ONNX/DJL); la frontera «IA:
  embeddings locales» pasa a estar implementada; se subraya que **no** está
  cableada, que no anticipa pgvector/HNSW (FT00016) y que el modelo no se
  commitea.
- `CONSTRAINTS.md`: update — nueva sección «Embeddings locales» con MUST: E5 int8
  vía **ONNX Runtime en CPU** tras la interfaz `EmbeddingProvider`; prefijos
  `query: `/`passage: `; vectores **normalizados** de **384 dims** y ≤512 tokens;
  **modelo y tokenizador fuera del repo** y **nunca** descargados en
  `build`/`test`/`init.sh`/CI; prueba contra el modelo real **opt-in**
  (`EMBEDDING_LIVE_TEST=1`); ruta por entorno con **fail-fast**; **sin wiring**.
- `AGENTS.md`: not needed — no cambia el flujo ni el camino de arranque.
- **ADR `docs/adr/0010-embeddings-locales-e5-onnx.md`** (recomendado): decisión
  durable «embeddings locales E5 int8 vía ONNX Runtime tras una interfaz de
  proveedor; tokenizador XLM-R con DJL; aprovisionamiento del modelo fuera del
  repo y verificación *offline* con doble determinista + opt-in». El planner
  **no** lo crea; lo escribe el implementador/orquestador y lo inscribe en el
  índice `docs/adr/README.md`.
- `.agents/skills/rag-datapublico/SKILL.md`: update — §2 «Estado actual del
  producto (FT00015)» (paquete `rag/embeddings/`, interfaz, prefijos, 384 dims,
  normalización, contador real de tokens, aprovisionamiento y test opt-in).
- `docs/desarrollo-local.md` (producto): update — descarga del modelo, variables
  de entorno y comando del test opt-in.
- `docs/risks-and-open-questions.md`: update opcional — el *research task* de
  comparar int8 vs fp32/`-base` sigue abierto (FT00015 deja la interfaz lista).

## Implementation Plan

1. Añadir al version catalog y a `:backend` las dependencias (`onnxruntime`
   1.20.0, `djl-tokenizers`/`djl-api` 0.33.0).
2. Crear `VectorMath.kt` (puro) y sus tests; es la base de pooling/normalización/
   coseno.
3. Crear los *seams* `TextTokenizer`/`EmbeddingModel` y `E5EmbeddingProvider` con
   prefijos y validación; tests con dobles (escenarios 1–4, 6, 7).
4. Implementar `E5Tokenizer` (DJL) y `OnnxEmbeddingModel` (ONNX) con cierre de
   recursos.
5. Implementar `EmbeddingConfig` (entorno + fail-fast) y su test (escenario 5).
6. Añadir el script de descarga y `.gitignore`; escribir `E5EmbeddingLiveTest`
   (opt-in) y el comando documentado.
7. Ejecutar el gate offline y, con el modelo descargado, el test opt-in; actualizar
   la documentación durable (ARCHITECTURE, CONSTRAINTS, ADR 0010 + índice, skill
   RAG, `docs/desarrollo-local.md`). `PROGRESS.md`/`feature_list.json` los cierra
   el orquestador.

## Implementation Tasks

- [ ] Catalog + `:backend`: `onnxruntime` 1.20.0, `djl-tokenizers`/`djl-api` 0.33.0.
- [ ] `VectorMath.kt`: `meanPool`/`l2Normalize`/`cosineSimilarity` puros + KDoc.
- [ ] `TextTokenizer.kt`/`EmbeddingModel.kt`: *seams* + `TokenizedInput`.
- [ ] `E5EmbeddingProvider.kt`: prefijos, normalización, 384 dims y validación.
- [ ] `E5Tokenizer.kt`: DJL `HuggingFaceTokenizer` sobre `tokenizer.json` + `countTokens`.
- [ ] `OnnxEmbeddingModel.kt`: `OrtSession` (`input_ids`/`attention_mask` → `last_hidden_state`).
- [ ] `EmbeddingConfig.kt`: `EMBEDDING_*` con fail-fast (`EmbeddingException`).
- [ ] `VectorMathTest` + `E5EmbeddingProviderTest` + `EmbeddingConfigTest` (gate, sin red).
- [ ] `backend/tools/download-embedding-model.sh` + `.gitignore` (`backend/models/`).
- [ ] `E5EmbeddingLiveTest` opt-in (`EMBEDDING_LIVE_TEST=1`).
- [ ] Docs durables: ARCHITECTURE, CONSTRAINTS, ADR 0010 + índice, skill RAG,
      `docs/desarrollo-local.md`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red ni BD (obligatorio)**: `./gradlew :backend:test --rerun-tasks` →
  BUILD SUCCESSFUL con los nuevos tests (0 fallos) y el resto de `:backend`
  intacto. `./gradlew build --no-daemon -PskipClient` (incluye `:backend:detekt` y
  `:cpdCheck`), `./gradlew test`, `./gradlew detekt` y
  `env -u JAVA_HOME .harness/init.sh` → exit 0.
- **Offline confirmado**: ningún test del gate abre sockets ni usa la ruta del
  modelo; el opt-in se **omite** sin `EMBEDDING_LIVE_TEST` (un `@Test` que no
  abre nada). Verificar por inspección que el gate no descarga artefactos.
- **Escenarios 1–7** cubiertos por `VectorMathTest`/`E5EmbeddingProviderTest`/
  `EmbeddingConfigTest` con dobles deterministas.
- **Opt-in del modelo real (fuera del gate, no en CI)**:
  ```sh
  backend/tools/download-embedding-model.sh
  EMBEDDING_LIVE_TEST=1 ./gradlew :backend:test --tests '*E5EmbeddingLiveTest'
  ```
  Esperado: 384 dims y `cos(relacionados) > cos(no_relacionados)` con textos del
  BOE. Es la evidencia de los dos criterios de `verification`.
- **E2E**: no aplica — librería sin flujo de usuario ni endpoint nuevo
  (`pnpm`/E2E no existen en este repo; el cliente es Compose Multiplatform).
- `init.sh` (harness): **no** se modifica; no se le añade ningún paso de descarga.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con los nuevos tests (recuento, 0 fallos) y
  del gate (`build -PskipClient`, `test`, `detekt`, `init.sh` exit 0).
- Salida del test **opt-in** con el modelo real: 384 dims y la comparación de
  similitud coseno (relacionados > no relacionados).
- Hash/tamaño del `model.onnx` descargado y la variante exacta (int8) usada.
- Ficheros del commit `FT00015`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `rag/embeddings/` + tests + script + deps/docs; **sin**
      columna vectorial/HNSW ni migración (FT00016), **sin** recuperación
      (FT00017), **sin** resúmenes/IA, **sin** endpoints y **sin wiring** en
      `Application.kt`/job/backfill; `ArticleChunker`/`persistence/` intactos.
- [ ] Escenarios 1–7 pasan; **todo el gate corre sin red ni BD** y sin descargar
      el modelo; el opt-in se omite sin `EMBEDDING_LIVE_TEST`.
- [ ] El proveedor devuelve **384 dims**, vectores **normalizados**, prefijos
      `query: `/`passage: `; ≤512 tokens; `countTokens` real disponible.
- [ ] Modelo y tokenizador **fuera del repo** (gitignored) y **no** descargados en
      el gate/CI; ruta por entorno con **fail-fast** y mensaje claro.
- [ ] El modelo real verificado por el test **opt-in** (evidencia capturada).
- [ ] `return` único, sin `else if`, funciones ≤40 líneas, KDoc en castellano con
      identificadores en inglés.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0010 + índice, skill RAG,
      `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] No unrelated product behavior or extra feature work was added.

## Risks / Open Questions

- **Artefacto ONNX exacto.** El `intfloat/multilingual-e5-small` oficial es
  *sentence-transformers*; hay que fijar un export ONNX **int8 directamente
  cargable** (por defecto un espejo tipo `Xenova/multilingual-e5-small`
  `onnx/model_quantized.onnx` + `tokenizer.json`) y confirmar el **contrato de
  salida** (`last_hidden_state` `[1, seq, 384]` vs `sentence_embedding` `[1,384]`).
  El proveedor debe soportar ambas; fijar la URL concreta y su hash en el script.
- **DJL y el tokenizador XLM-R.** Se asume `HuggingFaceTokenizer.newInstance(Path)`
  sobre `tokenizer.json`; confirmar la *overload* exacta (fichero vs directorio).
  DJL **no** trae nativo para `osx-x86_64` (Intel Mac): este entorno
  (`osx-aarch64`), el N100 (`linux-x86_64`) y la CI (`linux-x86_64`) sí están
  cubiertos.
- **Peso de las dependencias.** `onnxruntime` (~93 MB de jar con nativos de varias
  plataformas) y `tokenizers` (~18 MB de jar) engordan la descarga de la CI y el
  artefacto del backend; aceptable en servidor, a vigilar en la CI.
- **Memoria en el N100.** Una sesión E5 int8 (~120 MB) + runtime consume RAM junto
  a JVM y PostgreSQL. Como **no** se cablea todavía, no afecta al gate; FT00016/17
  deberán medirlo (ver `risk` de rendimiento del N100).
- **Contador real de tokens y `ArticleChunker`.** FT00015 expone el contador real
  pero **no** modifica el chunker (se mantiene puro). Decidir en FT00016/17 si se
  inyecta un `tokenCounter` (función, no el tokenizador nativo) o si se recalibra
  `CHARS_PER_TOKEN`; FT00015 deja la puerta abierta.
- **Caducidad de la decisión del doble determinista.** Si en el futuro se quiere
  ejercitar `OrtSession` en el gate, habría que añadir un `.onnx` diminuto +
  *toolchain* de generación; se descarta ahora por coste/beneficio (ver *Technical
  Approach*).
- **`close()` idempotente.** `OrtSession`/DJL pueden lanzar al cerrar dos veces;
  el wrapper debe tolerarlo (test explícito).

## Nota de implementación (2026-10-10)

- **Contrato real del export ONNX (desviación justificada).** El artefacto real
  del espejo `Xenova/multilingual-e5-small` (`onnx/model_quantized.onnx`, sha256
  `f80102d3…f98c193`) declara **tres** entradas —`input_ids`, `attention_mask` y
  `token_type_ids`— y una salida `last_hidden_state` (sin `sentence_embedding`).
  El *Technical Approach* solo describía las dos primeras, así que
  `OnnxEmbeddingModel` se corrigió para **añadir `token_type_ids` (ceros, `[1,
  seq]`) solo si el modelo lo declara**; sin ello la inferencia falla con
  `Missing Input: token_type_ids`. El *mean pooling* con máscara es el camino
  usado. Evidencia del modelo real:
  `dims=384 norm=1.0 cos(rel,par)=0.9693954 cos(rel,unrel)=0.849925
  cos(par,unrel)=0.8374902`, `countTokens(passage)=24`.
