# Feature Implementation Spec: Fragmentación por artículo o sección

## Source Feature

- `id`: chunking-articulos
- `ft_id`: FT00014 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ~4–5 ficheros de producto, por debajo del límite de 30)
- `area`: rag
- `depends_on`: publicacion-persistencia (FT00008, `accepted`)
- `status`: not_started (al planificar)
- `source`: `feature_list.json`
- `claim`: rama `feat/ft00014-chunking-articulos` reclamada (local y `origin`); el
  usuario nombra la feature explícitamente y confirma que el claim es de esta sesión.

> **Encaje con FT00008/FT00015/FT00016.** `fragmento` (`FragmentEntity` +
> `FragmentRepository`) ya existe desde FT00008 con la forma
> (`publicacion_id`, `orden`, `referencia`, `contenido`); la columna
> `embedding vector(384)` y el índice HNSW son **FT00016** y no se anticipan. Los
> embeddings/ONNX son **FT00015**. FT00014 solo **transforma** `Publicacion.texto`
> en fragmentos deterministas con referencia, sin vectorizar ni persistir.

## Goal

Añadir en `:backend` un **chunking puro, determinista y sin red/BD** que divide el
texto de una `Publicacion` en fragmentos con metadatos de artículo/sección, listos
para vectorizar (FT00015) y persistir en `fragmento` (FT00016+). Es la tarea
`0.3-T01` de `docs/roadmap.md`: fragmentar por **artículo/disposición**
conservando su **referencia**, cubriendo el texto **sin solapamientos inválidos** y
respetando el presupuesto del modelo E5 (**≤512 tokens** por fragmento), con
**variantes por sección** (las secciones irregulares II.A/II.B/IV/V.A/V.B/V.C no
tienen artículos).

La feature **no** genera embeddings, **no** escribe en PostgreSQL, **no** se
cablea en `Application.kt` y **no** expone endpoints: es una transformación pura
más sus tests.

## Non-Goals

- **Embeddings locales ONNX** (`multilingual-e5-small` int8) y prefijos
  `query:`/`passage:` → FT00015.
- **Columna `embedding vector(384)` + índice HNSW** y persistencia real de
  fragmentos → FT00016. La tabla `fragmento` ya existe; **no** se crea migración.
- **Recuperación híbrida / búsqueda** → FT00017; **evaluación** → FT00018.
- **Resúmenes, chat, IA** de cualquier tipo → FT00019+.
- **Normalización del texto** (espacio duro, saltos por párrafo, anclaje de
  encabezados): ya la hace `BoeXmlParser` (FT00007). **No** se duplica.
- **Wiring en el arranque/job**: `Application.kt`, `job/`, `backfill/` intactos.
- **Tokenizador real**: no se integra ONNX; se usa una **estimación determinista
  documentada** (ver *Risks*), sustituible en FT00015.
- **Reescritura del texto** o corrección lingüística: el contenido de cada
  fragmento es el texto de origen tal cual (solo se decide dónde cortar).

## Job Story

Cuando implemento el RAG base,
quiero dividir el texto oficial de cada publicación en fragmentos por
artículo/disposición (o por sección en las que no tienen artículos), con su
referencia y dentro del presupuesto del modelo,
para poder vectorizarlos, persistirlos y recuperarlos con citas fiables sin
reimplementar el chunking en cada feature posterior.

## Users And Permissions

- Desarrollador / job de ingesta (interno): invoca el chunker desde código de
  `:backend`. Sin cuentas, sin datos personales, sin autenticación, sin red y sin
  BD. Determinista: la misma `Publicacion` produce siempre la misma lista.

## Acceptance Scenarios

### Scenario 1: fragmentar una norma por artículo conservando la referencia

Given el XML real `texto-I-2026-20979` parseado a `Publicacion` (Sección I, 17
artículos y 3 disposiciones finales),
When se ejecuta el chunker sobre su `texto`,
Then se obtiene un fragmento por encabezado `Artículo N.`/`Disposición …` (más el
bloque introductorio previo al primer artículo), cada uno con `reference` igual a
la línea de encabezado y `content` con el encabezado y su cuerpo.

