# Constraints — DatoPublico

> Reglas operativas **MUST / MUST NOT** que toda feature debe respetar. Añade
> aquí solo restricciones durables que futuras features deban cumplir.

## Producto y datos

- **MUST**: cada resumen publicado lleva enlace visible a la **fuente oficial**.
- **MUST NOT**: cuentas de usuario ni almacenamiento de datos personales **de
  quien usa la app** (nada de perfiles); el contenido del BOE es información
  pública y **nunca se restringe**.
- **MUST NOT**: analítica o telemetría de uso.
- **MUST**: el chat verifica **solo** contra el corpus del BOE (sin fuentes
  externas) y **no** persiste historial en el servidor.
- **MUST**: el aviso de contenido generado por IA es visible.
- **MUST**: el corpus de la 1.0.0 es **todo el sumario del BOE** (secciones I,
  II.A, II.B, III, IV, V.A, V.B y V.C) y se usan **todos los campos** que ofrece
  la API. Ninguna sección ni campo del BOE se excluye por «datos personales» ese
  principio aplica solo a los datos de los usuarios de la app.

## Fuentes externas (ingesta)

- **MUST**: el contenido remoto del BOE se trata como **no confiable**. El XML
  estructurado (`xml.php`) se parsea con *secure processing* del parser del JDK y
  con **DTD y entidades externas deshabilitadas** (`disallow-doctype-decl`,
  `ACCESS_EXTERNAL_DTD`/`ACCESS_EXTERNAL_SCHEMA` vacíos, sin expandir
  referencias), para evitar XXE y *billion laughs*.
- **MUST**: la descarga del texto oficial es una **llamada de red** y queda sujeta
  a la regla de tests opt-in (`BOE_LIVE_TEST=1`) de la sección «Operación»;
  nunca se ejecuta en el gate ni en la CI.
- **MUST**: las **llamadas de red del backend** fijan un `HttpTimeout` explícito
  (conexión ~10 s, petición/socket ~30 s) para que una descarga colgada del BOE no
  bloquee indefinidamente la ventana del job (FT00009).

## IA y coste

- **MUST**: embeddings **locales** (`multilingual-e5-small` int8, ONNX), tras una
  interfaz de proveedor.
- **MUST**: generación y chat por **OpenCode**, tras una interfaz intercambiable;
  la clave vive **solo** en el servidor.
- **MUST**: cachear resúmenes por publicación y aplicar **rate limiting** al chat.
- **MUST NOT**: publicar afirmaciones fuera del contexto recuperado (si el corpus
  no lo sustenta, se declara `sin_fundamento`/`refutada`).

## Contrato del resumen ciudadano

- **MUST**: todo resumen ciudadano cumple el **contrato** validado en `:shared`
  (`validation/CitizenSummaryValidator`, FT00019): **fuente oficial obligatoria**
  como enlace absoluto `http(s)://`, «¿Qué cambia?» y «¿A quién afecta?» no vacíos
  y «Cifras clave» sin entradas en blanco (la lista **puede** estar vacía). Decisión
  durable en `docs/adr/0014`.
- **MUST**: la **variante** de empleo público y becas
  (`OPOSICIONES_Y_EMPLEO_PUBLICO`, `BECAS_SUBVENCIONES_Y_AYUDAS`) exige **plazo**
  con `fechaLimite` no vacía; el resto de categorías no lo exigen. La variante es un
  **valor interno** (sin `Dto`, no `@Serializable`).
- **MUST**: el validador del contrato es **puro** (sin red, BD, reloj ni estado),
  **acumula violaciones y no lanza**: un resumen inválido es un resultado esperado
  (lo consumirán FT00022/FT00023), no un error de programación. Se distingue del
  *fail-fast* de configuración (`PgVector`, `SearchFilterSql`), que sí son errores
  de programación.
- **MUST NOT**: este validador comprueba solo el **contrato** (estructura y
  presencia de la fuente), **no la veracidad**: la **alcanzabilidad** del enlace y
  las afirmaciones fuera del contexto recuperado son **guardrails de contenido**
  (FT00022). Tampoco cambia el **contrato de wire** de `ResumenDto` (congelado).

## Generación de resumen ciudadano

