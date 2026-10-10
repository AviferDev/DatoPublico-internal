---
name: rag-datapublico
description: Guía del pipeline RAG de DatoPublico sobre el BOE (todo el sumario: Secciones I, II.A, II.B, III, IV, V.A, V.B y V.C). Úsala al ingerir o fragmentar publicaciones, generar o almacenar embeddings, indexar en pgvector, montar recuperación híbrida, generar resúmenes o respuestas de chat con citas, aplicar guardrails o evaluar calidad (golden set, precision/recall). Fija las convenciones del proyecto (chunking, multilingual-e5-small int8, protección anti-alucinación, trazabilidad a la fuente) y describe el patrón objetivo y sus riesgos conocidos.
---

# RAG de DatoPublico (BOE)

El valor del producto está en recuperar bien y **no inventar**. Toda afirmación
mostrada al usuario debe apoyarse en fragmentos del BOE y llevar **enlace a la
fuente oficial**. Lee también `docs/domain-model.md`,
`docs/technical-discovery.md` y `CONTEXT.md`.

> Antecedente: una PoC temporal (`poc/boe-rag`) validó el pipeline de punta a
> punta (ingesta → chunking → embeddings ONNX → pgvector → recuperación →
> generación con cita; recall/MRR 1.0 sobre un set mínimo). Se **eliminó** a
> propósito: era una prueba temporal. Sus lecciones están destiladas en esta
> skill; no la busques en el repo.

## Pipeline

```
ingesta BOE → chunking → embeddings (ONNX) → pgvector → recuperación híbrida
   → generación (OpenCode) → guardrails → publicación | cola_revision
```

## 1. Ingesta y chunking

- Corpus: **todo el sumario del BOE** — **I** (disposiciones generales), **II.A**
  (nombramientos), **II.B** (empleo), **III** (otras disposiciones), **IV**
  (Administración de Justicia), **V.A** (contratación pública), **V.B** (otros
  anuncios) y **V.C** (anuncios particulares). Cada sección tiene estructura y
  vocabulario distintos: el chunking necesita **variantes por sección**, no una
  regla única.
- Fragmenta por **artículo/disposición** conservando su referencia. No generes
  solapamientos inválidos; los fragmentos deben cubrir el texto.
- Normaliza: el BOE usa **espacio duro (`\u00a0`)** tras etiquetas como
  «Artículo»; inserta saltos por párrafo y ancla los encabezados a **inicio de
  línea**. Omitir esto produce referencias erróneas.
- Cada fragmento guarda metadatos de metadatos de filtrado: publicación,
  categoría, fecha, organismo y referencia de artículo/sección.

### Estado actual del producto (FT00014)

- La fragmentación **ya está implementada** en `:backend`:
  `es.aviferdev.datopublico.backend.rag.chunking.ArticleChunker`
  (`chunk(Publicacion): List<Fragment>`) y el modelo de dominio
  `rag.Fragment` (`publicationId`, `order`, `reference`, `content`, sin sufijo).
  Es **pura, determinista y sin red/BD**, con variante por sección y cobertura sin
  solapamiento; el mapeo a persistencia es la extensión pura `Fragment.toEntity()`
  en `persistence/FragmentRepository.kt`. Decisión durable en
  `docs/adr/0009`.
- **Estimación de tokens provisional**: `ArticleChunker` usa
  `ceil(length / charsPerToken)` con `charsPerToken = 3` y `maxTokens = 512`
  (ambos inyectables por constructor) porque el tokenizador real E5 llega con
  **FT00015**. Es conservadora; FT00015 deberá recalibrarla o inyectar el
  contador real sin cambiar la firma.
- La detección de encabezados es **heurística por texto** (la `Publicacion` no
  conserva el `class="articulo"`): una línea que empiece por «Artículo»/
  «Disposición» se trata como encabezado. Validado con los fixtures reales de las
  ocho secciones.

## 2. Embeddings (locales)

- Modelo por defecto: **`intfloat/multilingual-e5-small` cuantizado int8** vía
  **ONNX Runtime en CPU**; **384 dimensiones**, contexto **512 tokens**.
- Prefijos obligatorios: `query: ` para la consulta y `passage: ` para los
  fragmentos. Sin prefijo la calidad cae.
- Normaliza los vectores. No superes 512 tokens por fragmento.
- El modelo vive tras una **interfaz de proveedor** para poder cambiar a `-base`
  (768 dims) sin tocar el resto del código. Cambiar de modelo implica **rediseñar
  la columna y reindexar**.