### Scenario 2: cubrir el texto sin solapamientos ni pérdidas

Given el texto normalizado de una publicación,
When se fragmenta,
Then la concatenación de los fragmentos (unidos por `\n`) reproduce **exactamente**
las líneas no vacías del texto de origen, en orden, sin líneas duplicadas ni
omitidas (cobertura total, sin solapamiento).

### Scenario 3: secciones sin artículos (II.A/II.B/IV/V.A/V.B/V.C)

Given un documento real de una sección irregular (p. ej. `texto-VB-2024-76` con
700 párrafos sin encabezados de artículo),
When se fragmenta,
Then no se generan fragmentos por artículo; los párrafos se agrupan en fragmentos
consecutivos dentro del presupuesto, todos con `reference` de **sección**
(`"Sección <seccion>"`), y se sigue cumpliendo la cobertura del escenario 2.

### Scenario 4: artículo largo que supera el presupuesto

Given un artículo cuyo texto estimado supera `MAX_TOKENS` (p. ej. el artículo 1 de
la Sección I o un párrafo largo de V.B),
When se fragmenta,
Then se parte en **fragmentos consecutivos** con la **misma `reference`**, cada
uno con estimación ≤ `MAX_TOKENS`, sin repetir ni perder palabras (el corte en un
párrafo demasiado largo se hace por palabras).

### Scenario 5: `orden` contiguo y determinismo

Given cualquier publicación,
When se fragmenta dos veces,
Then las dos salidas son idénticas y `orden` es `0..n-1` contiguo en orden de
documento.

### Scenario 6: texto nulo o vacío no rompe

Given una `Publicacion` con `texto = null`, vacío o solo espacios (caso
`texto-sin-texto`),
When se fragmenta,
Then devuelve lista vacía, sin excepción ni fragmento vacío.

### Scenario 7: encaje con `FragmentEntity`/`FragmentRepository`

Given los fragmentos de dominio,
When se mapean con el mapeador proporcionado,
Then se obtiene un `FragmentEntity` por fragmento con `publicationId`, `order`,
`reference` y `content` idénticos y `id = null` (aún sin insertar). **No** se
abre conexión ni se llama al repositorio.

## Repository Research

### Files Inspected

- `.harness/feature_list.json` (FT00014; FT00008 `accepted`),
  `PROGRESS.md` (estado verificado), `docs/feature-ids.md` (FT00014 registrado),
  `docs/roadmap.md` §0.3.0 (`0.3-T01`), `docs/domain-model.md` (Fragmento = porción
  por artículo/sección), `docs/technical-discovery.md` (E5 384 dims, 512 tokens),
  `docs/risks-and-open-questions.md` (chunking más frágil en secciones
  irregulares), `ARCHITECTURE.md`, `CONSTRAINTS.md`, `docs/adr/README.md`
  (decisión durable → ADR), y la skill **`rag-datapublico`** §1 (convenciones de
  chunking).