- **MUST**: el **proveedor de texto** va tras una **interfaz intercambiable**
  (`rag/generation/TextGenerationProvider`, `suspend`); OpenCode la implementa
  (`OpenCodeTextGenerationProvider`) y es la **única** pieza que conoce Ktor/HTTP.
  La **clave** vive **solo en el servidor** (`OPENCODE_API_KEY` por entorno; nunca
  versionada ni en logs) y su ausencia es **fail-fast** (`TextGenerationException`).
  Decisión durable en `docs/adr/0015`.
- **MUST**: la **fuente oficial se inyecta** de forma determinista desde
  `Publicacion.urlOficial` (`SummaryGenerationDto.toResumenDto`) y `avisoIA = true`;
  **nunca** la produce el modelo. La salida del modelo solo aporta «¿Qué cambia?»,
  «¿A quién afecta?», «Cifras clave» y, si procede, el plazo.
- **MUST**: la salida se **valida** con `CitizenSummaryValidator` (FT00019); un
  resumen que no cumple el contrato **no se publica**: el servicio devuelve
  `CitizenSummaryResult.Invalid` con las violaciones (resultado tipado, **no** una
  excepción). Una salida **no parseable** (vacía o JSON inválido) es un fallo
  distinto: lanza `SummaryGenerationException` tipada.
- **MUST**: el prompt trabaja **solo** con el contexto recuperado y lo delimita
  como **datos, no instrucciones**; la variante de empleo/beca
  (`OPOSICIONES_Y_EMPLEO_PUBLICO`, `BECAS_SUBVENCIONES_Y_AYUDAS`) pide **plazo**.
  `publication.categoria` nula es **fail-fast** (`IllegalArgumentException`) antes
  de recuperar o invocar al proveedor.
- **MUST NOT**: la generación es una **librería sin wiring**: **no** se construye
  en `Application.kt`/job/backfill, no añade endpoints/UI ni migración, y **no**
  anticipa lo diferido — **sin** cacheo ni control de coste (FT00021), **sin**
  guardrails de contenido/alcanzabilidad (FT00022), **sin** cola de revisión ni
  aviso de IA (FT00022/FT00023) y **sin** chat (FT00025). No se modifican
  `ResumenDto`/`CitizenSummaryValidator`/`HybridSearch` (se reutilizan).
- **MUST**: la prueba real contra OpenCode es **opt-in**
  (`OPENCODE_LIVE_TEST=1`, fail-fast sin clave), fuera de `build`/`test`/`init.sh` y
  de la CI; el gate cubre config, proveedor (`MockEngine`), parser, prompt y servicio
  con **dobles deterministas**, sin red ni BD.

## Categorización y plazos

- **MUST**: la categoría de una publicación es una **regla curada determinista**
  a partir de la **sección** y el **epígrafe** (con el título como respaldo), sin
  IA/LLM ni embeddings; el clasificador es **puro** y **siempre** devuelve una
  `CategoriaDto` (nunca `null`), cayendo en la categoría por defecto de la
  sección, y **conserva** el epígrafe original como metadato. Decisión durable en
  `docs/adr/0007`.
- **MUST**: la extracción del plazo de solicitud es **heurística y acotada**
  (patrones concretos + puerta de contexto y descarte de ejecución/resolución/
  recurso/subsanación/alegaciones/informe); devuelve **vacío** (`null`) si no es
  fiable y **nunca** inventa una fecha. Los «días hábiles» cuentan solo sábados y
  domingos (sin calendario de festivos), límite documentado.

## Relevancia y destacados

- **MUST**: el ranking de destacados es **automático, objetivo, determinista y
  explicable**: usa **señales objetivas documentadas** (sección normativa, rango
  normativo, categoría curada, plazo abierto y organismo de una lista curada y
  modesta), **sin IA/LLM ni señales editoriales o subjetivas**, y **cada
  destacado expone su motivo** (`HighlightReason`, nunca vacío). Es **puro** (sin
  red, BD, reloj, aleatoriedad ni estado) y su salida **no depende del orden de
  entrada**; un día sin señales devuelve lista vacía. La señal de organismo es
  **modesta** y **nunca** decide por sí sola un destacado. Decisión durable en
  `docs/adr/0008`.
