# ADR 0010: Embeddings locales E5 int8 vía ONNX Runtime tras una interfaz de proveedor

## Estado

Aceptado (2026-10-10). Decisión del dueño del proyecto. No supersede ningún ADR.

## Contexto

El RAG de la 1.0.0 (ingesta → chunking → **embeddings ONNX** → pgvector →
recuperación → generación con cita) necesita vectorizar fragmentos y consultas
**sin depender de un servicio de embeddings remoto** (OpenCode no ofrece endpoint
de embeddings). La decisión previa ya fijó `intfloat/multilingual-e5-small`
**int8** por ONNX/CPU, 384 dimensiones, contexto de 512 tokens y prefijos
obligatorios `query: `/`passage: `.

Tras FT00014 (chunking puro) hacía falta: (1) un **proveedor intercambiable** para
poder cambiar a `-base` (768 dims) sin tocar el resto del código; (2) el
**tokenizador XLM-R real** (cierre del contador provisional de FT00014); (3) una
estrategia de **verificación sin red ni artefactos en el gate** y sin commitear el
modelo (~118 MB) ni el `tokenizer.json` (~17 MB); y (4) un modo de **aprovisionar**
los artefactos fuera del repositorio con fail-fast.

## Decisión

- **Proveedor tras interfaz.** Paquete nuevo
  `es.aviferdev.datopublico.backend.rag.embeddings` en `:backend`:
  `EmbeddingProvider` (público, `AutoCloseable`: `dimensions`, `embedQuery`,
  `embedPassage`, `embedPassages`) + `E5EmbeddingProvider` (composición con
  prefijos `query: `/`passage: `, *mean pooling* con máscara, normalización L2 y
  validación de 384 dims). El resto del pipeline solo conoce la interfaz.
- **Dos *seams* internos.** `TextTokenizer` (tokenización + `countTokens`) y
  `EmbeddingModel` (inferencia `forward`) son interfaces **internas** con
  implementaciones reales `E5Tokenizer` (DJL `HuggingFaceTokenizer` sobre el
  `tokenizer.json`) y `OnnxEmbeddingModel` (`OrtSession`). Aíslan las fronteras
  nativas y permiten probar el pipeline con dobles deterministas.
- **Contrato de salida flexible.** `OnnxEmbeddingModel` soporta
  `last_hidden_state` `[1, seq, 384]` (preferido: *mean pooling* manual) y
  `sentence_embedding` `[1, 384]`; si el modelo declara `token_type_ids`, se
  envía a ceros (el export de espejo lo exige). Falla en claro si la última
  dimensión no es 384.
- **Aritmética pura reutilizable.** `VectorMath` (`meanPool`, `l2Normalize`,
  `cosineSimilarity`) es puro y determinista; lo reutilizará FT00017.
- **Aprovisionamiento fuera del repo.** `backend/models/` está **gitignored** y se
  puebla con `backend/tools/download-embedding-model.sh` (URL real y verificable
  del espejo `Xenova/multilingual-e5-small`). El proveedor carga por **ruta
  absoluta** desde `EMBEDDING_MODEL_PATH`/`EMBEDDING_TOKENIZER_PATH` con
  **fail-fast** (`EmbeddingException`); sin *fallback* ni descarga silenciosa.
- **Verificación *offline* + opt-in.** El gate cubre el contrato y la aritmética
  con **dobles deterministas** (`TextTokenizer`/`EmbeddingModel`), sin red ni
  artefactos. El **modelo real** se verifica con un test **opt-in**
  (`EMBEDDING_LIVE_TEST=1`), fuera de `build`/`test`/`init.sh`/CI.
- **Sin wiring ni anticipación.** `Application.kt`, job, backfill, migraciones,
  `:shared`, `:composeApp` y CI quedan intactos; **no** se toca `ArticleChunker` ni
  `persistence/`; la columna `embedding vector(384)`/HNSW es de FT00016.

## Alternativas consideradas

- **Servicio de embeddings remoto.** Descartado: coste, dependencia externa y la
  decisión de IA fija embeddings **locales** (OpenCode no los ofrece).
- **`.onnx` diminuto + `tokenizer.json` mínimos commiteados en `src/test/resources`.**
  Descartado: exige *toolchain* Python para generarlo y commitear binarios con
  regeneración frágil, y el modelo diminuto no verifica la semántica de E5; el
  beneficio (ejercitar `OrtSession`) no compensa.
- **Reimplementar el tokenizador SentencePiece/XLM-R en Kotlin.** Descartado:
  costoso y propenso a errores.
- **Commitear el modelo int8 (~118 MB).** Descartado: engorda el repo y rompe la
  regla de no versionar artefactos pesados; se aprovisiona *out-of-band*.
- **Descargar el modelo en `build`/`test`/`init.sh`/CI.** Descartado: el gate debe
  correr sin red.

## Consecuencias

- **Habilita** FT00016 (indexado en pgvector) y FT00017 (recuperación) reutilizando
  `EmbeddingProvider` y `VectorMath`; el tokenizador real cierra el contador
  provisional de FT00014 (`countTokens`, ≤512).
- **Cuesta** asumir dependencias pesadas (`onnxruntime` ~93 MB de jar con nativos y
  `djl-tokenizers` ~18 MB) en el classpath de `:backend`; aceptable en servidor, a
  vigilar en la CI.
- **Cuesta** un paso manual de aprovisionamiento (script) y la verificación del
  modelo real queda **fuera** del gate; la evidencia opt-in se captura a mano.
- **Riesgo abierto**: la comparación int8 vs fp32/`-base` sobre corpus real sigue
  pendiente (FT00015 deja la interfaz lista); la memoria en la máquina única
  (sesión E5 + JVM + PostgreSQL) la deberán medir FT00016/17.
- **Documentación/código**: `rag/embeddings/` en `ARCHITECTURE.md`, regla MUST en
  `CONSTRAINTS.md` §«Embeddings locales», estado actual en la skill
  `rag-datapublico`, sección en `docs/desarrollo-local.md` y este ADR.
- **Verificación**: `VectorMathTest`/`E5EmbeddingProviderTest`/`EmbeddingConfigTest`
  (gate, sin red) y `E5EmbeddingLiveTest` (opt-in con el modelo real).