- Producto `..`:
  - `backend/src/main/kotlin/.../persistence/FragmentRepository.kt`
    (`FragmentEntity`: `id?`, `publicationId`, `order`, `reference?`, `content`;
    `FragmentRepository.save/listByPublication`; tabla `fragmento` con
    `UNIQUE (publicacion_id, orden)`).
  - `backend/src/main/resources/db/migration/V2__persistencia_publicaciones.sql`
    (tabla `fragmento`; **sin** embedding → FT00016).
  - `backend/.../ingesta/publicacion/Publicacion.kt` (`texto: String?`, `seccion:
    SeccionBoeDto`, `categoria`, `plazo`), `BoeXmlParser.kt` (texto ya normalizado
    por párrafos, `\n`, espacio duro colapsado, encabezados como línea),
    `PublicacionParser.kt`, `DocumentoBoe.kt`.
  - `shared/.../model/SeccionBoeDto.kt` (8 valores; token oficial `II.B`,
    nombre Kotlin `II_B`).
  - `backend/src/test/resources/boe/` — **fixtures reales** de las 8 secciones
    (`texto-I-2026-20979.xml`, `texto-IIA-2024-87.xml`, `texto-IIB-2024-93.xml`,
    `texto-III-2024-117.xml`, `texto-IV-2024-1.xml`, `texto-VA-2024-25.xml`,
    `texto-VB-2024-76.xml`, `texto-VC-2024-92.xml`, `texto-sin-texto.xml`).
  - Patrón de tests sin red/BD y de carga de fixtures: `BoeXmlParserTest.kt`
    (`recurso("/boe/...")`), `HighlightRankerTest.kt` (puro, in-memory).
- Estructura de `:backend`: paquetes `infra/`, `ingesta/{sumario,publicacion,job,
  backfill,categorizacion}`, `persistence/`, `relevance/`, `plugins/`; **no**
  existe `rag/`.

### Existing Patterns To Follow

- **Componente puro y determinista** como `relevance/HighlightRanker` o
  `ingesta/categorizacion/PublicationClassifier`: clase sin dependencias de red/BD/
  reloj, con KDoc y constantes documentadas.
- **Modelo interno sin sufijo** para dominio/valor no serializable
  (p. ej. `EntradaSumario`): el fragmento de dominio va **sin** sufijo; la fila de
  persistencia ya es `FragmentEntity`.
- **Identificadores en inglés**; KDoc y comentarios en castellano.
- **Estilo MUST**: `return` único por función, sin `else if`, funciones ≤40 líneas,
  reutilizar antes de escribir, crear la capa que falte.
- **Tests** `kotlin.test` en espejo del paquete; fixtures en `src/test/resources`;
  sin red ni BD en el gate.
- **Texto ya normalizado**: `BoeXmlParser` entrega el texto por líneas de párrafo
  con el espacio duro ya convertido en espacio normal; el chunker **no** re-normaliza.

### Current Gaps

- No existe paquete `rag/` ni ningún modelo de fragmento de dominio (solo
  `FragmentEntity`, provisional, de FT00008).
- No existe lógica de chunking.

## Technical Approach

1. **Nuevo paquete `rag/`** (capa de dominio RAG, pura; futuras features añaden
   subpaquetes de embeddings/recuperación). Ficheros:
   - `rag/Fragment.kt`: modelo de dominio `Fragment` (sin sufijo) —
     `publicationId: String`, `order: Int`, `reference: String?`, `content: String`.
     KDoc: representa un fragmento listo para vectorizar; el `id` de BD lo añade la
     persistencia.
   - `rag/chunking/ArticleChunker.kt`: el chunker puro.