- **MUST**: en la 1.0.0 los destacados se **calculan *on-the-fly*** sobre la lista
  del día (`PublicationRepository.listByDate`), **no se persisten**: no hay
  columna, migración, repositorio ni segunda pasada en el job/backfill.

## RAG / fragmentación

- **MUST**: el **chunking es puro y determinista** sobre `Publicacion.texto`
  (paquete `rag/` de `:backend`; `rag/chunking/ArticleChunker`): sin IA/LLM, red,
  base de datos, reloj, aleatoriedad ni estado; la misma `Publicacion` produce
  siempre la misma lista. Decisión durable en `docs/adr/0009`.
- **MUST**: se fragmenta por **artículo/disposición** conservando su
  **referencia** (la línea de encabezado) y con **variante por sección** para las
  secciones sin artículos (II.A/II.B/IV/V.A/V.B/V.C: `reference = "Sección " +
  seccion.name`). El texto se cubre **sin solapamiento**: la concatenación de los
  fragmentos reproduce las líneas del texto de origen, en orden, sin repetirlas ni
  omitirlas.
- **MUST**: cada fragmento respeta el presupuesto del modelo E5 (**≤512 tokens**),
  con una **estimación provisional documentada e inyectable** por constructor
  (`charsPerToken = 3` por defecto) mientras el chunker se mantiene **puro**;
  FT00015 **expone** el tokenizador real (`countTokens`) sin modificar
  `ArticleChunker`, y la inyección/calibración del contador real en el chunker
  queda **diferida** (no forma parte de FT00016, que solo almacena vectores); un
  párrafo que supere el presupuesto se parte por palabras y conserva la misma
  `reference`. `order` es **contiguo** `0..n-1` en orden de documento.
- **MUST NOT**: la fragmentación **no anticipa lo diferido** — sin embeddings/ONNX
  en el propio chunker (FT00015), sin columna `embedding vector(384)` ni índice
  HNSW ni migración (FT00016), sin recuperación (FT00017) — y **no** escribe en
  PostgreSQL ni se cablea en `Application.kt`/job/backfill. El encaje con la
  persistencia es solo el mapeo puro `Fragment.toEntity()` (`id = null`, sin abrir
  conexión).

## Almacenamiento vectorial (pgvector)

- **MUST**: el embedding de `fragmento` es la columna **`embedding vector(384)`
  nullable** (dimensión del modelo E5 `-small`) con índice **HNSW**
  `vector_cosine_ops` (`m = 16`, `ef_construction = 64`), creada en la migración
  `V3`. Decisión durable en `docs/adr/0011`.
- **MUST**: el vector se guarda y consulta como **literal textual** (`[v1,v2,…]`,
  formato independiente del *locale*) enlazado con el *cast* `?::vector`, **sin
  ORM** y sin depender de `PGobject`; `PgVector` (puro) valida la dimensión **384**
  con **fail-fast** (`IllegalArgumentException`) **antes** de tocar la base de
  datos.
- **MUST**: `findNearest` filtra los fragmentos **sin embedding**
  (`embedding IS NOT NULL`) y ordena por **distancia coseno** ascendente; `limit`
  debe ser `>= 1` (fail-fast). **Sin** filtros de metadatos: la recuperación
  híbrida es de FT00017.
- **MUST**: la prueba real de similitud e índice HNSW es **opt-in**
  (`DB_LIVE_TEST=1`) contra el PostgreSQL de `docker-compose`, fuera de
  `build`/`test`/`init.sh` y de la CI; el gate cubre la conversión pura
  (`PgVectorTest`) y el contrato SQL de `V3`
  (`FragmentEmbeddingMigrationSqlTest`) sin red ni BD. `saveEmbedding` **no**
  crea el fragmento: la fila la crea `save` (FT00008/FT00014).

## Embeddings locales

- **MUST**: los embeddings son **locales** (`intfloat/multilingual-e5-small` int8)
  vía **ONNX Runtime en CPU**, tras una **interfaz intercambiable**
  (`EmbeddingProvider`); el resto del pipeline no conoce ONNX ni el modelo. El
  tokenizador XLM-R es el de DJL (`HuggingFaceTokenizer`) sobre un
  `tokenizer.json` local. Decisión durable en `docs/adr/0010`.
