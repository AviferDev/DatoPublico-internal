# Technical Discovery

## Product Surface

Cliente multiplataforma con **UI compartida**:

- Móvil: Android e iOS.
- Web (Wasm).
- Una sola base de UI en Compose Multiplatform.
- **Detalle de publicación:** se muestra el **resumen ciudadano + enlace a la
  fuente**; no se integra el texto oficial completo.
- **Chat RAG:** consulta en lenguaje natural o **afirmación a verificar** contra
  el corpus del BOE, con respuestas apoyadas en fragmentos recuperados y **citas
  a la fuente oficial**. Entra en el alcance de la 1.0.0. Sin historial
  persistido en el servidor ni fuentes externas.

## Candidate Stack

- **Lenguaje:** Kotlin end-to-end.
- **Backend:** Ktor (jobs programados, ingesta, RAG, API).
- **Cliente:** Compose Multiplatform (Android, iOS, Wasm).
- **Contratos:** `kotlinx.serialization` en módulo `shared`.
- **Persistencia:** PostgreSQL + `pgvector`.
- **Migraciones:** Flyway.
- **HTTP:** Ktor Client.
- **Concurrencia/estado:** coroutines, `StateFlow`, ViewModels compartidos.
- **Build:** Gradle Kotlin DSL con version catalog.
- **IA (proveedor):** interfaz de proveedor abstracta para poder cambiar sin
  tocar código. Reparto: **embeddings locales pequeños** + **generación y chat
  por OpenCode**.
  - **Generación y chat:** **OpenCode** (Zen/Go), endpoint OpenAI-compatible
    `https://opencode.ai/zen/go/v1/chat/completions`. Cubre la simplificación a
    lenguaje claro («traducción» del texto jurídico a resumen ciudadano) y el
    **chat RAG** (consulta en lenguaje natural sobre el corpus, con citas).
    Modelo candidato: `deepseek-v4.1-flash`.
  - **Embeddings:** **modelo local open-source** ejecutado con **ONNX Runtime en
    CPU**: `intfloat/multilingual-e5-small` **cuantizado int8** como modelo por
    defecto (~120 MB, 384 dimensiones, 512 tokens de contexto, prefijos
    `query:`/`passage:`). `-base` (768 dims) queda como alternativa tras la
    misma interfaz, a decidir con una comparación real sobre el corpus.
  - **OpenCode no ofrece endpoint de embeddings.** Por eso los embeddings son la
    única pieza de IA local; la generación y el chat sí van por OpenCode.

## Data and Storage

- PostgreSQL con la extensión `pgvector`.
- Entidades principales: `publicacion` (con categoría, sección y epígrafe),
  `fragmento` (con embedding), `resumen`, `cola_revision`.
- Migraciones con Flyway; backups periódicos.
- Índices vectoriales para búsqueda semántica y filtros SQL por metadatos
  (fecha, categoría, sección, organismo).
- **Corpus:** publicaciones nuevas de **todo el sumario del BOE** (secciones I,
  II.A, II.B, III, IV, V.A, V.B y V.C) del BOE, en **castellano**, más **backfill
  del último año**.
- **Categoría:** enum curado (11 valores) derivado de la sección/epígrafe; se
  conserva también la sección y el epígrafe crudos del BOE.

## Integrations

- **BOE:** API de datos abiertos (sumario diario) y textos oficiales, de **todo
  el sumario**: **I** (disposiciones generales), **II.A** (nombramientos y ceses),
  **II.B** (empleo público), **III** (otras disposiciones), **IV** (Administración
  de Justicia), **V.A** (contratación del sector público), **V.B** (otros anuncios
  oficiales) y **V.C** (anuncios particulares). Sin exclusiones: la API pública se
  consume completa y se guardan todos sus campos.
- **OpenCode (Zen/Go):** generación de resúmenes y chat vía endpoint
  OpenAI-compatible. La clave vive solo en el servidor.
- **Embeddings locales:** `intfloat/multilingual-e5-small` (int8) vía ONNX
  Runtime en CPU, en el propio servidor. Única IA ejecutada en local.
- **Futuras (1.x):** BDNS, PLACSP/PRTR, INE, datos.gob.es, EUR-Lex/CELLAR, TED.

## Authentication and Authorization

- **Sin cuentas en ningún momento.** La API es pública de solo lectura y el
  servidor no almacena datos personales.
- **Watchlist local:** las leyes seguidas viven en el dispositivo; la app
  comprueba cambios al abrirse.
- **Push futuro (opcional):** si se añade, usará un **identificador anónimo de
  dispositivo** (token aleatorio), sin email ni nombre.
- La **clave de OpenCode Go** vive solo en el servidor (variable de entorno),
  nunca en el cliente.

## Deployment and Operations

- **Hosting propio:** servidor con **Intel N100 y 8 GB de RAM** (sin GPU).
- Orquestación con `docker-compose`.
- Job programado diario (cron) para la ingesta a las **9:30**, con una **segunda
  pasada** por la tarde para captar lo publicado más tarde.
- Web desplegada como estático; backend como servicio.
- Ajustes de recursos: `shared_buffers` de PostgreSQL ~1 GB, heap JVM ~1 GB,
  swap activado.
- **Backfill por lotes** en horario de baja carga (el N100 lo vectoriza en
  horas, no en minutos).
- Secretos por entorno, HTTPS.

## Testing and Verification

- Tests unitarios del backend (ingesta, parsers, clasificación, guardrails).
- Fixtures reales del BOE de **todas** las secciones del sumario (I, II.A, II.B,
  III, IV, V.A, V.B y V.C).
- **Golden set** de publicaciones para medir la calidad de los resúmenes.
- Pruebas de recuperación (precision/recall) y de los **destacados** (ranking).
- Pruebas del **chat RAG**: respuestas fundamentadas en el corpus, con citas y
  guardrail de "sin fundamento" (incluida la refutación de afirmaciones falsas).
- Beta interna vía Play internal testing y TestFlight.

## Observability

- Logs estructurados.
- Alerta si la ingesta de las **9:30** o la segunda pasada no se ejecuta.
- Métrica de resúmenes enviados a cola de revisión.
- Métrica de **coste/tokens y de consultas al chat RAG** (para vigilar abuso y
  cuota).
- **Sin analítica de uso** en la 1.0.0 (ni cookies ni telemetría de terceros).

## Constraints

- **Equipo:** una persona, a tiempo parcial, sin fecha fija.
- **Presupuesto:** cuota de OpenCode Go ($10/mes) + servidor propio (ya
  existente) + coste eléctrico.
- **Hardware:** N100 / 8 GB define el techo de CPU y RAM; la generación es
  remota para no cargar la CPU local.
- **Lenguas:** solo castellano en la 1.0.0.
- **Legal:** avisos de IA, disclaimer de no asesoramiento jurídico y
  trazabilidad a la fuente.