2. **Algoritmo del chunker** (determinista, sobre `Publicacion.texto`):
   1. Si `texto` es `null`/en blanco → `emptyList()` (sin excepción).
   2. Partir en líneas por `\n`, `trim`, descartar vacías (el parser ya las
      normalizó).
   3. **Detectar encabezados** con una `Regex` anclada a inicio de línea:
      `^(Artículo|Disposición)\b` (cubre `Artículo 1.`, `Artículo 2 bis.`,
      `Disposición adicional única.`, `Disposición final tercera.`). Toda línea que
      no sea encabezado es cuerpo.
   4. **Bloques**: cada encabezado inicia un bloque (encabezado + cuerpo hasta el
      siguiente encabezado). Las líneas previas al primer encabezado forman un
      bloque **introductorio** (preámbulo). En documentos sin encabezados, todo el
      texto es un único bloque.
   5. **Empaquetado con presupuesto**: recorrer las líneas del bloque y acumular en
      un fragmento hasta que añadir la siguiente línea supere `MAX_TOKENS`
      (estimación, ver paso 6); entonces se cierra el fragmento y se abre otro
      **con la misma `reference`**. Un bloque nunca mezcla dos encabezados.
   6. **Estimación de tokens** (provisional, documentada): `estimateTokens(texto) =
      (texto.length + CHARS_PER_TOKEN - 1) / CHARS_PER_TOKEN` con
      `CHARS_PER_TOKEN = 3` (conservador para español; el tokenizador real E5 llega
      con FT00015 y podrá recalibrarse). `MAX_TOKENS = 512`.
   7. **Línea indivisible** (un solo párrafo > presupuesto, p. ej. en V.B): dividir
      esa línea por **palabras** en partes consecutivas ≤ presupuesto, sin repetir
      ni perder palabras; una palabra sola mayor que el presupuesto (URL larga) se
      trocea por caracteres. (Se factoriza en helpers para respetar ≤40 líneas.)
   8. **`reference`**: para bloques con encabezado, la **línea de encabezado**
      (p. ej. `Artículo 4. Convocatoria.`); para el bloque introductorio y para
      documentos sin encabezados, `"Sección " + publicacion.seccion.name`
      (p. ej. `Sección II_B`). Constante documentada `SECTION_REFERENCE_PREFIX`.
   9. Descartar cualquier fragmento con `content` en blanco y asignar
      `order = 0..n-1` en orden de documento.

3. **API pública**:
   ```kotlin
   class ArticleChunker(
       private val maxTokens: Int = MAX_TOKENS,
       private val charsPerToken: Int = CHARS_PER_TOKEN,
   ) {
       fun chunk(publicacion: Publicacion): List<Fragment>
   }
   ```
   Sin interfaz (patrón de `HighlightRanker`/`PublicationClassifier`); parámetros
   con default para permitir que FT00015 inyecte un contador real sin cambiar la
   firma.

4. **Mapeo a persistencia**: extensión pura `fun Fragment.toEntity(): FragmentEntity`
   (en `persistence/FragmentRepository.kt`, capa de datos → depende del dominio
   `rag.Fragment`, dirección correcta). **No** se invoca el repositorio ni se abre
   conexión; solo cierra el encaje con `FragmentEntity` y deja el fragmento "listo
   para persistir".

5. **Sin wiring**: `Application.kt`, `:shared`, `:composeApp`, la raíz del build,
   `settings.gradle.kts`, migraciones y CI quedan intactos.

**Riesgos clave:** (a) la **estimación de tokens** es aproximada y debe calibrarse
con el tokenizador real en FT00015 (se documenta y se deja inyectable); (b) la
detección de encabezados es **heurística por texto** (el `class="articulo"` del XML
no llega a `Publicacion.texto`): una línea de cuerpo que empiece por «Artículo»/
«Disposición» podría tratarse como encabezado (mitigado con el anclaje a inicio de
línea y validación con fixtures reales); (c) las secciones irregulares pueden
producir fragmentos heterogéneos (tablas/líneas sueltas) — se acepta y se valida
con datos reales; (d) no se anticipa embedding/HNSW (FT00016).

## Expected File Changes

Rutas en el repo de producto (`..`):

- `backend/src/main/kotlin/…/backend/rag/Fragment.kt` — create; modelo de dominio
  del fragmento.
- `backend/src/main/kotlin/…/backend/rag/chunking/ArticleChunker.kt` — create;
  chunker puro.
- `backend/src/main/kotlin/…/backend/persistence/FragmentRepository.kt` — modify;
  extensión `Fragment.toEntity()` (sin tocar la interfaz existente).
- `backend/src/test/kotlin/…/backend/rag/chunking/ArticleChunkerTest.kt` — create;
  tests sin red ni BD con fixtures reales (cubre escenarios 1–7, incluido el mapeo).
- `docs/desarrollo-local.md` — modify (producto); nota del chunking y de la
  estimación provisional de tokens.