- **MUST**: se aplican los **prefijos obligatorios** `query: ` (consulta) y
  `passage: ` (fragmento); los vectores se **normalizan** (L2) y tienen **384
  dimensiones**; la entrada se recorta a **≤512 tokens**; el proveedor expone el
  **contador real** `countTokens` (cierre del provisional de FT00014).
- **MUST NOT**: el modelo (`model.onnx`, ~118 MB) y el `tokenizer.json` **no** se
  versionan ni se descargan en `build`/`test`/`init.sh`/CI; viven en
  `backend/models/` (**gitignored**), se aprovisionan con
  `backend/tools/download-embedding-model.sh` y se referencian por **ruta
  absoluta** de entorno (`EMBEDDING_MODEL_PATH`/`EMBEDDING_TOKENIZER_PATH`) con
  **fail-fast** (`EmbeddingException`) si faltan o no existen, **sin** *fallback*
  ni descarga silenciosa.
- **MUST**: la prueba contra el **modelo real** es **opt-in**
  (`EMBEDDING_LIVE_TEST=1`), fuera de `build`/`test`/`init.sh`/CI; el gate cubre el
  contrato y la aritmética con **dobles deterministas** (sin red ni artefactos).
- **MUST NOT**: el proveedor de embeddings (FT00015) **no** se cablea en
  `Application.kt`/job/backfill; el **almacenamiento** vectorial vive en
  `persistence/` (FT00016, `embedding vector(384)` + HNSW) y la **recuperación
  híbrida** (FT00017) es quien combina proveedor y repositorio.

## Recuperación híbrida e indexado

- **MUST**: la recuperación híbrida (FT00017) filtra **solo** por los metadatos
  existentes (`fecha_publicacion`, `categoria`, `seccion`, `organismo`) **combinados
  con `AND`** y siempre **parametrizados** (`?`, nunca concatenando entrada); el
  `SearchFilter` es un valor interno (sin sufijo, **no** `@Serializable`) y su
  traducción a SQL (`SearchFilterSql.whereClause`/`parameters`) es **pura**, con
  orden documentado y coherente. Las fechas ISO-8601 se enlazan como **texto con
  *cast* `?::date`** y una fecha no ISO falla con `IllegalArgumentException`
  **antes** de tocar la base de datos. Decisión durable en `docs/adr/0012`.
- **MUST**: `FragmentRepository.findNearest(queryEmbedding, filter, limit)` filtra
  los fragmentos **sin embedding** (`embedding IS NOT NULL`), aplica el filtro vía
  `JOIN publicacion` y ordena por **distancia coseno** ascendente; el `findNearest`
  de 2 argumentos (FT00016) **delega** con `SearchFilter()` sin romper su contrato.
  `limit < 1`, dimensión ≠384 o fecha no ISO son **fail-fast**
  (`IllegalArgumentException`) antes de abrir la conexión.
- **MUST**: la **composición** proveedor de embeddings + repositorio de fragmentos
  vive en **`rag/`** (servicios `HybridSearch` en `rag/retrieval/` y
  `FragmentIndexer` en `rag/indexing/`), **no** en `persistence/`; se **extiende**
  la interfaz existente (`FragmentRepository`) en vez de declarar un *port* nuevo
  para no duplicar SQL. La consulta usa `embedQuery` (prefijo `query: `) y los
  fragmentos `embedPassage` (prefijo `passage: `).
- **MUST**: el indexado mínimo (`FragmentIndexer.index`) es **idempotente** por el
  *upsert* de `(publicacion_id, orden)`: fragmenta (`ArticleChunker`), persiste cada
  fragmento (`save`) y guarda su embedding (`saveEmbedding`), **sin** *batching*,
  sin transacción multi-repositorio y **sin** indexar el corpus completo (operación
  posterior).
- **MUST**: la recuperación y el indexado son una **librería sin wiring**: **no** se
  construyen en `Application.kt` ni en el job/backfill, **no** hay endpoints/UI ni
  migración nueva, y **no** se anticipa lo diferido (evaluación FT00018;
  resúmenes/chat FT00019+; reranking/fusión léxica/índice GIN o trigram y ajuste de
  `ef_search`, que quedan para la evaluación/operación).