- Herramienta configurable por entorno; clave de OpenCode solo en el servidor.

### Estado actual del producto (FT00015)

- El proveedor de embeddings **ya está implementado** en `:backend`, paquete
  `es.aviferdev.datopublico.backend.rag.embeddings`: interfaz pública
  `EmbeddingProvider` (`dimensions`, `embedQuery`, `embedPassage`, `embedPassages`,
  `AutoCloseable`) + implementación `E5EmbeddingProvider`
  (`intfloat/multilingual-e5-small` int8 vía **ONNX Runtime en CPU**, tokenizador
  XLM-R de DJL). Aplica los **prefijos obligatorios** `query: `/`passage: `,
  *mean pooling* con máscara, **normaliza** (L2) y devuelve **384 dims**;
  `VectorMath` (`meanPool`/`l2Normalize`/`cosineSimilarity`) es puro y lo
  reutilizará la recuperación. Decisión durable en `docs/adr/0010`.
- **Tokenizador real**: `E5Tokenizer.countTokens` cierra el **contador provisional**
  de FT00014 (`ArticleChunker` se mantiene **puro**, sin dependencia nativa; la
  inyección/calibración es de FT00016).
- **Aprovisionamiento**: el modelo (~118 MB) y el `tokenizer.json` **no** se
  versionan; se descargan con `backend/tools/download-embedding-model.sh` a
  `backend/models/` (gitignored) y se referencian por **ruta absoluta**
  (`EMBEDDING_MODEL_PATH`/`EMBEDDING_TOKENIZER_PATH`) con fail-fast. El gate no
  descarga nada; el modelo real se prueba **opt-in**
  (`EMBEDDING_LIVE_TEST=1`). No está cableado y **no** anticipa pgvector/HNSW
  (FT00016) ni la recuperación (FT00017).

## 3. Almacenamiento vectorial

- PostgreSQL + **pgvector**; columna de dimensión **384**; índice **HNSW**.
- Filtros SQL por metadatos (fecha, categoría, organismo) combinados con la
  similitud. Verifica que el índice **se usa** en la consulta.

## 4. Recuperación híbrida

- Combina filtros SQL con similitud vectorial; devuelve top-k fragmentos con su
  referencia y score.
- Ordena por relevancia; deja la puerta a un **reranking** si la calidad lo pide.

## 5. Generación (resumen y chat)

- Proveedor: **OpenCode** (OpenAI-compatible, candidato `deepseek-v4.1-flash`)
  tras una interfaz intercambiable.
- **Resumen ciudadano:** salida estructurada "¿Qué cambia?", "¿A quién afecta?",
  "Cifras clave", con **cita obligatoria** a la fuente. Variante para empleo/beca
  (incluye **plazo**).
- **Chat/consulta:** acepta una pregunta o una **afirmación a verificar**;
  responde con las citas y distingue **respondida**, **refutada** y
  **sin_fundamento**.
- El prompt trabaja **solo** con el contexto recuperado; prohibido el
  conocimiento libre del modelo.

## 6. Guardrails (anti-alucinación y trazabilidad)

- Ningún resumen se publica sin **enlace válido** a la fuente oficial.
- Ninguna afirmación fuera del contexto recuperado. Si el corpus no sustenta la
  respuesta, se declara **sin_fundamento** (no se inventa).
- Resúmenes de **baja confianza** van a `cola_revision`, sin bloquear el feed.
- Cachea resúmenes por publicación para no regenerar ni gastar tokens de más.

## 7. Evaluación

- **Recuperación:** precision/recall (y recall@k / MRR) sobre un set de prueba.
- **Resúmenes:** **golden set** de publicaciones con referencia; mide acierto en
  "¿Qué cambia?" y "¿A quién afecta?".
- **Chat:** respuestas con citas correctas, refutación de afirmaciones falsas y
  comportamiento ante preguntas sin fundamento.

## Riesgos conocidos

- Chunking por expresiones regulares es **heurístico**; la vía de producto debería
  aprovechar la estructura/XML del BOE cuando sea posible.
- `int8` degrada ligeramente la calidad; **no** se ha comparado aún contra fp32 ni
  `-base` sobre corpus real.
- Corpus de prueba pequeño; validar con volúmenes reales antes de confiar en las
  métricas.
- Las Secciones II.A, II.B, III, IV, V.A, V.B y V.C son más irregulares que la I:
  parser, chunking y clasificación requieren validación con datos reales; puede
  haber duplicidad III ↔ V.B (base reguladora y extracto).
- Coste del chat por tokens: aplicar rate limiting y control de contexto.