Harness: `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0009` + índice,
`.agents/skills/rag-datapublico/SKILL.md`, `feature_list.json`, `PROGRESS.md`
(ver *Durable Documentation Impact*).

**Sin cambios** en `Application.kt`, `:shared`, `:composeApp`, la raíz del build,
`settings.gradle.kts`, las migraciones Flyway ni `.github/workflows/ci.yml`.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI.

## Durable Documentation Impact

- `ARCHITECTURE.md`: update — `:backend` añade el paquete **`rag/`**
  (`ArticleChunker` puro + modelo `Fragment`); subraya que es determinista, sin
  red/BD/wiring, y que embeddings (FT00015) y pgvector/HNSW (FT00016) no se
  anticipan.
- `CONSTRAINTS.md`: update — nueva sección «RAG / fragmentación» con MUST: el
  chunking es **puro y determinista** sobre `Publicacion.texto`; fragmenta por
  **artículo/disposición** conservando la **referencia** y cubriendo el texto
  **sin solapamientos**; respeta **≤512 tokens** por fragmento (con estimación
  provisional documentada e inyectable hasta FT00015); **no** anticipa
  embeddings/HNSW ni escribe en BD; sin wiring en el arranque.
- `AGENTS.md`: not needed — no cambia flujo ni camino de arranque.
- **ADR `docs/adr/0009-…`** (recomendado): registrar la decisión durable
  «fragmentación determinista por artículo/disposición con variante por sección,
  referencia conservada, cobertura sin solapamiento y presupuesto de tokens con
  estimación provisional». El planner **no** lo crea; lo escribe el
  implementador/orquestador e inscribe el índice en `docs/adr/README.md`.
- Skill `.agents/skills/rag-datapublico/SKILL.md`: update — añadir a §1 el
  **estado actual de producto** (implementado en `:backend` `rag/chunking/`) y la
  nota de que la estimación de tokens es provisional hasta FT00015.
- Otros: `docs/desarrollo-local.md` (producto) — update; `README.md`/`ROADMAP.md`,
  `docs/domain-model.md` — not needed.

## Implementation Plan

1. Crear el paquete `rag/` con el modelo `Fragment.kt`.
2. Implementar `ArticleChunker` (detección de encabezados, bloques, empaquetado por
   presupuesto, división de líneas largas, `reference`, `order`), con KDoc y
   constantes documentadas.
3. Añadir la extensión `Fragment.toEntity()` en `persistence/FragmentRepository.kt`.
4. Escribir `ArticleChunkerTest` con los fixtures reales (escenarios 1–7) y
   ejecutarlo.
5. Ejecutar el gate completo sin red ni BD y actualizar la documentación durable
   (ARCHITECTURE, CONSTRAINTS, ADR 0009 + índice, skill RAG, `docs/desarrollo-local.md`);
   `PROGRESS.md`/`feature_list.json` los cierra el orquestador.

## Implementation Tasks

- [ ] `rag/Fragment.kt`: modelo de dominio (sin sufijo) + KDoc.
- [ ] `rag/chunking/ArticleChunker.kt`: `chunk(publicacion): List<Fragment>` puro.
- [ ] Detección de encabezados `Artículo`/`Disposición` anclada a inicio de línea.
- [ ] Empaquetado por bloques con `MAX_TOKENS=512` y `CHARS_PER_TOKEN=3`
      (inyectables), referencia conservada y `order` contiguo.
- [ ] División de líneas/palabras indivisibles sin pérdida ni solapamiento.
- [ ] `persistence/FragmentRepository.kt`: extensión `Fragment.toEntity()`.
- [ ] `ArticleChunkerTest` sin red/BD con los 9 fixtures (escenarios 1–7).
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0009 + índice,
      `rag-datapublico/SKILL.md`, `docs/desarrollo-local.md`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red ni BD:** `./gradlew :backend:test --rerun-tasks` → BUILD
  SUCCESSFUL con `ArticleChunkerTest` en verde (0 fallos) y el resto de `:backend`
  intacto. `./gradlew build --no-daemon -PskipClient` (incluye `:backend:detekt` y
  `:cpdCheck`), `./gradlew test`, `./gradlew detekt` y
  `env -u JAVA_HOME .harness/init.sh` → exit 0.