- **MUST**: las pruebas reales (filtros sobre PostgreSQL con vectores sintéticos, e
  indexado + recuperación con el modelo E5 real) son **opt-in**
  (`DB_LIVE_TEST=1` y `EMBEDDING_LIVE_TEST=1`), fuera de
  `build`/`test`/`init.sh`/CI; el gate cubre la traducción SQL, el servicio y el
  indexado con **dobles deterministas**, sin red ni BD.

## Evaluación de recuperación

- **MUST**: el **golden set** de evaluación es **versionado** en los recursos de
  `:backend` (`rag/eval/golden-set.json`) y su estructura y validaciones son las
  del spec FT00018: `k >= 1`, corpus y consultas no vacíos, ids únicos y **cada
  fragmento relevante existente en el corpus** (`publicationId` presente y
  `order >= 0`). Un dataset inválido falla con `IllegalArgumentException` **sin**
  abrir conexión. Decisión durable en `docs/adr/0013`.
- **MUST**: las métricas de recuperación (`precision@k`, `recall@k` y MRR) son
  **puras** (sin red, BD, modelo, reloj ni estado) y testables en el gate con
  dobles deterministas; el evaluador **agrega medias sin `NaN`** (media de una
  lista vacía = `0.0`) y **no** conoce el proveedor de embeddings ni Ktor.
- **MUST**: la evaluación **no cambia la recuperación**: reutiliza
  `SearchFilter`/`HybridSearch`/`FragmentIndexer` tal cual. La ejecución real es
  **opt-in** (`DB_LIVE_TEST=1` + `EMBEDDING_LIVE_TEST=1`) con la tarea
  `:backend:evaluateRetrieval` **fuera** de `build`/`check`/`init.sh` y de la CI;
  el test live afirma un **umbral conservador y documentado** (no perfección).
- **MUST NOT**: la evaluación **no persiste el histórico** (log JSON estructurado
  `event=retrieval.evaluation.*` + stdout) ni añade migración; **no** se cablea en
  `Application.kt`/job/backfill y **no** se anticipa lo diferido (resúmenes/chat,
  endpoints/UI, reranking/fusión léxica, indexado del corpus completo).

## Persistencia y base de datos

- **MUST**: el acceso a datos usa **JDBC + HikariCP**, **sin ORM** (nada de
  Exposed/Hibernate). Los repositorios viven en `persistence/` (interfaz +
  entidad `...Entity` + implementación JDBC) y el pool/configuración en `infra/`;
  la conexión se **deriva** de `POSTGRES_*` (fuente única). Decisión durable en
  `docs/adr/0003`.
- **MUST**: la escritura de una publicación es **upsert por `id`**
  (`INSERT … ON CONFLICT (id) DO UPDATE`), **idempotente**: reejecutar la ingesta
  (FT00009) no crea filas duplicadas.
- **MUST**: las pruebas que **tocan la base de datos real** son **opt-in** por
  `DB_LIVE_TEST=1` contra el PostgreSQL de `docker-compose`, y quedan **fuera**
  de `build`/`test`/`init.sh` y de la CI (patrón `BOE_LIVE_TEST`). El gate cubre
  config de conexión, mapeo y contrato SQL de la migración **sin** PostgreSQL.
- **MUST**: las migraciones Flyway son versionadas y **nunca** se edita una ya
  aplicada (`V1`/`V2`/`V3`); lo diferido (p. ej. los filtros de metadatos de la
  recuperación híbrida, FT00017) **no** se anticipa.

## Nombres y contratos

- **MUST**: **todo el código va en inglés**. Los **identificadores** (paquetes,
  tipos, funciones, propiedades, constantes, parámetros, variables y los nombres
  de clases y métodos de test) se escriben en **inglés**; no se introducen
  identificadores en castellano. El **KDoc y los comentarios** van en castellano
  (idioma de la documentación del proyecto), igual que los mensajes dirigidos al
  operador. No se traducen los identificadores que son **datos/tokens de la
  fuente** (p. ej. los valores de wire de `CategoriaDto`/`SeccionBoeDto`). El
  código anterior a esta regla con identificadores en castellano es **deuda** a
  renombrar de forma incremental (FT00047); el código nuevo no añade más.
