# ADR 0009: Fragmentación determinista por artículo/disposición con variante por sección

## Estado

Aceptado (2026-10-10). Decisión del dueño del proyecto. No supersede ningún ADR.

## Contexto

El RAG de la 1.0.0 (ingesta → **chunking** → embeddings ONNX → pgvector →
recuperación → generación con cita) necesita dividir el texto oficial de cada
publicación del BOE antes de vectorizarlo (FT00015) y persistirlo en la tabla
`fragmento` (FT00016+). El corpus es **todo el sumario** (secciones I, II.A, II.B,
III, IV, V.A, V.B y V.C) y la estructura varía mucho: la Sección I se organiza en
**artículos y disposiciones** con encabezado, pero II.A/II.B/IV/V.A/V.B/V.C **no
tienen artículos** y llegan como párrafos, tablas y listas sueltas.

`Publicacion.texto` ya llega **normalizado por el parser** del BOE (FT00007):
espacio duro colapsado, párrafos como líneas y encabezados anclados a inicio de
línea; **no** conserva el `class="articulo"` del XML. El modelo E5
(`multilingual-e5-small` int8, 384 dims) tiene un contexto de **512 tokens**.

Hacía falta fijar por adelantado: (1) la **unidad** de fragmentación y cómo se
conserva la **referencia** para citar; (2) cómo cubrir el texto **sin
solapamientos**; (3) cómo respetar el **presupuesto de tokens** sin depender
todavía del tokenizador real (FT00015); y (4) dónde vive el modelo de fragmento
para no repetir esta decisión en cada feature posterior del pipeline.

## Decisión

- **Paquete de dominio RAG `rag/`** en `:backend`, puro y sin wiring:
  `rag/Fragment` (modelo de dominio **sin sufijo**) y
  `rag/chunking/ArticleChunker` (clase pura, patrón de `HighlightRanker`). El
  contrato público es `chunk(publicacion: Publicacion): List<Fragment>`; el
  constructor admite `maxTokens` y `charsPerToken` con default para que FT00015
  inyecte el tokenizador real **sin cambiar la firma**.
- **Unidad por artículo/disposición.** Se detectan encabezados con una `Regex`
  **anclada a inicio de línea** (`^(Artículo|Disposición)\b`). Cada encabezado
  inicia un bloque (encabezado + cuerpo hasta el siguiente); las líneas previas al
  primero forman el bloque **introductorio**. En documentos **sin encabezados**
  hay un único bloque: es la **variante por sección**.
- **Referencia conservada.** La `reference` de un bloque con encabezado es la
  **línea de encabezado** (p. ej. `Artículo 4. Convocatoria.`); para el bloque
  introductorio y para los documentos sin encabezados es `SECTION_REFERENCE_PREFIX
  + seccion.name` (p. ej. `Sección II_B`).
- **Cobertura sin solapamiento.** Los fragmentos se construyen acumulando líneas
  hasta el presupuesto; la concatenación reproduce las líneas del texto de origen,
  en orden, sin repetirlas ni omitirlas. Un **párrafo único** que supere el
  presupuesto se parte por **palabras** con la **misma `reference`** (una palabra
  mayor que el presupuesto se trocea por caracteres); nunca hay solapamiento.
- **Presupuesto ≤512 tokens con estimación provisional e inyectable.**
  `estimateTokens(text) = ceil(length / charsPerToken)` con `CHARS_PER_TOKEN = 3` y
  `MAX_TOKENS = 512`, constantes documentadas. La estimación es **conservadora**
  (favorece no superar los 512 tokens reales); FT00015 la recalibra o inyecta el
  contador real.
- **`order` contiguo y determinismo.** `order` es `0..n-1` en orden de documento;
  la misma `Publicacion` produce siempre la misma lista. Se descarta cualquier
  fragmento con `content` en blanco.
- **Mapeo a persistencia en la capa de datos.** La extensión pura
  `Fragment.toEntity(): FragmentEntity` (en `persistence/FragmentRepository.kt`)
  cierra el encaje dominio → entidad con `id = null`. **No** se abre conexión ni
  se invoca el repositorio.
- **No se anticipa lo diferido.** Sin embeddings/ONNX (FT00015), sin columna
  `embedding vector(384)` ni índice HNSW ni migración (FT00016), sin recuperación
  (FT00017) y sin wiring en `Application.kt`/job/backfill.

## Alternativas consideradas

- **Fragmentar por tamaño fijo de caracteres.** Descartada: rompe la unidad
  artículo/disposición y la cita fiable (la referencia se perdería).
- **Usar el marcado `class="articulo"` del XML.** Descartada: `Publicacion.texto`
  no conserva el marcado (haría falta cambiar el parser de FT00007, fuera de
  alcance). La vía futura —que el parser preserve el encabezado— queda anotada como
  riesgo.
- **Integrar ya el tokenizador real de E5 (ONNX).** Descartada para FT00014: es
  FT00015. Se deja una estimación determinista, documentada e **inyectable**.
- **Solapar fragmentos (*overlap*) para no cortar contexto.** Descartada: el spec
  exige cobertura **sin solapamiento**; el riesgo de cortar contexto se gestiona en
  recuperación/generación (FT00017+).
- **Modelo `Fragment` con sufijo `Dto`/`Entity`.** Descartado: es un modelo de
  **dominio interno** no serializable → va **sin sufijo** (`CONSTRAINTS.md`
  §«Nombres y contratos»); la fila de persistencia ya es `FragmentEntity`.

## Consecuencias

- **Habilita** vectorizar y persistir fragmentos con referencia sin reimplementar
  el chunking: FT00015 y FT00016 consumen `ArticleChunker` y `Fragment`.
- **Cuesta** asumir dos heurísticas documentadas con deuda aceptada: la
  **estimación de tokens** (`charsPerToken = 3`) y la **detección de encabezados
  por texto** (una línea de cuerpo que empiece por «Artículo»/«Disposición» podría
  tratarse como encabezado). Ambas se mitigan con la validación sobre los fixtures
  reales y son afinables con datos reales.
- **Secciones irregulares**: II.A/II.B/IV/V.A/V.B/V.C producen fragmentos
  heterogéneos (tablas/listas como líneas sueltas); se acepta y se valida con
  datos reales (riesgo ya registrado en `risks-and-open-questions.md`).
- **Documentación/código**: paquete `rag/` en `ARCHITECTURE.md`, regla MUST en
  `CONSTRAINTS.md` §«RAG / fragmentación», estado actual en la skill
  `rag-datapublico` y nota en `docs/desarrollo-local.md`. Sin cambios en
  `:shared`, migraciones, `Application.kt` ni CI.
- **Verificación**: `ArticleChunkerTest` (sin red ni BD) cubre los escenarios 1–7
  con los fixtures reales de las ocho secciones; no se añade ninguna prueba opt-in.