- **Sin red/BD:** ningún test nuevo abre sockets ni conexión (solo strings y
  fixtures locales); confirmar por inspección que no se importa nada de
  `infra/Database*` ni de `java.sql`.
- **Escenarios 1–7** cubiertos por `ArticleChunkerTest` (norma por artículos,
  cobertura sin solapamiento, sección irregular, artículo largo, determinismo y
  `order`, texto nulo, mapeo a `FragmentEntity`).
- **E2E:** no aplica — sin flujo de usuario ni endpoint nuevo.
- `init.sh` (harness): **no** se modifica.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con `ArticleChunkerTest` (recuento de tests,
  0 fallos) y de los escenarios de cobertura/referencia sobre fixtures reales.
- Gate sin red ni BD: `build -PskipClient`, `test`, `detekt`, `init.sh` (exit 0).
- Ficheros del commit `FT00014`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `rag/` (chunker + modelo) + mapeo `Fragment.toEntity`
      + tests + docs; **sin** embeddings/ONNX (FT00015), **sin** columna
      vectorial/HNSW ni migración (FT00016), **sin** recuperación (FT00017), sin
      resúmenes/IA, sin endpoints ni wiring en `Application.kt`.
- [ ] Escenarios 1–7 pasan sobre **fixtures reales** del BOE; toda prueba corre sin
      red ni BD.
- [ ] Cobertura verificada: la concatenación reproduce las líneas del texto sin
      duplicar ni perder; `order` contiguo `0..n-1`; determinismo.
- [ ] Cada fragmento respeta el presupuesto; la estimación de tokens está
      documentada y es inyectable; no se anticipa el tokenizador de FT00015.
- [ ] `reference` conserva el encabezado de artículo/disposición o la sección.
- [ ] `return` único, sin `else if`, funciones ≤40 líneas y KDoc en castellano con
      identificadores en inglés.
- [ ] El gate sigue verde sin red ni BD; `ARCHITECTURE.md`, `CONSTRAINTS.md`,
      ADR 0009, `rag-datapublico/SKILL.md`, `docs/desarrollo-local.md`,
      `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] No unrelated product behavior or extra feature work was added.

## Risks / Open Questions

- **Estimación de tokens provisional.** El presupuesto usa longitud de caracteres
  (`charsPerToken = 3`) porque el tokenizador real E5 es de FT00015. Es conservador
  (favorece no superar 512 tokens reales) pero puede fragmentar de más. FT00015
  deberá calibrar o inyectar el contador real; el constructor ya lo permite.
  **Confirmar el valor `charsPerToken` si el dueño tiene una referencia.**
- **Detección heurística de encabezados.** `Publicacion.texto` no conserva el
  `class="articulo"` del XML, así que se detecta por patrón anclado a inicio de
  línea. Riesgo de falsos positivos (línea de cuerpo que empiece por «Artículo»/
  «Disposición»), mitigado con validación sobre fixtures reales; una vía futura
  sería que el parser preserve el marcado de encabezado (fuera de alcance).
- **Secciones irregulares.** II.A/II.B/IV/V.A/V.B/V.C no tienen artículos y su
  texto incluye tablas/listas que llegan como líneas sueltas; los fragmentos serán
  heterogéneos. Se acepta para la 1.0.0 y se valida con datos reales (riesgo ya
  registrado en `risks-and-open-questions.md`).
- **`CHARS_PER_TOKEN = 3`** es una elección conservadora de partida; si genera
  demasiados fragmentos en la práctica, ajustar antes de FT00015.
- **`FragmentEntity` aún sin embedding.** El mapeo no lo incluye; FT00016 añadirá
  la columna y el índice vía migración nueva, sin tocar FT00014.