- **MUST**: **todo tipo `@Serializable`/de transporte** lleva sufijo `Dto`: el
  contrato de `:shared` — las `data class` (`PublicacionDto`, `ResumenDto`,
  `PlazoDto`, `ResumenDiarioDto`) y los **enums de wire** (`CategoriaDto`,
  `SeccionBoeDto`) — y también los DTOs de transporte de `:backend`
  (`HealthDto`, `BoeSumarioResponseDto`, `BoeSeccionDto`…). La configuración de
  serialización no es un tipo de contrato y va sin `Dto` (`DatoPublicoJson`).
- **MUST**: en las capas internas, entidades de persistencia `...Entity`, filas
  `...Row` y modelos de UI `...Ui`. Un **modelo de dominio/valor interno** que no
  sea serializable ni `Entity`/`Row`/`Ui` va **sin sufijo** (p. ej.
  `EntradaSumario`). Sin prefijos en ningún caso.

## Serialización (kotlinx.serialization)

- **MUST**: en todo tipo `@Serializable`, **cada propiedad** lleva `@SerialName`
  explícito, **aunque el nombre Kotlin coincida** con la clave JSON; no se confía
  en el nombre por defecto. Aplica al contrato de `:shared` y a los DTOs de
  transporte de `:backend`. Los valores de los enums de wire también llevan su
  `@SerialName`.

## Estilo de código

- **MUST**: cada función/método tiene **una sola salida** (`return` único);
  prohibido el *early return* (retornos intermedios). Se resuelve con expresiones
  (`when`, operador Elvis, `if`/`else` como expresión, `buildList`, etc.). Aplica
  **también a los tests**. Los códigos de salida temprana de lambdas etiquetadas
  (`return@…`, p. ej. `return@runTest`) se evitan igualmente: usa guardas `if` y
  deja el cuerpo sin salidas etiquetadas.
- **MUST**: **no** se usa `else if`. Las cadenas de guardas se resuelven con
  `when` (`when { cond -> …; else -> … }`), como expresión o como sentencia. Un
  `if` simple de dos ramas sigue permitido.
- **MUST**: las funciones son **cortas y con una sola responsabilidad**: máximo
  **40 líneas** (objetivo **30**), sin contar KDoc, comentarios ni líneas en
  blanco. Si se supera, se **extraen** sub-funciones o componentes.
- **MUST**: **reutilizar antes de escribir**. Antes de crear UI o lógica nueva,
  busca un componente/función equivalente en **todo** el repositorio (no solo en
  la feature en curso). Si lo van a usar **≥2 features**, muévelo a
  `design/components/`; si es de una sola feature, a `feature/<nombre>/ui/components/`.

## Documentación de código (KDoc)

- **MUST**: todo el código Kotlin que se añada o modifique lleva documentación
  **KDoc** (`/** … */`): clases, interfaces, objetos, funciones, propiedades y
  tipos públicos, con `@param`/`@property`/`@return`/`@throws`/`@see` cuando aporten.
- **MUST**: documentar el **porqué** de lo no obvio (contratos, invariantes,
  efectos secundarios, límites), no solo el qué. El KDoc vive junto al código; no
  se duplica en `docs/` lo que ya explica el KDoc.
- Un cambio que añade o modifica API sin KDoc es motivo de revisión en el PR.

## Arquitectura por capas: crear la capa que falte

- **MUST**: al añadir código, si la **capa o directorio** que le corresponde según
  la arquitectura **no existe todavía**, se **crea** y se coloca ahí; nunca en un
  paquete plano o en la capa equivocada «porque aún no existe».
- **MUST**: al implementar una feature, si falta una capa (p. ej. `domain/` o
  `data/`) se crea con sus componentes mínimos (interfaz + implementación, caso de
  uso, ViewModel…). No se inventan capas ni nombres nuevos: se siguen las skills
  `ktor-backend-architecture`, `compose-multiplatform-architecture` y
  `rag-datapublico` y `ARCHITECTURE.md`.

## Cliente (Compose Multiplatform)

- **MUST**: la **UI compartida** de `:composeApp` vive en `commonMain`; cada
  plataforma aporta **solo su entrypoint** (Android `MainActivity`, Wasm `main()`,
  iOS `MainViewController`). No duplicar pantallas por plataforma.
- **MUST**: el gate estándar (`./gradlew build -PskipClient`, `.harness/init.sh`
  por defecto) **no** exige el Android SDK ni arranca Xcode; el cliente
  (`:composeApp`) se añade con `--with-client`/`--with-ios`/`--with-all`. Los targets
  iOS se ignoran en hosts no-Apple y los tests de Wasm en navegador (Karma/Chrome)
  quedan fuera del gate.
- **MUST**: toda función `@Composable` de UI (pantallas, componentes y
  sub-composables) incluye al menos una `@Preview` (`org.jetbrains.compose.ui.tooling.preview.Preview`)
  en `commonMain`, junto al composable y dentro del tema. Los composables privados
  se previsualizan en el mismo fichero. Una preview **no** es un test y no autoriza
  tests de vistas/composables.
- **MUST**: **nunca** se provoca a propósito un *crash* que cierre la app. No se usan
  `throw`, `error(...)`, `TODO()` ni asertos como camino de control (en el código de
  producción). Los fallos (red, parseo, permisos, estados inesperados) se **modelan y
  se muestran** como estado gestionado (mensaje, reintento o estado vacío).
- **MUST**: todo texto visible al usuario sale de **recursos**
  (`composeResources/values*/strings.xml`, consumido con `stringResource(Res.string.*)`),
  nunca hardcodeado. La clave existe en **todos** los locales. Solo se permiten
  literales para símbolos tipográficos (flechas, separadores) y en `@Preview`.
- **MUST**: los **iconos con significado** usan **Material Icons**
  (`Icon(Icons.Outlined.*)`), con `contentDescription` cuando transmiten información;
  los glifos Unicode/ASCII se reservan a lo tipográfico dentro de un texto.
- **MUST**: las pantallas leen sus colores **solo** de `MaterialTheme.colorScheme.*`;
  nunca fijan un color de runtime. Los literales de color solo se permiten en `@Preview`.

## Build y repositorios

- **MUST**: el **gate de calidad es bloqueante**: `./gradlew detekt` ejecuta Detekt en
  `:backend`, `:shared` y `:composeApp` (config en `config/detekt/detekt.yml`, deuda
  conocida en `config/detekt/<módulo>-baseline.xml`) y, enganchado a él, el chequeo global
  de duplicación **`:cpdCheck`** (CPD de PMD, `language = kotlin`, umbral 100 tokens, barre
  todo `<módulo>/src/**/*.kt` salvo tests). Un hallazgo nuevo o un duplicado rompe el build.
  `check`/`build` lo arrastran, así que `./init.sh` también.
- **MUST**: el **gate estándar es SDK-free**: `./gradlew build -PskipClient` compila y testea
  solo `:shared` y `:backend` (no exige el Android SDK). `:composeApp` se incluye sin el flag
  y exige el Android SDK. `.harness/init.sh` es SDK-free por defecto y añade el cliente con
  `--with-client`/`--with-ios`/`--with-all`. `-PskipClient` lo reutilizará la imagen del backend.
- **MUST**: las distribuciones de herramientas de Kotlin/JS-Wasm (Binaryen, Node,
  Yarn) se declaran como repositorios Ivy en `settings.gradle.kts`, que usa
  `RepositoriesMode.PREFER_SETTINGS`. El plugin de Kotlin/Wasm las registra a
  nivel de proyecto, así que `FAIL_ON_PROJECT_REPOS` rompería el build. Mantén el
  settings como **fuente única de verdad** de repositorios.

## Decisiones y flujo

- **MUST**: las decisiones **durables** (modelo de datos, arquitectura, integración
  externa, despliegue, flujo de trabajo, seguridad) se registran como **ADR** en
  `docs/adr/` (formato e índice en `docs/adr/README.md`); para reabrir una decisión
  aceptada se escribe un ADR nuevo que la supersede/adjusta, no se edita el anterior.
- **MUST**: los PR que cambian la interfaz (`:composeApp` o `DESIGN.md`) llevan
  **capturas antes/después** en `docs/pr/<rama>/` (ver `docs/pr/README.md` y
  `docs/git-workflow.md`). Un cambio visual sin capturas ni justificación no se mergea.
- **MUST**: ningún PR de producto supera los **30 ficheros**; si se excede, se divide
  en partes `FTxxxxx-PTn` (`docs/git-workflow.md`).

## Operación

- **MUST**: ingesta diaria a las **9:30** más una **segunda pasada**; alerta si no
  se ejecuta.
- **MUST**: el backfill histórico es **one-shot**, **idempotente** por *upsert* de
  `id` y **reanudable** (checkpoint **local en fichero**); se ejecuta por **lotes
  con pausa configurable** en baja carga mediante una tarea explícita
  (`./gradlew :backend:backfill`) y **no** se cablea al arranque del servidor ni
  cambia las reglas del gate (sin red ni BD en `build`/`test`/`init.sh`). El
  *runner* **reutiliza** el job diario y no filtra secciones (ADR 0006).
- **MUST**: la observabilidad de la ingesta usa **eventos de log JSON con clave
  `event` estable** (ejecución: `ingestion.run.completed`/`ingestion.run.failed`;
  ventana perdida: `ingestion.missed`) y la alerta de ingesta ausente es un log
  `ERROR`; **sin** alertas externas (email, push, webhooks) ni telemetría. La
  gracia tras una ventana se configura con `INGESTA_GRACE_MINUTES` (default 30).
- **MUST**: migraciones Flyway versionadas; **nunca** editar una ya aplicada.
- **MUST**: el gate de build/tests (`./gradlew build`, `.harness/init.sh`) **no**
  depende de servicios externos (base de datos). Las migraciones se ejecutan con
  una tarea explícita (`./gradlew :backend:flywayMigrate`) y las tareas Flyway
  **nunca** se enganchan a `build`/`check` (la CI corre sin PostgreSQL).
- **MUST**: los tests del gate (`./gradlew build`, `./gradlew test`,
  `.harness/init.sh`) **no** hacen **llamadas de red**. Cualquier prueba contra un
  servicio externo (p. ej. la API de datos abiertos del BOE) es **opt-in** por
  variable de entorno y queda **fuera** de `build`/`test`/`init.sh` y de la CI;
  sin la variable, el test se omite sin abrir sockets (`BOE_LIVE_TEST=1`).
- **MUST NOT**: incluir credenciales en ficheros versionados, **ni siquiera de
  desarrollo** (sin contraseñas literales ni como *fallback* en código, compose,
  CI o plantillas). La única fuente es el entorno/`.env` (ignorado por git); la
  plantilla `.env.example` solo admite *placeholders* explícitos no secretos.
- **MUST**: un secreto ausente debe **fallar con mensaje claro** (fail-fast), no
  caer en un valor por defecto silencioso. `POSTGRES_PASSWORD` es obligatorio en
  `docker-compose` (`:?`) y la contraseña de Flyway no tiene default en el build
  (usa `FLYWAY_PASSWORD` o `POSTGRES_PASSWORD`).
- **MUST NOT**: duplicar la configuración de conexión entre herramientas. Las
  piezas de conexión tienen una **única fuente de verdad** (`POSTGRES_*`, la
  misma que consume `docker-compose`) y las variables propias de cada herramienta
  (`FLYWAY_*`) son solo *overrides* opcionales: cambiar `POSTGRES_PORT` (o
  host/db/usuario) debe bastar para que Flyway apunte al mismo sitio.
- **MUST**: el PostgreSQL local de desarrollo se publica **solo en loopback**
  (`127.0.0.1`), nunca en `0.0.0.0`.
- **MUST**: el arranque del backend **no** depende de la base de datos ni de
  servicios externos: se registran solo los subsistemas/rutas cuyas dependencias
  existen (el healthcheck `GET /health` queda operativo sin PostgreSQL). La
  configuración es **por entorno**, con valores por defecto no sensibles y
  **fail-fast** (arranque abortado con mensaje claro) si un valor es inválido.
- **N100 / 8 GB**: backfill por lotes en baja carga; `shared_buffers` ~1 GB,
  heap JVM ~1 GB, swap activado.
