# Progress Log

## Current Verified State

- Harness (privado): `.harness/`
- Repositorio de producto (código): `..` (repo público `DatoPublico`)
- Camino de arranque estándar: `./init.sh` (desde `.harness/`)
- Camino de verificación estándar: `./gradlew build` y `./gradlew test` desde la
  raíz del repo público (`..`) — **bootstrapped** (Gradle 8.10.2 + JDK 21).
- Última verificación: 2026-10-10 (Sessions 032–035). **Cambio de alcance 1.0.0 =
  TODO el BOE** (secciones I, II.A, II.B, III, IV, V.A, V.B y V.C; ningún campo ni
  sección se excluye) y nueva norma MUST de **`@SerialName` explícito** en cada
  propiedad `@Serializable`. **FT00002** (`bootstrap-shared-dtos`) y **FT00006**
  (`boe-sumario-cliente`) reabiertas, implementadas, **validadas (`accept`) y
  fusionadas** (PR #6). **FT00007** (`boe-parser-publicacion`) implementada y
  **validada (`accept`)** (Session 035).
- Última feature cerrada: `boe-parser-publicacion` (FT00007) → **`accepted`**
  (Session 035; parser de publicaciones del BOE en `:backend`
  (`ingesta/publicacion/`) que descarga el texto oficial por el **XML estructurado**
  (`xml.php`) con parser XML seguro y produce `Publicacion` (metadatos + texto +
  URL oficial), sin wiring en el arranque; `categoria = null`, diferida a FT00012;
  validación independiente `accept`; **PR #8 fusionado** en `main` por rebase →
  `f20cb40`, CI en verde run `38045496356`; deuda Low: `HttpTimeout` explícito →
  FT00009; detalle en `docs/validations/boe-parser-publicacion.md` y ADR
  `docs/adr/0002-fuente-texto-boe-xml.md`). Hito anterior:
  `boe-sumario-cliente` (FT00006) → **`accepted` y fusionada** (Sessions 029–034;
  validación + revalidación `accept`; **PR #6 fusionado** por rebase → `main`:
  `a7b3749` FT00002, `a347e72` FT00006). Siguiente feature lista:
  `publicacion-persistencia` (FT00008, depende de FT00007 y FT00003).
  FT00003 (`bootstrap-postgres-pgvector`) queda **`accepted`** (Session 023) tras
  la reparación de seguridad y la derivación de la conexión. FT00002
  (`bootstrap-shared-dtos`) **`accepted` y fusionada** (PR #2, merge `ca781f3`;
  ampliada en el PR #6 a las 8 secciones y `@SerialName`).

- Feature en curso: ninguna. **FT00008 `publicacion-persistencia`** implementada,
  autoverificada y **validada de forma independiente (`accept`)** (Session 036):
  migración `V2` (tablas
  `publicacion`/`fragmento`/`resumen`/`cola_revision`), `infra/` (config derivada
  de `POSTGRES_*` + pool HikariCP: `DatabaseConfig`/`Database`) y `persistence/`
  (4 repositorios JDBC + entidades), más `Publicacion.plazo`. Decisión durable en
  **ADR 0003**. Gate sin
  BD verde y prueba real opt-in `DB_LIVE_TEST=1` verde; detalle en
  `docs/validations/publicacion-persistencia.md`. Siguiente feature lista:
  `ingesta-job-diario` (FT00009).
- Bloqueo actual: ninguno para el bootstrap. Pendiente de producto: **nombre y
  marca** (bloquea la fase de producción, no el bootstrap).
- Convención de nombres (aclarada 2026-10-10): **todo tipo `@Serializable`/de
  transporte** lleva sufijo **`Dto`** (contrato de `:shared` y DTOs de
  `:backend`); la config de serialización (`DatoPublicoJson`) sin `Dto`; en capas
  internas `Entity`/`Row`/`Ui` y **sin sufijo** los modelos de dominio/valor
  internos (p. ej. `EntradaSumario`); sin prefijos. En `ARCHITECTURE.md`
  §«Convenciones de nombres» y **MUST** en `CONSTRAINTS.md`.
- Estilo (2026-10-10): **una sola salida por función** (prohibido el *early
  return*, también en tests; sin `return@…`). `CONSTRAINTS.md` §«Estilo de código».
- Última verificación: 2026-10-10. **FT00006 `boe-sumario-cliente`: `accepted`**
  (Sessions 029–031; revalidado tras el refactor de **retorno único**): cliente
  del sumario diario del BOE en `:backend`
  (`ingesta/sumario/`) con filtro I/II.A/II.B/III/V.B (excluye IV/V.A),
  serializador objeto/array, dos fixtures reales byte-idénticos a la API, tests
  sin red (18 en `:backend`, 0 fallos) y test opt-in `BOE_LIVE_TEST=1` fuera del
  gate; gate verde (`build` 197 tareas, `test` 3 módulos, `init.sh` exit 0) y
  validación independiente `accept`
  (`docs/validations/boe-sumario-cliente.md`). Sin wiring en el arranque;
  `Application.kt`/Flyway/`:shared`/`:composeApp`/CI intactos. Hito previo:
  **FT00005 `bootstrap-cmp-targets`:
  `accepted`** (Sessions 026–027): esqueleto Compose Multiplatform con targets
  Android/Wasm/iOS, pantalla mínima única en `commonMain` (`App()`) y entrypoint
  por plataforma; verificados `:composeApp:assembleDebug` (APK), 
  `wasmJsBrowserDistribution`, klib+framework iOS, `./gradlew test` (SmokeTest en
  jvm/Android/iOS; `:shared` 11 + `:backend` 9), `build --no-daemon` (196 tareas)
  e `init.sh` (exit 0). Validación independiente `accept` (detalle en
  `docs/validations/bootstrap-cmp-targets.md`); sin hallazgos de seguridad, deuda
  Low registrada. Dos desviaciones de build aceptadas como acotadas
  (`settings.gradle.kts` → `PREFER_SETTINGS` + repos Ivy de Binaryen/Node/Yarn;
  `wasmJsBrowserTest` fuera del gate). Hito previo: **FT00004
  `bootstrap-ktor-healthcheck`:
  `accepted`** (Sessions 024–025): esqueleto Ktor/Netty con `GET /health` (`200
  {"status":"ok"}` en `:backend:run`, en el puerto por defecto 8080 y en 8090 por
  entorno), configuración por entorno con fail-fast ante puerto inválido, logging
  JSON (Logback + logstash, una línea por evento en stdout) y
  `:backend:test --rerun-tasks` con 9 tests verdes; gate sin BD en verde
  (`./gradlew test` 3 módulos, `./gradlew build --no-daemon`,
  `env -u JAVA_HOME .harness/init.sh` → exit 0). Validación independiente
  (`feature-validator`) con veredicto `accept` (reejecutó arranque, tests,
  fail-fast y gate sin BD; sin hallazgos de seguridad; deuda menor L1–L4).
  Producto: commit `9266729`, PR #4, CI en verde (run 38034700464). Hitos previos:
  **FT00002 `bootstrap-shared-dtos`:
  `accepted`** (validación independiente `accept` de los renombrados de
  contenedores y de enums); PR #2 con CI en verde (run 37998033440, head
  872fb2b) y **fusionado** (`ca781f3`). Gate verde desde `..` con JDK 21 (JBR):
  `./gradlew :shared:jvmTest`, `./gradlew test` (3 módulos) y `./gradlew build`.
  FT00001 `bootstrap-monorepo-gradle`: **`accepted`** (PR #1 fusionado, merge
  `912c328`). **FT00003 `bootstrap-postgres-pgvector`: `accepted`** (Session 023)
  tras: reparación de seguridad (sin credenciales versionadas, `POSTGRES_PASSWORD`
  obligatorio, loopback, fail-fast), derivación de la conexión de Flyway desde
  `POSTGRES_*` (URL `jdbc:postgresql://host:port/db`; `FLYWAY_*` como override) y
  limpieza de comentarios (`docs/desarrollo-local.md`). PR #3 con CI en verde (run
  38033346128, head 55217b6); recomendado squash-merge.
- PoC exploratoria (no feature), **temporal y ya eliminada**: `poc/boe-rag`
  validó el RAG de punta a punta (embeddings locales ONNX + pgvector + generación
  con cita). Sus lecciones quedan en la skill `rag-datapublico`. Ver Session 002.
- Decisión de IA (2026-10-09): **embeddings locales `multilingual-e5-small` int8
  (ONNX/CPU)** por defecto (`-base` como alternativa tras la interfaz) +
  **OpenCode** (`deepseek-v4.1-flash`) para resumen y chat. OpenCode no ofrece
  endpoint de embeddings. El **chat RAG entra en el alcance de la 1.0.0**.
- Alcance 1.0.0 (actualizado 2026-10-10): **todo el sumario del BOE**
  (secciones I, II.A, II.B, III, IV, V.A, V.B y V.C) con **categorías** curadas
  (11 valores) + sección/epígrafe del BOE como metadato; feed diario con
  **destacados**, búsqueda con filtros y **chat de verificación** contra el BOE.
  Ingesta **9:30 + segunda pasada**; backfill del **último año**. El principio
  «sin datos personales» aplica a los **usuarios de la app**, no al BOE. Fuera:
  PLACSP (detalle de adjudicaciones) y fact-checking externo (1.x).

## Session Log

### Session 001

- Fecha: 2026-10-08
- Objetivo: crear el harness mínimo de arranque.
- Completado: `AGENTS.md`, `init.sh`, `PROGRESS.md` y `feature_list.json`
  creados en `.harness/` (repo interno). Bootstrap registrado como
  pre-bootstrap.
- Verificación ejecutada: validación de JSON de `feature_list.json` y
  `chmod +x init.sh`.
- Evidencia capturada: `feature_list.json` parsea como JSON válido; todas las
  features tienen los campos requeridos y las dependencias referencian ids
  existentes.
- Ficheros actualizados: `.harness/AGENTS.md`, `.harness/init.sh`,
  `.harness/PROGRESS.md`, `.harness/feature_list.json`.
- Riesgo o duda sin resolver: el harness vive en el repo privado y el código en
  el público (`..`); hay que ejecutar los comandos de build desde `..`.
- Siguiente mejor paso: implementar `bootstrap-monorepo-gradle` en el repo
  público.

### Session 002

- Fecha: 2026-10-08
- Objetivo: POC de viabilidad del RAG (recuperación + generación con cita).
- Completado: nueva PoC standalone en `poc/boe-rag` (repo público, no feature):
  ingesta del BOE → chunking por artículo/disposición → embeddings locales
  `multilingual-e5-small` vía ONNX Runtime (CPU) → pgvector (docker-compose,
  índice HNSW) → recuperación semántica con filtros → respuesta con OpenCode Go
  citando fuentes → evaluación recall@k/MRR. Endpoints: `POST /index`,
  `GET /buscar`, `GET /preguntar`, `GET /evaluar`, `GET /stats`.
- Verificación ejecutada (servidor real en :8090, Postgres+pgvector en Docker):
  - `GET /health` → 200 `{status:ok, dimensiones:384}`.
  - `POST /index?fecha=20261008&limite=5` → 5 normas, 240 fragmentos sin errores.
  - `GET /buscar?q=...` → devuelve fragmentos relevantes con referencia y score.
  - `GET /evaluar?k=5` → recall 1.0, MRR 1.0 sobre 4 casos.
  - `GET /preguntar?q=...` → respuesta en castellano citando `[3]` («Artículo 4»)
    y fuentes oficiales; ~6 s por respuesta. avisoIA presente.
- Evidencia capturada: resultados anteriores por HTTP; `docker ps` con
  `datopublico-rag-postgres` healthy; reindexado de 5 normas en ~12 s.
- Ficheros creados: `poc/boe-rag/` (Boe.kt, Chunking.kt, Embeddings.kt, Db.kt,
  Rag.kt, Llm.kt, Eval.kt, Main.kt, build.gradle.kts, docker-compose.yml,
  download-model.sh, README.md, eval/queries.json).
- Correcciones durante la PoC: los encabezados del BOE usan espacio duro
  (`\u00a0`) tras «Artículo», y el texto se extraía sin saltos de bloque; se
  normalizan espacios y se insertan saltos por párrafo, anclando los encabezados
  a inicio de línea. Esto arregla referencias erróneas («parte 32», «Encabezado»).
- Riesgo o duda sin resolver: el chunking por expresiones regulares es heurístico
  (la ruta de producto debería aprovechar la estructura XML); los embeddings
  cuantizados (int8) no se han comparado aún con fp32 en calidad; corpus de
  prueba pequeño (5 normas).
- Ampliación posterior (misma sesión): generación **local sin OpenCode**.
  `LlmClient` pasa a ser configurable por entorno (`LLM_CHAT_URL`, `LLM_MODEL`,
  `LLM_API_KEY`); si no hay clave no envía cabecera de auth (sirve para un
  servidor local). Se añade `ollama` al `docker-compose` (puerto 11434) y
  `pull-model.sh`. Modelo probado en la VM (4 CPU, 4 GB, sin GPU):
  `qwen2.5:1.5b`. Verificado `/preguntar` con el modelo local (respuesta
  correcta a la consulta de beneficiarios) y `/health` con `modelo=qwen2.5:1.5b`.
  Consumo: Ollama ~1.5 GB RAM y 100% CPU durante la inferencia; Postgres ~62 MB.
  Incidencia resuelta: la red host↔Colima se rompió (socket Docker y reenvío de
  puertos); se arregló con `colima restart` (los contenedores `vuelantis` con
  `restart=unless-stopped` volvieron solos). Para que cupiera la imagen de
  Ollama hubo que liberar caché de build (`docker builder prune -a`), 19 GB.
- Decisión final de la PoC: **generación con DeepSeek remoto para todo**
  (`deepseek-v4.1-flash` vía OpenCode Go). Se retira del `.env` la config del
  modelo local (`LLM_CHAT_URL`/`LLM_MODEL`), de modo que la PoC vuelve al
  endpoint por defecto. Los **embeddings siguen siendo locales** (ONNX), que es
  la otra mitad del RAG y no tiene equivalente en DeepSeek. Verificado:
  `/health` → `modelo=deepseek-v4.1-flash` y `/preguntar` devuelve respuesta
  citada correcta. Se **retira Ollama por completo**: servicio fuera del
  `docker-compose`, contenedor/volumen/imagen eliminados y `pull-model.sh`
  borrado; el stack de la PoC queda solo con Postgres + DeepSeek.
- Siguiente mejor paso: decidir si esta PoC informa las features `rag` del
  `feature_list.json` (`embeddings-locales-onnx`, `pgvector-indexado`,
  `recuperacion-hibrida`) y seguir con `bootstrap-monorepo-gradle`.
- Nota posterior (2026-10-09): la PoC era **temporal** (solo una prueba) y se
  **eliminó** a propósito; no hay que recuperarla. Sus lecciones quedan
  destiladas en la skill `rag-datapublico`.

### Session 003

- Fecha: 2026-10-09
- Objetivo: replanificar la IA (embeddings locales pequeños + OpenCode para
  generación y chat) e incorporar el **chat RAG** al alcance de la `1.0.0`.
- Completado:
  - Decision de IA fijada: `multilingual-e5-small` **int8** (ONNX/CPU) como
    único modelo local; OpenCode (`deepseek-v4.1-flash`) para resumen y chat.
    OpenCode **no** ofrece endpoint de embeddings (verificado en su documentación).
  - Discovery actualizado: `build-brief.md` (Goals, MVP Slice, validación y
    criterios), `domain-model.md` (entidad **Consulta** y sus estados),
    `technical-discovery.md` (reparto IA, chat RAG), `risks-and-open-questions.md`
    (riesgos/dudas del chat) y `CONTEXT.md` (glosario + término "Traducción").
  - Roadmap interno (`docs/roadmap.md`): chat movido a `0.4-T07` (generación),
    `0.5-T06` (endpoint) y `0.6-T08` (UI); retirado de post-producción; stack e
    IA actualizados.
  - `feature_list.json`: 3 features nuevas — `chat-generacion` (simplificacion-ia),
    `api-chat` (api-publica) y `ui-chat` (cliente-cmp); `beta-cerrada` depende de
    `ui-chat`. Títulos/notas "OpenCode Go" normalizados a "OpenCode".
  - Repo público: `README.md` y `ROADMAP.md` incluyen el chat en la 1.0.0.
- Verificación ejecutada: `feature_list.json` parsea como JSON válido; 44
  features, todas con los campos requeridos y todas las dependencias referencian
  ids existentes (0 problemas).
- Ficheros actualizados: `.harness/CONTEXT.md`, `.harness/docs/build-brief.md`,
  `.harness/docs/domain-model.md`, `.harness/docs/risks-and-open-questions.md`,
  `.harness/docs/technical-discovery.md`, `.harness/docs/roadmap.md`,
  `.harness/feature_list.json`, `.harness/PROGRESS.md`, `README.md`, `ROADMAP.md`.
- Riesgo o duda sin resolver: el chat es más caro por consulta que el feed
  (requiere rate limiting y control de contexto); el historial de chat no se
  persiste en el servidor; sigue pendiente el **nombre y marca**.
- Siguiente mejor paso: implementar `bootstrap-monorepo-gradle` en el repo
  público.

### Session 004

- Fecha: 2026-10-09
- Objetivo: ampliar el alcance de la `1.0.0` con **empleo público y becas**
  (Secciones II.B y III del BOE), **destacados del día**, **verificación de
  afirmaciones** en el chat, ingesta **9:30 + segunda pasada** y backfill del
  **último año**; y propagarlo a la planificación.
- Decisiones tomadas:
  - Datos 1.0.0: Secciones I, II.B y III. **Contratación pública (PLACSP)** queda
    en 1.x.
  - Chat: verifica afirmaciones **solo contra el BOE** (sin prensa/redes); el
    fact-checking externo queda en 1.x.
  - Destacados: ranking **automático y explicable** por señales objetivas (rango
    normativo, organismo, palabras clave).
  - Ingesta a las **9:30** con segunda pasada; backfill del **último año**.
  - Lenguaje: término paraguas **Publicación** (Norma / Empleo público / Becas y
    subvenciones).
- Completado:
  - Discovery: `CONTEXT.md`, `build-brief.md`, `domain-model.md` (reescrito sobre
    **Publicación**), `technical-discovery.md` y `risks-and-open-questions.md`.
  - `docs/roadmap.md`: alcance, corpus, ingesta, destacados y tareas (`0.2-T08`
    clasificación+plazos, `0.2-T09` backfill, `0.4-T08` destacados); API/UI con
    destacados, categorías y chat de verificación.
  - `feature_list.json`: renombrados `boe-parser-norma`→`boe-parser-publicacion` y
    `norma-persistencia`→`publicacion-persistencia`; nuevas features
    `categorizacion-publicaciones` y `destacados-diarios` (area `relevancia`);
    actualizadas feed, detalle, búsqueda, chat y UI.
  - `DESIGN.md`: descripción, colores de categoría, tarjeta de publicación,
    pantalla de chat, destacados y estados.
  - `AGENTS.md` interno y `README.md`/`ROADMAP.md` públicos actualizados.
- Verificación ejecutada: `feature_list.json` parsea como JSON válido; **46
  features**, todas con los campos requeridos y todas las dependencias referencian
  ids existentes (0 problemas, sin ids duplicados).
- Ficheros actualizados: `.harness/CONTEXT.md`, `.harness/DESIGN.md`,
  `.harness/AGENTS.md`, `.harness/docs/{build-brief,domain-model,technical-discovery,risks-and-open-questions,roadmap}.md`,
  `.harness/feature_list.json`, `.harness/PROGRESS.md`, `README.md`, `ROADMAP.md`.
- Riesgo o duda sin resolver: estructura irregular de las Secciones II.B/III
  (parser/clasificación a validar); posible percepción de sesgo en los destacados;
  taxonomía fina de la Sección III y modelado de plazos; sigue pendiente el
  **nombre y marca**.
- Siguiente mejor paso: implementar `bootstrap-monorepo-gradle` en el repo
  público.

### Session 005

- Fecha: 2026-10-09
- Objetivo: preparar las **skills del proyecto** para poder implementar con
  consistencia.
- Completado:
  - **Adaptadas a DatoPublico** (estaban copiadas de otro proyecto, «Vuelantis»):
    `ktor-backend-architecture` y `compose-multiplatform-architecture`.
  - **Nueva skill** `rag-datapublico` (pipeline RAG sobre el BOE: chunking por
    sección, `multilingual-e5-small` int8, pgvector, recuperación híbrida,
    generación con citas, guardrails y evaluación).
  - No se crea skill de Docker: basta la sección de operación local dentro de la
    skill de backend.
- Estado de skills del harness: `build-brief`, `harness-starter`,
  `feature-spec`, `feature-implementer`, `feature-validator`,
  `feature-task-ids` (genéricas); `ktor-backend-architecture`,
  `compose-multiplatform-architecture`, `rag-datapublico` (proyecto).
- Pendiente/deuda detectada (resuelta en Session 006):
  - `feature-flow` **no operativo**: faltaban `docs/git-workflow.md`,
    `docs/feature-ids.md`, `docs/specs/`, `docs/validations/`, campos `ft_id` y
    los subagentes `planner/implementer/validator`.
  - `poc/boe-rag`: era una PoC **temporal** y se eliminó a propósito; no hay que
    recuperarla (lecciones en la skill `rag-datapublico`).
  - Namespace raíz **decidido**: `es.aviferdev.datopublico`.
- Ficheros: `.harness/.agents/skills/{ktor-backend-architecture,compose-multiplatform-architecture}/SKILL.md`
  (reescritos), `.harness/.agents/skills/rag-datapublico/SKILL.md` (nuevo).
- Siguiente mejor paso: implementar `bootstrap-monorepo-gradle` en el repo
  público.

### Session 006

- Fecha: 2026-10-09
- Objetivo: **cablear el flujo de features** (`feature-flow`) y cerrar las
  decisiones pendientes.
- Decisiones: namespace raíz **`es.aviferdev.datopublico`** (backend en
  `es.aviferdev.datopublico.backend`); la PoC `poc/boe-rag` era **temporal** y se
  eliminó a propósito.
- Completado:
  - `docs/git-workflow.md`: protocolo adaptado a **dos repos** (producto público
    con ramas/PR; harness privado en `main`), *claim* por push inmediato de la
    rama, commits con `FT` como scope y worktrees opcionales.
  - `docs/feature-ids.md`: convención `FTxxxxx` + tabla de las **46 features** +
    siguiente libre (`FT00047`).
  - `feature_list.json`: campo `ft_id` añadido a las 46 features (FT00001..FT00046).
  - `docs/specs/README.md` y `docs/validations/README.md` (carpetas del flujo).
  - Subagentes OpenCode en `.harness/.opencode/agents/` (`planner`, `implementer`,
    `validator`), expuestos vía symlink `.opencode → .harness/.opencode` y
    excluidos del repo público.
  - Skill de backend: namespace fijado; skill de RAG: nota de PoC actualizada.
- Verificación ejecutada: `feature_list.json` parsea; 46 features con `ft_id`
  único y todas las dependencias válidas; los 3 agentes y 3 skills presentes en
  disco.
- Ficheros: `.harness/docs/{git-workflow,feature-ids}.md`,
  `.harness/docs/specs/README.md`, `.harness/docs/validations/README.md`,
  `.harness/feature_list.json`, `.harness/.opencode/agents/*.md`,
  `.harness/ARCHITECTURE.md`, `.harness/CONSTRAINTS.md`, `.harness/AGENTS.md`,
  `.harness/.agents/skills/{ktor-backend-architecture,rag-datapublico}/SKILL.md`,
  symlink `.opencode` en la raíz del producto.
- Riesgo o duda sin resolver: los subagentes pueden requerir **reiniciar la
  sesión** de OpenCode para aparecer; los permisos de los agentes son mínimos
  (denegar `subagent`; validador solo-lectura) y puede haber que ajustarlos al
  usarlos.
- Siguiente mejor paso: implementar `bootstrap-monorepo-gradle` (FT00001 en
  `docs/feature-ids.md`).

### Session 007

- Fecha: 2026-10-09
- Objetivo: ampliar el alcance a **todas las categorías** del BOE.
- Decisiones:
  - Secciones ingeridas: **I, II.A, II.B, III y V.B**. Fuera: **IV**
    (Administración de Justicia, datos personales) y **V.A** (subastas y
    licitaciones → PLACSP/1.x).
  - Categorías: **enum curado de 11** (Normas y legislación; Nombramientos y
    ceses; Oposiciones y empleo público; Becas, subvenciones y ayudas; Premios;
    Convenios y acuerdos; Educación y planes de estudio; Medio ambiente; Recursos
    y resoluciones; Información pública y concesiones; Otras disposiciones y
    anuncios) + **sección/epígrafe del BOE** como metadato.
- Completado:
  - Discovery: `CONTEXT.md` (Categoría, Sección/Epígrafe, secciones nuevas y
    términos excluidos IV/V.A), `docs/build-brief.md`, `docs/domain-model.md`
    (reescrito con la taxonomía), `docs/technical-discovery.md` (corpus y BOE) y
    `docs/risks-and-open-questions.md` (mapeo, duplicidad III↔V.B, volumen).
  - `docs/roadmap.md`: alcance, corpus y tareas de la 0.2 (secciones, categorías,
    dedup III↔V.B).
  - `feature_list.json`: actualizadas ingesta/parser/persistencia, categorización,
    backfill, feed/UI (siguen 46 features; sin features nuevas).
  - `DESIGN.md` (categorías), `CONSTRAINTS.md` (secciones excluidas),
    `AGENTS.md`, skills `ktor-backend-architecture` y `rag-datapublico`,
    `README.md`/`ROADMAP.md` públicos.
- Verificación ejecutada: `feature_list.json` parsea; 46 features, `ft_id` únicos
  y dependencias válidas (0 problemas).
- Ficheros: `.harness/{CONTEXT.md,DESIGN.md,CONSTRAINTS.md,AGENTS.md,PROGRESS.md,feature_list.json}`,
  `.harness/docs/{build-brief,domain-model,technical-discovery,risks-and-open-questions,roadmap}.md`,
  `.harness/.agents/skills/{ktor-backend-architecture,rag-datapublico}/SKILL.md`,
  `README.md`, `ROADMAP.md`.
- Riesgo o duda sin resolver: mapeo epígrafe→categoría en casos ambiguos;
  duplicidad III↔V.B; volumen de III/V.B en el N100.
- Siguiente mejor paso: implementar `bootstrap-monorepo-gradle` (FT00001).

### Session 008

- Fecha: 2026-10-09
- Objetivo: implementar `bootstrap-monorepo-gradle` (FT00001) en el repo público:
  monorepo Gradle Kotlin DSL con version catalog, wrapper commiteado, tres
  módulos mínimos y CI de build+tests.
- Completado:
  - `settings.gradle.kts`: `pluginManagement` + `dependencyResolutionManagement`
    (Maven Central, Google, Plugin Portal, `FAIL_ON_PROJECT_REPOS`),
    `rootProject.name = "datopublico"` e `include(":shared", ":backend",
    ":composeApp")`.
  - `build.gradle.kts` raíz con todos los plugins del catálogo `apply false`.
  - `gradle/libs.versions.toml` con Kotlin 2.1.20 activo y AGP 8.7.3, Compose
    Multiplatform 1.7.3, Ktor 3.0.3, kotlinx.serialization 1.8.0 y coroutines
    1.10.1 predeclarados para FT00002/04/05.
  - `gradle.properties` (jvmargs, parallel, caching, `kotlin.code.style`).
  - Módulos mínimos (solo target `jvm()`, toolchain 21): `:shared` KMP,
    `:composeApp` KMP y `:backend` Kotlin JVM con
    `implementation(project(":shared"))`; un test smoke por módulo
    (`commonTest`/`test`, 1 test cada uno).
  - Wrapper Gradle 8.10.2 commiteable (`gradlew`, `gradlew.bat`,
    `gradle/wrapper/gradle-wrapper.jar` y `.properties`).
  - `.github/workflows/ci.yml`: ubuntu-latest, temurin JDK 21,
    `gradle/actions/setup-gradle@v4` y `./gradlew build --no-daemon`.
  - `.gitignore`: `.gradle/`, `build/`, `**/build/`, `.kotlin/`,
    `local.properties`, `*.hprof`; el wrapper **no** se ignora.
- Verificación ejecutada (desde `..` con `JAVA_HOME` del JBR 21):
  - `./gradlew --version` → Gradle 8.10.2, JVM 21.0.10.
  - `./gradlew build --no-daemon` → BUILD SUCCESSFUL (15 tareas).
  - `./gradlew test --rerun-tasks` → BUILD SUCCESSFUL; 3 tests, 0 fallos.
  - `./gradlew projects` → `:backend`, `:composeApp`, `:shared`.
  - `./gradlew :backend:compileKotlin` → BUILD SUCCESSFUL (resuelve
    `:shared:jvmJar`).
- Evidencia capturada: salidas anteriores y XML de resultados
  (`backend/build/test-results/test`, `shared`/`composeApp`
  `build/test-results/jvmTest`, `tests="1" failures="0" errors="0"`).
- Ficheros creados/modificados: `settings.gradle.kts`, `build.gradle.kts`,
  `gradle.properties`, `gradle/libs.versions.toml`,
  `gradle/wrapper/*`, `gradlew`, `gradlew.bat`, `shared/*`, `backend/*`,
  `composeApp/*`, `.github/workflows/ci.yml`, `.gitignore`,
  `.harness/feature_list.json`, `.harness/PROGRESS.md`.
- Riesgo o duda sin resolver: el **run de CI en GitHub Actions** no puede
  comprobarse en local; queda pendiente de push/PR (a cargo del orquestador).
  `:backend:compileKotlin` es `NO-SOURCE` (aún sin `main`), lo que no rompe el
  escenario de dependencia. Sin `main` en `:shared`/`:composeApp` hasta sus
  features.
- Siguiente mejor paso: validación independiente de FT00001 (`feature-validator`)
  y, una vez aceptada, implementar `bootstrap-shared-dtos` (FT00002).

### Session 009

- Fecha: 2026-10-09
- Objetivo: reparar FT00001 tras validación independiente con veredicto `revise`
  (evidencia inexacta sobre `./gradlew test` y `init.sh` pre-bootstrap).
- Diagnóstico: en KMP no existe una task `test` a nivel de proyecto, así que
  `./gradlew test` desde la raíz solo ejecutaba `:backend:test` (1 test); los 3
  tests solo se cubrían con `./gradlew build` (vía `allTests`). La evidencia
  afirmaba lo contrario.
- Completado:
  - `build.gradle.kts` raíz: nueva task `test` que agrega
    `:backend:test`, `:shared:jvmTest` y `:composeApp:jvmTest`.
  - `.harness/init.sh`: deja de ser pre-bootstrap; es un gate real no bloqueante
    que descubre el JDK (JAVA_HOME → `/usr/libexec/java_home` → JBR de Android
    Studio), ejecuta `./gradlew build --no-daemon` desde la raíz y falla en error;
    no arranca servidores.
  - `.harness/feature_list.json` (FT00001): evidencia corregida y sin la
    afirmación inexacta; sigue `passing`.
  - `.harness/docs/feature-ids.md`: FT00001 pasa a `passing`.
  - `.github/workflows/ci.yml`: `actions/checkout` y `actions/setup-java` a `@v5`.
- Verificación ejecutada (desde `..`, `JAVA_HOME` del JBR 21):
  - `./gradlew test --rerun-tasks` → BUILD SUCCESSFUL; ejecuta `:shared:jvmTest`,
    `:backend:test` y `:composeApp:jvmTest`; 3 XML regenerados (`tests="1"
    failures="0" errors="0"` por módulo).
  - `./gradlew build` → BUILD SUCCESSFUL (15 tareas).
  - `./gradlew projects` → `:backend`, `:composeApp`, `:shared`.
  - `./gradlew :backend:compileKotlin` → BUILD SUCCESSFUL.
  - `env -u JAVA_HOME .harness/init.sh` → descubre el JBR, ejecuta el gate y
    devuelve 0.
- Ficheros modificados: `build.gradle.kts`, `.harness/init.sh`,
  `.harness/feature_list.json`, `.harness/PROGRESS.md`,
  `.harness/docs/feature-ids.md`, `.github/workflows/ci.yml`.
- Riesgo o duda sin resolver: el run de CI sigue pendiente de push/PR (a cargo
  del orquestador). Sin cambios de alcance.
- Siguiente mejor paso: revalidar FT00001 (`feature-validator`) con la evidencia
  corregida.

### Session 010

- Fecha: 2026-10-09
- Objetivo: cerrar FT00001 (`bootstrap-monorepo-gradle`): reparación → CI → PR →
  aceptación.
- Completado:
  - Commits de producto en la rama `feat/ft00001-bootstrap-monorepo-gradle`:
    `6bde1d5` (bootstrap) y `8ad45c4` (fix: `./gradlew test` cubre los tres
    módulos + acciones CI `@v5`). Rama pusheada.
  - **PR #1** hacia `main`: https://github.com/AviferDev/DatoPublico/pull/1 —
    **fusionado** (merge commit `912c328`); rama `feat/ft00001-...` eliminada
    (local y remota).
  - **CI en verde**: run `37995689375`, job "Build and test" SUCCESS para el head
    `8ad45c4`.
  - **Validación independiente**: `revise` inicial → reparación → revalidación con
    veredicto **`accept`**.
  - `.harness/feature_list.json`: FT00001 → **`accepted`** (evidencia con ref. real
    de CI y de la aceptación). `docs/feature-ids.md`: FT00001 → `accepted`.
- Verificación: el validator reejecutó el gate (3 módulos, 3 tests verdes),
  comprobó `init.sh` (exit 0) y el run de CI; árbol de producto limpio.
- Ficheros: `.harness/feature_list.json`, `.harness/docs/feature-ids.md`,
  `.harness/PROGRESS.md`.
- Limpieza posterior: se detectó una referencia al **hardware** (N100) en
  `gradle.properties` del repo público. Se quitó y la rama se **rebasó**
  (`git rebase -i`) para **fusionar** ese commit (`chore(FT00001): quitar la
  referencia al hardware…`) dentro del commit de bootstrap, de modo que la línea
  nunca aparece en el historial. Hashes reescritos: feat `6bde1d5`, fix `8ad45c4`;
  CI reejecutada en verde (run `37995689375`). El resto de menciones al N100 siguen
  solo en el **harness privado** (planificación), no en el repo público.
- Estado: **FT00001 `accepted`**. Siguiente feature lista: `bootstrap-shared-dtos`
  (FT00002).
- Siguiente mejor paso: implementar `bootstrap-shared-dtos` (FT00002) con el flujo.

### Session 011

- Fecha: 2026-10-09
- Objetivo: implementar `bootstrap-shared-dtos` (FT00002) en el repo público:
  contrato de datos base en `:shared` serializable con `kotlinx.serialization`.
- Completado:
  - `shared/build.gradle.kts`: aplica `libs.plugins.kotlin.serialization` y añade
    `libs.kotlinx.serialization.json` a `commonMain`. Sin tocar raíz ni otros
    módulos.
  - `commonMain` (`es.aviferdev.datopublico.model`), todos `@Serializable`:
    `Categoria` (11 valores, `@SerialName` snake_case), `SeccionBoe` (`I`,
    `II.A`, `II.B`, `III`, `V.B`), `Plazo`, `Resumen`, `Publicacion`,
    `DailySummary`. Fechas como `String` ISO-8601, sin `java.time`.
  - `DatoPublicoJson` en `es.aviferdev.datopublico.serialization`
    (`ignoreUnknownKeys = true`, `encodeDefaults = true`).
  - `commonTest`: `SerializationTest` (7 tests: round-trip de cada DTO, opcionales
    nulos, `Plazo` ISO, `ignoreUnknownKeys`) y `CategoriaWireTest` (3 tests:
    tokens de `Categoria`/`SeccionBoe` y unicidad). `SmokeTest` intacto.
- Verificación ejecutada (desde `..`, `JAVA_HOME` del JBR 21):
  - `./gradlew :shared:jvmTest` → BUILD SUCCESSFUL; XML: SmokeTest 1/0/0,
    CategoriaWireTest 3/0/0, SerializationTest 7/0/0.
  - `./gradlew test` → BUILD SUCCESSFUL (agrega `:shared:jvmTest`,
    `:backend:test`, `:composeApp:jvmTest`).
  - `./gradlew build` → BUILD SUCCESSFUL (16 tareas).
  - grep de `java.time`/`java.util`/`System.` en `commonMain`: solo en KDoc.
- Ficheros creados/modificados: `shared/build.gradle.kts`,
  `shared/src/commonMain/kotlin/es/aviferdev/datopublico/model/{Categoria,SeccionBoe,Plazo,Resumen,Publicacion,DailySummary}.kt`,
  `shared/src/commonMain/kotlin/es/aviferdev/datopublico/serialization/DatoPublicoJson.kt`,
  `shared/src/commonTest/kotlin/es/aviferdev/datopublico/model/{SerializationTest,CategoriaWireTest}.kt`,
  `.harness/feature_list.json` (FT00002 → `passing`), `.harness/docs/feature-ids.md`,
  `.harness/PROGRESS.md`.
- Riesgo o duda sin resolver: la verificación de `feature_list.json` cita
  `./gradlew :shared:test` (inexistente en KMP); se acepta `:shared:jvmTest` como
  equivalencia según el spec. Commit/push/PR y CI quedan a cargo del orquestador
  (el implementer no crea commits).
- Siguiente mejor paso: validación independiente de FT00002 (`feature-validator`).

### Session 012

- Fecha: 2026-10-10
- Objetivo: cerrar FT00002 (`bootstrap-shared-dtos`): commit → CI → PR →
  aceptación.
- Completado:
  - Commit de producto en la rama `feat/ft00002-bootstrap-shared-dtos`:
    `9bfeaf5 feat(FT00002): DTOs compartidos con kotlinx.serialization` (10
    ficheros, +365). Rama pusheada.
  - **PR #2** hacia `main`: https://github.com/AviferDev/DatoPublico/pull/2
  - **CI en verde**: run `37996544504`, job "Build and test" SUCCESS para el head
    `9bfeaf5`.
  - **Validación independiente**: veredicto **`accept`** (sin hallazgos
    bloqueantes; dos correcciones *Low* aplicadas al persistir).
  - `.harness/feature_list.json`: FT00002 → **`accepted`**; corregida la
    verificación (`:shared:jvmTest`) y la evidencia (commit/PR/CI + aceptación).
    `docs/feature-ids.md`: FT00002 → `accepted`.
- Verificación: el validator reejecutó `:shared:jvmTest`/`test`/`build`
  (`--rerun-tasks`) y `init.sh` (exit 0); contrato de `Categoria` (11) y
  `SeccionBoe` verificados; sin hallazgos de seguridad.
- Ficheros: `.harness/feature_list.json`, `.harness/docs/feature-ids.md`,
  `.harness/PROGRESS.md`.
- Nota (no bloqueante): `organismo`/`epigrafe` en `Publicacion` no tienen valor por
  defecto; si el backend omite claves nulas, habrá que añadir `= null` y valorar
  `explicitNulls`.
- Estado: **FT00002 `accepted`**. Siguiente feature lista:
  `bootstrap-postgres-pgvector` (FT00003).
- Siguiente mejor paso: implementar `bootstrap-postgres-pgvector` (FT00003) con el
  flujo.

### Session 013

- Fecha: 2026-10-10
- Objetivo: reparar `bootstrap-shared-dtos` (FT00002) aplicando la **convención
  de nombres** `Dto` en `:shared` y dejarla durable en la documentación.
- Completado:
  - Renombrados (con `git mv`, mismos tokens de wire y JSON) los contenedores de
    datos del contrato en `es.aviferdev.datopublico.model`:
    `Publicacion`→`PublicacionDto`, `Resumen`→`ResumenDto`,
    `Plazo`→`PlazoDto`, `DailySummary`→`ResumenDiarioDto`
    (`PublicacionDto.kt`, `ResumenDto.kt`, `PlazoDto.kt`, `ResumenDiarioDto.kt`).
  - Sin cambios (no son DTO): `Categoria` y `SeccionBoe` (enums de
    vocabulario/tokens de wire) y `DatoPublicoJson` (config de serialización).
  - Campos `PublicacionDto.resumen`/`plazo` ahora `ResumenDto?`/`PlazoDto?`;
    KDocs y `SerializationTest` actualizados (`CategoriaWireTest` no referenciaba
    los tipos renombrados).
  - Convención durable: `ARCHITECTURE.md` §«Convenciones de nombres» (sufijo
    `Dto`, enums sin sufijo, `...Entity`/`...Row`/`...Ui`, sin prefijos) y regla
    **MUST** en `CONSTRAINTS.md` §«Nombres y contratos». Nota de reparación en
    `docs/specs/bootstrap-shared-dtos.md` (sin reescribir el spec).
  - `.harness/feature_list.json` (FT00002 → `in_progress`) con la evidencia del
    renombrado.
- Verificación ejecutada (desde `..`, `JAVA_HOME` del JBR 21):
  - `./gradlew :shared:jvmTest --rerun-tasks` → BUILD SUCCESSFUL; XML: SmokeTest
    1/0/0, CategoriaWireTest 3/0/0, SerializationTest 7/0/0 (failures/errors = 0).
  - `./gradlew test` → BUILD SUCCESSFUL (agrega `:shared:jvmTest`,
    `:backend:test`, `:composeApp:jvmTest`).
  - `./gradlew build` → BUILD SUCCESSFUL (16 tareas).
  - grep: sin referencias stale a los nombres antiguos como tipos en `:shared`.
- Ficheros: `shared/src/commonMain/.../model/{PublicacionDto,ResumenDto,PlazoDto,ResumenDiarioDto}.kt`
  (renombrados), `.../model/Categoria.kt` (KDoc), `.../commonTest/.../SerializationTest.kt`,
  `.harness/{ARCHITECTURE.md,CONSTRAINTS.md,feature_list.json,PROGRESS.md}`,
  `.harness/docs/specs/bootstrap-shared-dtos.md`.
- Riesgo o duda sin resolver: el commit/push/PR y la CI los hace el orquestador;
  queda pendiente la **validación independiente** del renombrado.
- Siguiente mejor paso: validación independiente de FT00002 tras el renombrado.

### Session 014

- Fecha: 2026-10-10
- Objetivo: cerrar la reparación de nombres de FT00002 y dejar la convención
  aplicada y documentada.
- Completado:
  - Commit de producto en `feat/ft00002-bootstrap-shared-dtos`:
    `8320bfd refactor(FT00002): sufijo Dto en los contenedores de datos de :shared`
    (4 ficheros renombrados con `git mv`, +31/−31). Pusheado.
  - **CI en verde**: run `37997372090`, head `8320bfd` (PR #2).
  - **Validación independiente**: veredicto **`accept`**; confirmó renombrado
    íntegro, contrato de wire invariante y convención bien reflejada.
  - `.harness/feature_list.json`: FT00002 → **`accepted`** (nombres en la
    descripción y la evidencia alineados; commit/PR/CI y aceptación reales).
    `docs/feature-ids.md`: FT00002 → `accepted`. Spec: cabecera `accepted`.
- Convención durable (para no repetirlo):
  - `ARCHITECTURE.md` §«Convenciones de nombres» y regla **MUST** en
    `CONSTRAINTS.md` §«Nombres y contratos»: en `:shared` los contenedores de datos
    llevan sufijo **`Dto`**; los enums de vocabulario/tokens de wire van sin sufijo;
    la config de serialización sin `Dto`; capas internas `...Entity`/`...Row`/`...Ui`;
    **sin prefijos**.
- Ficheros: `.harness/feature_list.json`, `.harness/docs/feature-ids.md`,
  `.harness/docs/specs/bootstrap-shared-dtos.md`, `.harness/PROGRESS.md`.
- Estado: **FT00002 `accepted`**. Siguiente feature lista:
  `bootstrap-postgres-pgvector` (FT00003).
- Siguiente mejor paso: implementar `bootstrap-postgres-pgvector` (FT00003) con el
  flujo (aplicando ya la convención de nombres).

### Session 015

- Fecha: 2026-10-10
- Objetivo: **completar** la convención de nombres `Dto` en FT00002
  (`bootstrap-shared-dtos`) para que también los **enums de wire** del contrato
  lleven sufijo, y corregir la documentación durable que decía lo contrario.
- Contexto: la reparación anterior (Session 013/014) dejó `Categoria` y
  `SeccionBoe` sin sufijo y la convención documentada como "enums sin sufijo".
  El orquestador pidió hacerla **consistente**: todo tipo serializable del
  contrato (`:shared`) lleva `Dto`.
- Completado:
  - Renombrados con `git mv` (valores y tokens de wire invariantes):
    `Categoria`→`CategoriaDto` (`CategoriaDto.kt`, 11 valores con `@SerialName`
    snake_case) y `SeccionBoe`→`SeccionBoeDto` (`SeccionBoeDto.kt`, tokens `I`,
    `II.A`, `II.B`, `III`, `V.B`).
  - Referencias actualizadas: `PublicacionDto` (`seccion: SeccionBoeDto`,
    `categoria: CategoriaDto`) y los tests `SerializationTest` y
    `CategoriaWireTest`. `DatoPublicoJson` sin cambios (no es tipo de contrato).
  - Convención durable corregida: `ARCHITECTURE.md` §«Convenciones de nombres» y
    regla **MUST** en `CONSTRAINTS.md` §«Nombres y contratos» — todos los tipos
    serializables del contrato (data classes **y enums de wire**) llevan `Dto`;
    `DatoPublicoJson` sin `Dto`; `...Entity`/`...Row`/`...Ui`; sin prefijos. Nota
    de reparación de `docs/specs/bootstrap-shared-dtos.md` actualizada (incluye
    `CategoriaDto`/`SeccionBoeDto`).
  - `.harness/feature_list.json`: FT00002 → **`in_progress`** con la evidencia
    del renombrado de enums (descripción con `CategoriaDto`/`SeccionBoeDto`).
- Verificación ejecutada (desde `..`, `JAVA_HOME` del JBR 21):
  - `./gradlew :shared:jvmTest --rerun-tasks` → BUILD SUCCESSFUL; XML: SmokeTest
    1/0/0, CategoriaWireTest 3/0/0, SerializationTest 7/0/0 (failures/errors = 0).
  - `./gradlew test` → BUILD SUCCESSFUL (agrega `:shared:jvmTest`,
    `:backend:test`, `:composeApp:jvmTest`).
  - `./gradlew build` → BUILD SUCCESSFUL (16 tareas).
  - grep en `*.kt` de producto: sin referencias stale a `Categoria`/`SeccionBoe`
    como tipos (solo queda el nombre de la clase de test `CategoriaWireTest`).
- Ficheros: `shared/src/commonMain/.../model/{CategoriaDto,SeccionBoeDto}.kt`
  (renombrados con `git mv`), `.../model/PublicacionDto.kt`,
  `.../commonTest/.../{SerializationTest,CategoriaWireTest}.kt`,
  `.harness/{ARCHITECTURE.md,CONSTRAINTS.md,feature_list.json,PROGRESS.md}`,
  `.harness/docs/specs/bootstrap-shared-dtos.md`.
- Riesgo o duda sin resolver: el commit/push/PR y la CI los hace el orquestador;
  queda pendiente la **validación independiente** de esta ampliación.
- Siguiente mejor paso: validación independiente de FT00002 (`feature-validator`)
  tras el renombrado de enums; después, `bootstrap-postgres-pgvector` (FT00003).

### Session 016

- Fecha: 2026-10-10
- Objetivo: cerrar FT00002 tras ampliar la convención `Dto` a los enums y registrar
  el merge del PR #2.
- Completado:
  - Commit de producto en `feat/ft00002-bootstrap-shared-dtos`:
    `872fb2b refactor(FT00002): sufijo Dto en los enums del contrato`
    (`CategoriaDto`/`SeccionBoeDto`, 2 ficheros con `git mv`). Pusheado.
  - **CI en verde**: run `37998033440`, head `872fb2b` (PR #2).
  - **Validación independiente**: veredicto **`accept`** (renombrado íntegro,
    contrato de wire invariante, convención consistente y sin contradicciones).
  - `.harness/feature_list.json`: FT00002 → **`accepted`** (evidencia alineada a
    los nombres `...Dto` y al commit/PR/CI). `docs/feature-ids.md`: `accepted`.
  - **PR #2 fusionado** en `main` (merge `ca781f3`); rama de feature eliminada
    (local; la remota ya la borró GitHub al fusionar).
- Nota: la entrada de Session 014 decía "enums sin sufijo"; quedó **superada** por
  Session 015/016 (la convención final incluye los enums de wire).
- Estado: **FT00002 `accepted` y fusionada**. Siguiente feature lista:
  `bootstrap-postgres-pgvector` (FT00003).
- Siguiente mejor paso: implementar `bootstrap-postgres-pgvector` (FT00003) con el
  flujo (aplicando ya la convención `Dto`).

### Session 017

- Fecha: 2026-10-10
- Objetivo: implementar `bootstrap-postgres-pgvector` (FT00003) en el repo
  público: entorno local reproducible de PostgreSQL + pgvector con Docker Compose
  y migración base de Flyway, sin romper la CI (que corre sin base de datos).
- Completado:
  - `docker-compose.yml` (raíz): servicio `postgres` con `pgvector/pgvector:pg17`,
    volumen nombrado `pgdata`, healthcheck `pg_isready`, puerto configurable
    `${POSTGRES_PORT:-5432}` y credenciales `${POSTGRES_*}` con valores por
    defecto de desarrollo.
  - `.env.example` con las claves `POSTGRES_*` (y `FLYWAY_*` opcionales); `.env`
    en `.gitignore` (+ `!.env.example` para que la plantilla se versione).
  - `gradle/libs.versions.toml`: `flyway = 11.20.3`, `postgresql = 42.7.14`;
    plugin `org.flywaydb.flyway`, `org.flywaydb:flyway-database-postgresql` y
    `org.postgresql:postgresql`.
  - `backend/build.gradle.kts`: plugin Flyway; configuración `flyway` dedicada con
    driver + módulo por motor; extensión `flyway` con `url`/`user`/`password` por
    entorno (`FLYWAY_*`) y `locations` en `filesystem:` absoluto. Tareas
    explícitas (`:backend:flywayMigrate`/`:backend:flywayInfo`), **no** enganchadas
    a `build`/`check`.
  - Migración `backend/src/main/resources/db/migration/V1__esquema_base.sql`:
    `CREATE EXTENSION IF NOT EXISTS vector;` + tabla mínima `esquema_info` con
    fila marcadora. Sin tablas de dominio (FT00008) ni embedding/HNSW (FT00016).
- Verificación ejecutada (desde `..`, JDK 21 JBR; Docker Desktop 29.8.2 + Compose
  v5.6.0):
  - `docker compose up -d` → `postgres` `healthy` en ~2 s; `SELECT 1;` → `1`.
  - `./gradlew :backend:flywayMigrate` → BUILD SUCCESSFUL; `:backend:flywayInfo` →
    `V1 | esquema base | Success`.
  - psql: `extversion` de `vector` = `0.8.7`; `esquema_info` → `(esquema_base,
    FT00003)`; `flyway_schema_history` → `V1` `success=t`.
  - CI sin BD: `docker compose down`; `./gradlew build --dry-run | grep -i flyway`
    → sin resultados; `./gradlew build --no-daemon` → BUILD SUCCESSFUL (17
    tareas). `./gradlew test` verde; `.harness/init.sh` (sin `JAVA_HOME`) → exit 0.
  - `POSTGRES_PORT=55432 docker compose config` → puerto publicado `55432`.
- Hallazgo de implementación: el plugin de Flyway 11 **no** crea una
  configuración `flyway` (usa los classpaths por defecto), así que se crea
  explícitamente y se referencia con `configurations = ["flyway"]`; además
  `flyway-database-postgresql` debe ir en el `buildscript` classpath porque Flyway
  lo resuelve por ServiceLoader desde el build classpath (documentado en el spec
  y en `CONSTRAINTS.md`).
- Ficheros creados/modificados: `docker-compose.yml`, `.env.example`, `.gitignore`,
  `gradle/libs.versions.toml`, `backend/build.gradle.kts`,
  `backend/src/main/resources/db/migration/V1__esquema_base.sql`,
  `.harness/{CONSTRAINTS.md,PROGRESS.md,feature_list.json}`,
  `.harness/docs/{feature-ids.md,specs/bootstrap-postgres-pgvector.md}`.
- Riesgo o duda sin resolver: el commit/push/PR y el run de CI los hace el
  orquestador; queda pendiente la **validación independiente** de FT00003.
- Siguiente mejor paso: validación independiente de FT00003 (`feature-validator`);
  después, `bootstrap-ktor-healthcheck` (FT00004).

### Session 018

- Fecha: 2026-10-10
- Objetivo: cerrar FT00003 (`bootstrap-postgres-pgvector`): commit → CI → PR →
  aceptación.
- Completado:
  - Commit de producto en `feat/ft00003-bootstrap-postgres-pgvector`:
    `9231452 feat(FT00003): PostgreSQL + pgvector en docker-compose y migracion
    base` (6 ficheros, +131/−4). Pusheado.
  - **PR #3** hacia `main`: https://github.com/AviferDev/DatoPublico/pull/3
  - **CI en verde**: run `37999962253`, head `9231452`.
  - **Validación independiente**: veredicto **`accept`**; reejecutó los 4
    escenarios con Docker real (BD `healthy`, `vector` 0.8.7, `V1` Success,
    `./gradlew build` sin BD) y dejó el entorno limpio. Sin hallazgos bloqueantes.
  - `.harness/feature_list.json`: FT00003 → **`accepted`** (evidencia con
    commit/PR/CI/aceptación). `docs/feature-ids.md`: FT00003 → `accepted`.
- Nota de claridad (hallazgo *Low* del validator, resuelto): se precisó en la skill
  `ktor-backend-architecture` §«Docker y entorno local» que en **local** las
  migraciones se aplican con `:backend:flywayMigrate` (tarea explícita, fuera de
  `build`/`check`) y que el backend en producción aplicará al arrancar (FT00004+).
- Estado: **FT00003 `accepted`**. Siguiente feature lista:
  `bootstrap-ktor-healthcheck` (FT00004).
- Siguiente mejor paso: implementar `bootstrap-ktor-healthcheck` (FT00004) con el
  flujo.

### Session 019

- Fecha: 2026-10-10
- Objetivo: **reparación de seguridad** de `bootstrap-postgres-pgvector`
  (FT00003): eliminar credenciales de ficheros versionados y el default silencioso
  inseguro. Sin ampliar alcance funcional.
- Diagnóstico: `backend/build.gradle.kts` tenía una contraseña literal como
  *fallback* (`password = System.getenv("FLYWAY_PASSWORD") ?: "datopublico"`);
  `docker-compose.yml` un default inseguro (`POSTGRES_PASSWORD:-datopublico`); y
  el puerto se publicaba en `0.0.0.0`. Riesgo: credencial versionada y, sobre
  todo, que un `FLYWAY_PASSWORD` ausente en producción **no** fallara (usaría el
  default en silencio).
- Completado:
  - `backend/build.gradle.kts`: sin contraseña literal. La conexión `FLYWAY_*` se
    resuelve del entorno y, si falta, del `.env` de la raíz (parser mínimo
    `clave=valor`, sin imprimir valores). `url`/`user` conservan default no
    sensible; `password` no: si falta, `flywayPasswordOrFail()` lanza
    `FLYWAY_PASSWORD no definido: copia .env.example a .env o expórtalo`. La
    validación se ejecuta en `doFirst` sobre las tareas `AbstractFlywayTask`
    (la extensión del plugin usa `String`, no un `Provider`), así
    `./gradlew build` sigue verde sin `.env` ni BD.
  - `docker-compose.yml`: `POSTGRES_PASSWORD` obligatorio
    (`${POSTGRES_PASSWORD:?define POSTGRES_PASSWORD en .env}`) y puerto publicado
    solo en loopback (`127.0.0.1:${POSTGRES_PORT:-5432}:5432`).
  - `.env.example`: `POSTGRES_PASSWORD`/`FLYWAY_PASSWORD` con *placeholder*
    explícito de desarrollo (`cambia_esta_clave_local`), documentado como no
    secreto; comentario de `FLYWAY_*` actualizado (el build ya no tiene default de
    contraseña).
  - `CONSTRAINTS.md` §«Operación»: MUST NOT de versionar credenciales (ni de
    desarrollo), MUST de fail-fast ante secreto ausente y MUST de Postgres local
    solo en loopback.
  - Nota de reparación en `docs/specs/bootstrap-postgres-pgvector.md`;
    `feature_list.json` (FT00003 → `in_progress`) y verificación ampliada.
- Verificación ejecutada (desde `..`, `JAVA_HOME` del JBR 21; Docker 29.8.2 +
  Compose v5.6.0). `.env` creado desde `.env.example` con contraseña de prueba
  (ignorado por git):
  - `docker compose up -d` → `datopublico-postgres` `Up (healthy)`;
    `SELECT 1;` → `1`; puerto publicado `127.0.0.1:5432->5432/tcp`.
  - `./gradlew :backend:flywayMigrate` → BUILD SUCCESSFUL;
    `:backend:flywayInfo` → `V1 | esquema base | SQL | Success`;
    `flyway_schema_history` → `V1 success=t`; `vector` → `0.8.7`;
    `esquema_info` → `(esquema_base, FT00003)`.
  - **Fail-fast**: sin `.env` ni `FLYWAY_PASSWORD`,
    `./gradlew :backend:flywayInfo` → exit 1 con
    `FLYWAY_PASSWORD no definido: copia .env.example a .env o expórtalo`;
    `docker compose config` sin `POSTGRES_PASSWORD` → exit 1 con
    `define POSTGRES_PASSWORD en .env`.
  - **CI sin BD**: `docker compose down` y `./gradlew build --no-daemon` (sin
    `.env` ni `FLYWAY_PASSWORD`) → BUILD SUCCESSFUL (17 tareas);
    `./gradlew build --dry-run | grep -i flyway` → sin resultados. Gate estándar
    `env -u JAVA_HOME .harness/init.sh` → exit 0.
  - **Grep** en ficheros rastreados: sin contraseña literal `datopublico` en
    código/compose (solo `POSTGRES_DB`/`POSTGRES_USER`/nombre de contenedor y la
    URL JDBC); el único valor de contraseña es el placeholder de `.env.example`.
  - Entorno limpiado: `docker compose down -v` (contenedor, volumen y red
    eliminados) y `.env` borrado; nada de `.env` versionado.
- Ficheros modificados: `backend/build.gradle.kts`, `docker-compose.yml`,
  `.env.example` (producto); `.harness/{CONSTRAINTS.md,PROGRESS.md,feature_list.json}`,
  `.harness/docs/specs/bootstrap-postgres-pgvector.md`.
- Riesgo o duda sin resolver: el commit/push/PR y el run de CI los hace el
  orquestador; queda pendiente la **validación independiente** de la reparación.
- Siguiente mejor paso: validación independiente de FT00003 (`feature-validator`)
  tras la reparación de seguridad; después, `bootstrap-ktor-healthcheck` (FT00004).

### Session 020

- Fecha: 2026-10-10
- Objetivo: cerrar la reparación de seguridad de FT00003
  (`bootstrap-postgres-pgvector`): commit → CI → PR → aceptación.
- Completado:
  - Commit de producto en `feat/ft00003-bootstrap-postgres-pgvector`:
    `44b8d50 fix(FT00003): eliminar credenciales versionadas y ligar Postgres a
    loopback` (3 ficheros). Pusheado.
  - **CI en verde**: run `38001658074`, head `44b8d50` (PR #3).
  - **Validación independiente**: veredicto **`accept`**; confirmó ausencia de
    credenciales versionadas, fail-fast (Flyway y Compose), Postgres en loopback y
    `./gradlew build` verde sin BD; sin hallazgos de seguridad.
  - `.harness/feature_list.json`: FT00003 → **`accepted`** (evidencia con
    commit/PR/CI/aceptación). `docs/feature-ids.md`: FT00003 → `accepted`.
- Ficheros: `.harness/feature_list.json`, `.harness/docs/feature-ids.md`,
  `.harness/PROGRESS.md`.
- Estado: **FT00003 `accepted`**. Siguiente feature lista:
  `bootstrap-ktor-healthcheck` (FT00004).
- Siguiente mejor paso: implementar `bootstrap-ktor-healthcheck` (FT00004) con el
  flujo.

### Session 021

- Fecha: 2026-10-10
- Objetivo: reparar el hallazgo L2 de FT00003
  (`bootstrap-postgres-pgvector`): la conexión de Flyway debe **derivarse** de
  `POSTGRES_*` en vez de duplicar la URL/contraseña. Sin ampliar alcance.
- Diagnóstico: `.env.example` fijaba
  `FLYWAY_URL=jdbc:postgresql://localhost:5432/datopublico` y `FLYWAY_PASSWORD`
  repetía el valor de `POSTGRES_PASSWORD`. Riesgo: cambiar `POSTGRES_PORT` (o
  host/db) dejaba a Flyway apuntando a otro sitio.
- Completado:
  - `backend/build.gradle.kts`: conexión derivada de las piezas con `FLYWAY_*`
    como *override* opcional — `host=FLYWAY_HOST?:POSTGRES_HOST?:'localhost'`,
    `port=FLYWAY_PORT?:POSTGRES_PORT?:'5432'`,
    `db=FLYWAY_DB?:POSTGRES_DB?:'datopublico'`,
    `user=FLYWAY_USER?:POSTGRES_USER?:'datopublico'`,
    `password=FLYWAY_PASSWORD?:POSTGRES_PASSWORD` (fail-fast si faltan ambos) y
    `url=FLYWAY_URL?:'jdbc:postgresql://$host:$port/$db'`. Se conservan el
    cargador de `.env` de la raíz y la validación en `doFirst` (así `build`/`check`
    siguen verdes sin BD); no se imprimen valores.
  - `.env.example`: solo `POSTGRES_*` como **fuente única de verdad**
    (`POSTGRES_PASSWORD` obligatoria; `POSTGRES_PORT` opcional con default 5432);
    `FLYWAY_*` documentadas como *overrides* opcionales comentados, sin duplicar
    la contraseña.
  - `CONSTRAINTS.md` §«Operación»: MUST de no duplicar la configuración de
    conexión entre herramientas (una sola fuente `POSTGRES_*`; `FLYWAY_*` solo
    *override*).
  - Nota de reparación en `docs/specs/bootstrap-postgres-pgvector.md`;
    `feature_list.json` (FT00003 → `in_progress`) y `docs/feature-ids.md`.
- Verificación ejecutada (desde `..`, `JAVA_HOME` del JBR 21; Docker 29.8.2 +
  Compose v5.6.0). `.env` con **solo `POSTGRES_*`** (sin `FLYWAY_*`):
  - `docker compose up -d` → `datopublico-postgres` `Up (healthy)`; `SELECT 1` →
    `1`; `./gradlew :backend:flywayMigrate` → BUILD SUCCESSFUL;
    `:backend:flywayInfo` → `V1 | esquema base | SQL | Success`;
    `flyway_schema_history` → `V1 success=t`; `vector` → `0.8.7`;
    `esquema_info` → `(esquema_base, FT00003)`.
  - **Derivación de puerto**: `.env` con `POSTGRES_PORT=5433` (sin tocar
    `FLYWAY_*`) y volumen fresco → `docker compose ps` publica
    `127.0.0.1:5433->5432/tcp`; `:backend:flywayMigrate` → BUILD SUCCESSFUL;
    `flywayInfo` → `V1 ... Success`. También conecta exportando **solo**
    `POSTGRES_*` (sin `.env` ni `FLYWAY_*`).
  - **Fail-fast**: sin `.env` ni `POSTGRES_PASSWORD`/`FLYWAY_PASSWORD`,
    `./gradlew :backend:flywayInfo` → FAILURE con
    `Contraseña de base de datos no definida: define POSTGRES_PASSWORD en .env
    (o expórtala, o usa FLYWAY_PASSWORD como override)`.
  - **CI sin BD**: `docker compose down -v` y `./gradlew build --no-daemon` (sin
    `.env` ni passwords) → BUILD SUCCESSFUL (17 tareas);
    `./gradlew build --dry-run | grep -i flyway` → sin resultados; gate estándar
    `env -u JAVA_HOME .harness/init.sh` → exit 0.
  - Entorno limpiado: `docker compose down -v` (contenedor, volumen y red
    eliminados) y `.env` borrado; nada de `.env` versionado.
- Ficheros modificados: `backend/build.gradle.kts`, `.env.example` (producto);
  `.harness/{CONSTRAINTS.md,PROGRESS.md,feature_list.json}`,
  `.harness/docs/{specs/bootstrap-postgres-pgvector.md,feature-ids.md}`.
- Riesgo o duda sin resolver: el commit/push/PR y el run de CI los hace el
  orquestador; queda pendiente la **validación independiente** de la reparación.
- Siguiente mejor paso: validación independiente de FT00003 (`feature-validator`)
  tras la reparación de conexión; después, `bootstrap-ktor-healthcheck` (FT00004).

### Session 022

- Fecha: 2026-10-10
- Objetivo: **limpieza de comentarios** de FT00003
  (`bootstrap-postgres-pgvector`): dejar los comentarios de código al mínimo y
  mover lo explicativo a un Markdown. Sin cambiar comportamiento ni alcance.
- Completado:
  - Nuevo `docs/desarrollo-local.md` (repo de producto): requisitos (JDK 21,
    Docker/Colima), arranque de la BD (`cp .env.example .env` + `docker compose
    up -d`), migraciones Flyway (`:backend:flywayMigrate`/`:backend:flywayInfo`,
    fuera de `build`/`check`), variables (`POSTGRES_*` fuente única; `FLYWAY_*`
    *overrides*; URL derivada `jdbc:postgresql://host:port/db`) y notas
    (`flyway-database-postgresql` en el buildscript, loopback, fail-fast sin
    credenciales). Enlazado desde `README.md` (sección «Desarrollo local»).
  - `backend/build.gradle.kts`: eliminado el bloque de cabecera y los comentarios
    largos (~57 líneas de comentario → 4 de una línea, solo en lo no obvio:
    buildscript, parser de `.env`, `flywayPasswordOrFail` y `doFirst`). Sin
    cambios en `buildscript`/`dependencies`/lógica.
  - `docker-compose.yml`: eliminado el bloque de cabecera; queda `# Solo loopback.`.
  - `.env.example`: eliminado el bloque de cabecera; comentarios mínimos de una
    línea por clave.
  - `git diff` de los tres ficheros: **solo comentarios** (sin cambios de
    comportamiento).
- Verificación ejecutada (desde `..`, `JAVA_HOME` del JBR 21; Docker 29.8.2 +
  Compose v5.6.0). `.env` con `POSTGRES_*` (puerto 5432):
  - `docker compose up -d` → `datopublico-postgres` `Up (healthy)`,
    `127.0.0.1:5432->5432/tcp`; `SELECT 1;` → `1`.
  - `./gradlew :backend:flywayMigrate` → BUILD SUCCESSFUL;
    `:backend:flywayInfo` → `V1 | esquema base | SQL | Success`;
    `vector` → `0.8.7`; `esquema_info` → `(esquema_base, FT00003)`.
  - **CI sin BD**: `docker compose down -v` + `.env` borrado y
    `./gradlew build --no-daemon` → BUILD SUCCESSFUL (17 tareas);
    `./gradlew build --dry-run | grep -i flyway` → sin resultados.
  - Entorno limpiado (`docker compose down -v`, `.env` borrado).
- Ficheros modificados: `docs/desarrollo-local.md` (nuevo), `README.md`,
  `backend/build.gradle.kts`, `docker-compose.yml`, `.env.example` (producto);
  `.harness/{PROGRESS.md,feature_list.json}`,
  `.harness/docs/specs/bootstrap-postgres-pgvector.md`.
- Riesgo o duda sin resolver: el commit/push/PR y el run de CI los hace el
  orquestador; queda pendiente la **validación independiente** de la limpieza.
- Siguiente mejor paso: validación independiente de FT00003 (`feature-validator`)
  tras la limpieza de comentarios; después, `bootstrap-ktor-healthcheck` (FT00004).

### Session 023

- Fecha: 2026-10-10
- Objetivo: cerrar las reparaciones de FT00003 (`bootstrap-postgres-pgvector`):
  derivación de la conexión y limpieza de comentarios.
- Completado:
  - Commits de producto en `feat/ft00003-bootstrap-postgres-pgvector`:
    `bc57224 refactor(FT00003): derivar la conexion de Flyway de POSTGRES_*` y
    `55217b6 docs(FT00003): reducir comentarios y mover la guia a
    docs/desarrollo-local.md`. Pusheado.
  - **CI en verde**: run `38033346128`, head `55217b6` (PR #3).
  - **Validación independiente**: veredicto **`accept`**; reejecutó la derivación
    (incluida prueba negativa de puerto y overrides `FLYWAY_*`), el fail-fast, la
    ausencia de credenciales y confirmó que la limpieza es solo comentarios/docs.
  - `.harness/feature_list.json`: FT00003 → **`accepted`** (evidencia con commits,
    PR, CI y aceptación). `docs/feature-ids.md`: FT00003 → `accepted`.
- Notas *Low* del validator (opcionales, no bloquean):
  - `docker compose down` también exige `POSTGRES_PASSWORD` (DX): derribar con
    `POSTGRES_PASSWORD=x docker compose down -v` o documentarlo.
  - El literal de dev `?: "datopublico"` sigue en el historial de la rama (commit
    `9231452`): **recomendado squash-merge** del PR #3 para no arrastrarlo a
    `main`.
- Estado: **FT00003 `accepted`**. Siguiente feature lista:
  `bootstrap-ktor-healthcheck` (FT00004).
- Siguiente mejor paso: implementar `bootstrap-ktor-healthcheck` (FT00004) con el
  flujo.

### Session 024

- Fecha: 2026-10-10
- Objetivo: implementar `bootstrap-ktor-healthcheck` (FT00004) en el repo público:
  esqueleto del backend Ktor (Netty) con configuración por entorno, logging
  estructurado JSON y healthcheck `GET /health`, sin depender de la base de datos;
  dejar los artefactos listos para validación independiente (commit/push/PR los
  gestiona el orquestador).
- Completado (producto, rama `feat/ft00004-bootstrap-ktor-healthcheck`):
  - `gradle/libs.versions.toml`: `logback = 1.5.12` y `logstashLogback = 8.0`;
    aliases `ktor-server-content-negotiation`, `ktor-server-call-logging`,
    `ktor-server-test-host`, `logback-classic` y `logstash-logback-encoder`.
  - `backend/build.gradle.kts`: plugins `application`, `io.ktor.plugin` y
    `org.jetbrains.kotlin.plugin.serialization`; `mainClass` =
    `es.aviferdev.datopublico.backend.ApplicationKt` (no `EngineMain`, sin
    `application.conf`); dependencias de servidor Ktor + logback/logstash y
    `ktor-server-test-host` para tests. La configuración Flyway queda intacta y
    fuera de `build`/`check`.
  - `Application.kt` (composition root: `embeddedServer(Netty, port, host,
    module = Application::module)`, sin BD/Hikari/Flyway),
    `infra/AppConfig.kt` (`fromEnv(map)` con defaults y fail-fast de puerto) y
    `plugins/` (`Serialization` con `DatoPublicoJson` de `:shared`, `Monitoring`
    con `CallLogging`, `Routing` y `Health` con `HealthDto` + `GET /health`).
  - `backend/src/main/resources/logback.xml`: `ConsoleAppender` +
    `LogstashEncoder` (una línea JSON por evento, solo stdout) con
    `app=datopublico-backend`, `env=${APP_ENV:-local}` y nivel raíz
    `${LOG_LEVEL:-INFO}`.
  - Tests: `plugins/HealthTest` (`testApplication`, 2 tests) e
    `infra/AppConfigTest` (6 tests); `SmokeTest` intacto.
  - Documentación durable: `ARCHITECTURE.md` (`:backend` deja de ser
    pre-bootstrap), `CONSTRAINTS.md` (MUST de arranque independiente de BD y
    servicios + config por entorno con fail-fast), `docs/desarrollo-local.md`
    (arranque del backend, variables y logs JSON) y la skill
    `ktor-backend-architecture` (`Estado actual`); `init.sh` sin cambios.
- Verificación ejecutada (desde `..`, `JAVA_HOME` del JBR 21):
  - **Hallazgo de implementación**: sin el plugin de serialización en `:backend`,
    `HealthDto` no generaba serializador (`Serializer for class 'HealthDto' is not
    found`); se añadió `org.jetbrains.kotlin.plugin.serialization` y el test pasó.
  - `SERVER_PORT=8090 APP_ENV=staging ./gradlew :backend:run` → log JSON
    `Responding at http://0.0.0.0:8090` (`"env":"staging"`); `curl` →
    `200` `{"status":"ok"}` con `Content-Type: application/json` y línea de
    CallLogging `200 OK: GET - /health`; proceso detenido y puerto 8090 libre.
  - Sin variables: `./gradlew :backend:run` → `Responding at
    http://0.0.0.0:8080` y `curl http://10.123.123.65:8080/health` →
    `200 {"status":"ok"}`. **Nota de entorno**: en esta máquina
    `127.0.0.1:8080` lo ocupa el mux SSH de Colima, así que `curl
    localhost:8080` responde a ese otro servicio; la comprobación del puerto por
    defecto se hizo contra la IP de LAN (artefacto del entorno, no del código).
  - Fail-fast: `SERVER_PORT=no-es-un-numero ./gradlew :backend:run` → exit 1 con
    `IllegalArgumentException: Puerto inválido: 'no-es-un-numero'. Define
    SERVER_PORT (o PORT) como un entero entre 1 y 65535.`; sin procesos
    escuchando.
  - `./gradlew :backend:test --rerun-tasks` → BUILD SUCCESSFUL; XML: SmokeTest
    `1/0/0`, AppConfigTest `6/0/0`, HealthTest `2/0/0` (9 tests, 0 fallos).
  - Gate sin BD (sin `.env`): `./gradlew test` → BUILD SUCCESSFUL (3 módulos);
    `./gradlew build --no-daemon` → BUILD SUCCESSFUL (25 tareas);
    `./gradlew build --dry-run --no-daemon | grep -i flyway` → sin resultados;
    `env -u JAVA_HOME .harness/init.sh` → exit 0.
- Ficheros creados/modificados: `gradle/libs.versions.toml`,
  `backend/build.gradle.kts`,
  `backend/src/main/kotlin/es/aviferdev/datopublico/backend/{Application.kt,infra/AppConfig.kt,plugins/Serialization.kt,plugins/Monitoring.kt,plugins/Routing.kt,plugins/Health.kt}`,
  `backend/src/main/resources/logback.xml`,
  `backend/src/test/kotlin/es/aviferdev/datopublico/backend/{plugins/HealthTest.kt,infra/AppConfigTest.kt}`
  (bloque de producto); `docs/desarrollo-local.md` (producto);
  `.harness/{ARCHITECTURE.md,CONSTRAINTS.md,PROGRESS.md,feature_list.json}`,
  `.harness/docs/feature-ids.md`,
  `.harness/.agents/skills/ktor-backend-architecture/SKILL.md`.
- Riesgo o duda sin resolver: el commit/push/PR y el run de CI los hace el
  orquestador; queda pendiente la **validación independiente** de FT00004. El
  escenario 1 no se pudo comprobar por `localhost:8080` por el mux SSH de Colima.
- Siguiente mejor paso: validación independiente de FT00004
  (`feature-validator`); después, `bootstrap-cmp-targets` (FT00005).

### Session 025

- Fecha: 2026-10-10
- Objetivo: cerrar FT00004 (`bootstrap-ktor-healthcheck`): validación
  independiente → commit → push → PR → CI → aceptación.
- Completado:
  - **Validación independiente** (`feature-validator`): veredicto **`accept`**.
    Reejecutó el plan completo: `:backend:test --rerun-tasks` (SmokeTest 1/0/0,
    AppConfigTest 6/0/0, HealthTest 2/0/0), arranque real `:backend:run` con
    `/health` → `200 {"status":"ok"}` (`application/json`, puerto 8090 por entorno
    y 8080 por defecto), fail-fast de puerto inválido (exit 1, nada escuchando),
    gate sin BD (`build` 25 tareas, `test` 3 módulos, `--dry-run | grep flyway`
    vacío, `init.sh` exit 0) y sin hallazgos de seguridad. Confirmó el alcance por
    grep (sin hikari/datasource/flyway/cors/ratelimit/openapi/EngineMain/
    application.conf en `backend/src`) y que la atribución de la evidencia era
    real (los recuentos 9 tests / 25 tareas coinciden).
  - Commit de producto en `feat/ft00004-bootstrap-ktor-healthcheck`:
    `9266729 feat(FT00004): complete bootstrap-ktor-healthcheck` (12 ficheros,
    +310/−5). Pusheado.
  - **PR #4** hacia `main`: https://github.com/AviferDev/DatoPublico/pull/4
  - **CI en verde**: run `38034700464`, head `9266729` (job "Build and test"
    SUCCESS).
  - `.harness/feature_list.json`: FT00004 → **`accepted`** (notas y evidencia con
    la validación independiente y la deuda menor L1–L4). `docs/feature-ids.md`:
    FT00004 → `accepted`.
- Notas *Low* del validator (no bloquean; deuda para features de observabilidad):
  - L1 — `Monitoring.kt` usa el `format` por defecto de `CallLogging`, que colorea;
    el campo `message` de los logs JSON lleva escapes ANSI (mejora: `format` sin
    color).
  - L2 — `AppConfig.environment`/`logLevel` se declaran y los consume Logback
    (`${APP_ENV}`/`${LOG_LEVEL}`), no el código.
  - L3 — KDoc de `Monitoring.kt` dice «nivel configurado» pero `CallLogging` está a
    `Level.INFO` fijo (el nivel raíz sí lo aplica Logback).
  - L4 — `localhost:8080` en `docs/desarrollo-local.md` es artefacto del mux SSH
    de Colima en esta máquina.
- Estado: **FT00004 `accepted` y fusionada** (PR #4 fusionado, merge `1e32f4c`).
  Siguiente feature lista: `bootstrap-cmp-targets` (FT00005).
- Siguiente mejor paso: implementar `bootstrap-cmp-targets` (FT00005) con el
  flujo.
- Duda abierta (DX, no bloqueante): el backend Ktor lee el entorno del proceso
  (`System.getenv()`), no el fichero `.env` (que solo consumen docker-compose y
  Flyway); las variables `SERVER_*`/`APP_ENV`/`LOG_LEVEL` están documentadas en
  `docs/desarrollo-local.md` pero no en `.env.example`. Pendiente decidir si se
  cablea el `.env` en `:backend:run` o se aclara la documentación.

### Session 026

- Fecha: 2026-10-10
- Objetivo: implementar `bootstrap-cmp-targets` (FT00005) en el repo público:
  esqueleto del cliente **Compose Multiplatform** (Android, Web/Wasm, iOS) con una
  **pantalla mínima compartida** en `commonMain` y un entrypoint por plataforma,
  sin ampliar targets de `:shared`, sin pantallas reales/red y manteniendo el gate
  estándar en verde sin Xcode ni base de datos.
- Completado (producto, rama `feat/ft00005-bootstrap-cmp-targets`):
  - `composeApp/build.gradle.kts`: plugins `kotlin.multiplatform` +
    `compose.multiplatform` + `compose.compiler` + `android.application`; targets
    `androidTarget()`, `iosArm64()`/`iosSimulatorArm64()` (framework estático
    `ComposeApp`), `wasmJs { browser(); binaries.executable() }`; se conserva
    `jvm()`; bloque `android { }` (`namespace`/`applicationId`
    `es.aviferdev.datopublico`, `compileSdk`/`targetSdk` 35, `minSdk` 26,
    `compileOptions` Java 21); dependencias por source set (`compose.*` en
    `commonMain`, `activity-compose` + `compose.preview` en `androidMain`).
  - `commonMain` (`es.aviferdev.datopublico.app.App()`): `MaterialTheme` con
    `primary` `#1A4D8F`/`background` `#F7F9FC` de `DESIGN.md`, `Surface` +
    `Column`/`Text` («DatoPublico» + «Esqueleto Compose Multiplatform»),
    `@Preview`. Textos literales **a propósito** (recursos fuera de alcance,
    FT00032+).
  - Entrypoints: `androidMain/MainActivity.kt` + `androidMain/AndroidManifest.xml`
    (LAUNCHER, icono de sistema), `wasmJsMain/main.kt`
    (`ComposeViewport(document.body!!)`) + `wasmJsMain/resources/index.html`
    (`composeApp.js`), `iosMain/MainViewController.kt` (`ComposeUIViewController`).
  - Catálogo/propiedades: `androidxActivityCompose = 1.9.3` y alias
    `androidx-activity-compose`; `android.useAndroidX=true` +
    `android.nonTransitiveRClass=true`; `local.properties` (gitignored) con
    `sdk.dir` para la verificación local.
  - `settings.gradle.kts`: de `FAIL_ON_PROJECT_REPOS` a
    `RepositoriesMode.PREFER_SETTINGS` + repositorios Ivy de **Binaryen/Node/Yarn**
    (layout exacto del plugin). `kotlin-js-store/yarn.lock` versionado.
- Verificación ejecutada (desde `..`, `JAVA_HOME` del JBR 21):
  - **Hallazgo 1**: con `FAIL_ON_PROJECT_REPOS`, el plugin de Kotlin/Wasm rompe el
    build en `:composeApp:kotlinBinaryenSetup` (`repository ... was added by
    unknown code`); se resuelve declarando los repos Ivy en el settings y usando
    `PREFER_SETTINGS` (documentado y añadido a `CONSTRAINTS.md`).
  - **Hallazgo 2**: la ruta `nodejs()` para tests Wasm (sugerida por el spec)
    **falla** (`Skiko .wasm` no carga bajo Node); se mantiene `browser()` y se
    desactiva `wasmJsBrowserTest` del gate (la máquina no tiene Chrome).
  - Escenario 1: `./gradlew :composeApp:assembleDebug` → BUILD SUCCESSFUL;
    `composeApp/build/outputs/apk/debug/composeApp-debug.apk` (8.740.700 bytes).
  - Escenario 2: `./gradlew :composeApp:wasmJsBrowserDistribution` → BUILD
    SUCCESSFUL; dist con `index.html`, `composeApp.js` y dos `.wasm`; servida en
    `127.0.0.1:8123` y abierta en el navegador: la app monta un `<canvas>` (984×154
    CSS px) sin errores de consola (solo warnings WebGL de Skiko). Sin captura
    visual (ventana no visible en este entorno).
  - Escenario 3: `:composeApp:compileKotlinIosSimulatorArm64` → BUILD SUCCESSFUL;
    `:composeApp:linkDebugFrameworkIosSimulatorArm64` → BUILD SUCCESSFUL;
    `.../debugFramework/ComposeApp.framework`.
  - Escenario 5: `./gradlew build --no-daemon` → BUILD SUCCESSFUL (196 tareas,
    incluido `:composeApp:lint`). **Escenario 6**: `./gradlew test` → BUILD
    SUCCESSFUL (SmokeTest 1/0/0 en `jvmTest`/`testDebugUnitTest`/
    `testReleaseUnitTest`/`iosSimulatorArm64Test`; `:shared` 11 tests; `:backend` 9).
    Gate: `env -u JAVA_HOME .harness/init.sh` → exit 0.
  - `SmokeTest` intacto; `jvm()` conservado (la task raíz `test` sigue agregando
    `:composeApp:jvmTest`).
- Documentación durable: `ARCHITECTURE.md` (`:composeApp` deja de ser
  pre-bootstrap), `CONSTRAINTS.md` (MUST: UI compartida en `commonMain` y solo
  entrypoints; gate sin Xcode/navegador; `PREFER_SETTINGS` + repos Ivy de
  Kotlin/Wasm), skill `compose-multiplatform-architecture` (§Estado actual y
  topología) y `docs/desarrollo-local.md` (producto). Notas de implementación en
  `docs/specs/bootstrap-cmp-targets.md`. `init.sh` sin cambios.
- Ficheros creados/modificados (producto): `composeApp/build.gradle.kts`,
  `gradle/libs.versions.toml`, `gradle.properties`, `settings.gradle.kts`,
  `composeApp/src/commonMain/.../App.kt`,
  `composeApp/src/androidMain/{AndroidManifest.xml,kotlin/.../MainActivity.kt}`,
  `composeApp/src/iosMain/kotlin/.../MainViewController.kt`,
  `composeApp/src/wasmJsMain/{kotlin/.../main.kt,resources/index.html}`,
  `kotlin-js-store/yarn.lock`, `docs/desarrollo-local.md`; harness:
  `.harness/{ARCHITECTURE.md,CONSTRAINTS.md,PROGRESS.md,feature_list.json}`,
  `.harness/docs/{feature-ids.md,specs/bootstrap-cmp-targets.md}`,
  `.harness/.agents/skills/compose-multiplatform-architecture/SKILL.md`.
- Riesgo o duda sin resolver: commit/push/PR/CI los hace el orquestador; queda
  pendiente la **validación independiente**. La verificación visual de la pantalla
  Wasm no produce captura (canvas + ventana no visible); el CI (ubuntu, sin Chrome
  ni Xcode) debe confirmar el escenario 5.
- Siguiente mejor paso: validación independiente de FT00005
  (`feature-validator`); después, `boe-sumario-cliente` (FT00006).

### Session 027

- Fecha: 2026-10-10
- Objetivo: cerrar `bootstrap-cmp-targets` (FT00005): validación independiente →
  aceptación → commit → push → PR.
- Completado:
  - **Validación independiente** (`feature-validator`): veredicto **`accept`**.
    Reejecutó con salidas reales: `:composeApp:assembleDebug` (APK 8.740.700 B),
    `:composeApp:wasmJsBrowserDistribution` (dist servida con `Content-Type`
    correctos: `*.wasm` → `application/wasm`),
    `compileKotlinIosSimulatorArm64` + `linkDebugFrameworkIosSimulatorArm64` con
    `--rerun-tasks` (`ComposeApp.framework` con binario/`Headers`/`Modules`/
    `Info.plist`), `App()` única (literales embebidos en `.dex`, `.framework` y
    `.wasm`), `./gradlew test` (0 fallos; mismos recuentos), `build --no-daemon`
    (196 tareas, `wasmJsBrowserTest SKIPPED`), `build --dry-run | grep flyway`
    vacío, `:composeApp:lint` «No issues found.» e `init.sh` exit 0. Aceptó las
    dos desviaciones de build como acotadas y justificadas; sin hallazgos de
    seguridad. Detalle en `docs/validations/bootstrap-cmp-targets.md`.
  - `.harness/feature_list.json`: FT00005 → **`accepted`** (evidencia con la
    validación independiente y la deuda Low). `docs/feature-ids.md`: FT00005 →
    `accepted`.
  - Commit de producto `0f47d03 feat(FT00005): complete bootstrap-cmp-targets` en
    `feat/ft00005-bootstrap-cmp-targets`. **PR #5** hacia `main`:
    https://github.com/AviferDev/DatoPublico/pull/5
  - **CI en verde**: run `38037289572`, job "Build and test" SUCCESS (5m16s) para
    el head `0f47d03`.
  - **PR #5 fusionado** en `main` (merge commit `136eedf`). Rama de feature
    eliminada (local y remota). `main` local sincronizada con `origin/main`.
- Notas *Low* del validator (no bloquean; deuda menor):
  1. `wasmJsBrowserTest` desactivado globalmente también salta en CI (ubuntu, con
     Chrome); revisar al llegar UI Wasm real (FT00032+).
  2. `<div id="root">` de `wasmJsMain/resources/index.html` queda sin usar (se
     monta en `document.body`).
  3. Textos literales en `App.kt` (intencional por non-goals; recursos → FT00032+).
  4. Aviso de deprecación de Gradle 9.0 preexistente (ajeno a la feature).
- Ficheros (harness): `.harness/feature_list.json`, `.harness/docs/feature-ids.md`,
  `.harness/docs/validations/bootstrap-cmp-targets.md`,
  `.harness/PROGRESS.md`.
- Estado: **FT00005 `accepted` y fusionada** (PR #5 fusionado, merge `136eedf`;
  CI en verde run `38037289572`; rama eliminada). Siguiente feature lista:
  `boe-sumario-cliente` (FT00006).
- Siguiente mejor paso: implementar `boe-sumario-cliente` (FT00006) con el flujo.

### Session 028

- Fecha: 2026-10-10
- Objetivo: implementar `boe-sumario-cliente` (FT00006) en el repo público: cliente
  del sumario diario del BOE en `:backend` (secciones I, II.A, II.B, III y V.B),
  con su modelo interno, serializador «objeto o array», tests sin red y un test
  opt-in contra la API real.
- Completado:
  - **Catálogo y build**: `gradle/libs.versions.toml` añade `ktor-client-cio` y
    `ktor-client-mock` (version.ref `ktor` 3.0.3); `:backend` añade
    `implementation` de `ktor-client-core`/`-cio`/`-content-negotiation` y
    `testImplementation` de `ktor-client-mock` y `kotlinx-coroutines-test`. Flyway,
    `:shared`, `:composeApp`, la raíz del build y el CI sin cambios.
  - **Producción** (`backend/src/main/kotlin/.../ingesta/sumario/`):
    `SumarioWireDto.kt` (DTOs de transporte `@Serializable` con `@SerialName`),
    `SingleOrArraySerializer.kt` (serializador genérico objeto/array + 5 objetos
    concretos), `EntradaSumario.kt` (modelo interno sin `Dto`), `BoeSumarioClient.kt`
    (interfaz + `BoeSumarioException` + mapeo) y `BoeSumarioHttpClient.kt`
    (`HttpClient` inyectado, `GET {base}/boe/sumario/{YYYYMMDD}` con
    `Accept: application/json`, `404`→vacío, error tipado; factory CIO +
    `ContentNegotiation` con `DatoPublicoJson`).
  - **Fixtures reales** capturados con `curl` (`Accept: application/json`, HTTP
    200): `backend/src/test/resources/boe/sumario-20261009.json` (item objeto y
    array; incluye V.A) y `sumario-20240102.json` (item y departamento objeto;
    incluye IV y V.A).
  - **Tests**: `SumarioParsingTest` (3), `BoeSumarioClientTest` (5, `MockEngine`) y
    `BoeSumarioLiveTest` (1, opt-in `BOE_LIVE_TEST=1`, fuera del gate).
  - **Docs durables**: `ARCHITECTURE.md` (frontera Backend→BOE y `ingesta/sumario/`),
    `CONSTRAINTS.md` (MUST: gate sin llamadas de red; pruebas externas opt-in fuera
    de gate/CI) y `docs/desarrollo-local.md` (cliente + check opt-in + nota del
    truststore). `init.sh` sin cambios.
- Verificación ejecutada (desde `..`, JAVA_HOME del JBR 21):
  - `./gradlew :backend:test --rerun-tasks` → BUILD SUCCESSFUL; XML sin
    failures/errors: SmokeTest 1/0/0, AppConfigTest 6/0/0, HealthTest 2/0/0,
    SumarioParsingTest 3/0/0, BoeSumarioClientTest 5/0/0, BoeSumarioLiveTest 1/0/0
    (18 tests). Escenarios 1–5 cubiertos sin red.
  - **Recuentos reales por sección**: `20261009` → 205 entradas de corpus
    (I 5 / II.A 16 / II.B 31 / III 69 / V.B 84), V.A (32) descartada; `20240102` →
    64 entradas (II.A 6 / II.B 24 / III 18 / V.B 16), IV/V.A/V.C descartadas.
  - **Escenario 6 (opt-in, fuera del gate)**: `BOE_LIVE_TEST=1 ./gradlew
    :backend:test --tests '*BoeSumarioLiveTest'` → BUILD SUCCESSFUL (1 test, 0
    fallos); `curl -H 'Accept: application/json'
    …/boe/sumario/20261009` → HTTP 200 con las mismas entradas no vacías por
    sección del corpus (205) y V.A (32) fuera.
  - **Gate sin red ni BD**: `./gradlew build --no-daemon` → BUILD SUCCESSFUL (197
    tareas); `./gradlew test` → BUILD SUCCESSFUL (3 módulos); `env -u JAVA_HOME
    .harness/init.sh` → exit 0.
- Hallazgo de implementación (entorno): el `cacerts` del JBR de Android Studio
  **no** incluye la raíz **FNMT-RCM** que firma `*.boe.es`, así que el test opt-in
  en JVM falla con `SunCertPathBuilderException`; se ejecutó añadiendo esa raíz a
  un truststore temporal (`JAVA_TOOL_OPTIONS=-Djavax.net.ssl.trustStore=…`). `curl`
  valida por el llavero del sistema. No afecta al gate; documentado en
  `docs/desarrollo-local.md`.
- Ficheros creados/modificados (producto): `gradle/libs.versions.toml`,
  `backend/build.gradle.kts`,
  `backend/src/main/kotlin/.../ingesta/sumario/{SumarioWireDto,SingleOrArraySerializer,EntradaSumario,BoeSumarioClient,BoeSumarioHttpClient}.kt`,
  `backend/src/test/kotlin/.../ingesta/sumario/{BoeSumarioClientTest,SumarioParsingTest,BoeSumarioLiveTest}.kt`,
  `backend/src/test/resources/boe/{sumario-20261009,sumario-20240102}.json`,
  `docs/desarrollo-local.md`; harness:
  `.harness/{ARCHITECTURE.md,CONSTRAINTS.md,PROGRESS.md,feature_list.json}` y
  `.harness/docs/feature-ids.md`.
- Riesgo o duda sin resolver: commit/push/PR y CI los hace el orquestador; queda
  pendiente la **validación independiente**. El cliente no se cablea en el arranque
  (lo harán FT00007/FT00009). El fixture `20240102` no tiene Sección I (sí II.A/II.B/
  III/V.B); la I se cubre con `20261009`.
- Estado: **FT00006 `passing`** (implementada y autoverificada), pendiente de
  validación independiente.
- Siguiente mejor paso: validación independiente de FT00006 (`feature-validator`).

### Session 029

- Fecha: 2026-10-10
- Objetivo: cerrar `boe-sumario-cliente` (FT00006): validación independiente →
  aceptación → commit → push → PR.
- Completado:
  - **Claim**: rama `feat/ft00006-boe-sumario-cliente` creada desde `origin/main`
    y reclamada con el commit vacío `03b00b8 chore(FT00006): claim` (push
    inmediato). Sin PRs ni ramas de feature previas (nada reclamado).
  - **Planner** (`feature-spec`): spec `docs/specs/boe-sumario-cliente.md`
    (cliente del sumario, modelo interno, serializador objeto/array, fixtures
    reales, test opt-in; `parts: none`).
  - **Implementer** (`feature-implementer`): cliente del sumario en `:backend`
    (`ingesta/sumario/`), catálogo/deps Ktor client, dos fixtures reales, tests con
    `MockEngine` (sin red) + opt-in; docs durables. Estado `passing`.
  - **Validación independiente** (`feature-validator`): veredicto **`accept`**.
    Reejecutó `:backend:test --rerun-tasks` (18 tests, 0 fallos), gate sin red/BD
    (`build --no-daemon` 197 tareas, `test` 3 módulos, `init.sh` exit 0), confirmó
    fixtures **byte-idénticos** a la API en vivo, recuentos por sección
    reproducidos (205 y 64; IV/V.A fuera), API real (`curl`: 200/404/400) y
    escenario 6 opt-in verde con el truststore FNMT temporal; sin hallazgos de
    seguridad y alcance acotado verificado. Detalle en
    `docs/validations/boe-sumario-cliente.md`.
  - `.harness/feature_list.json`: FT00006 → **`accepted`** (evidencia con la
    validación independiente y la deuda Low). `docs/feature-ids.md`: `accepted`.
    Spec: cabecera `accepted`.
  - Commit de producto `835420b feat(FT00006): complete boe-sumario-cliente` en
    `feat/ft00006-boe-sumario-cliente`; **PR #6** hacia `main`
    (https://github.com/AviferDev/DatoPublico/pull/6). **CI en verde**: run
    `38039279992`, job 'Build and test' SUCCESS (4m59s) para el head `835420b`.
- Notas *Low* del validator (no bloquean; deuda para FT00007/FT00009):
  1. `BoeSumarioLiveTest` se reporta como «passed» (no «skipped») en el XML del
     gate (`return@runTest`); no abre sockets.
  2. `boeSumarioHttpClient()` sin `HttpTimeout` explícito.
  3. La envoltura `departamento.texto.item` no se modela (hoy solo IV/V.C).
  4. Campos faltantes → cadena vacía sin filtrar entradas incompletas.
  5. Cosmético: la evidencia de `20240102` omite V.C (también descartada).
- Ficheros (harness): `.harness/feature_list.json`, `.harness/docs/feature-ids.md`,
  `.harness/docs/specs/boe-sumario-cliente.md` (nuevo),
  `.harness/docs/validations/boe-sumario-cliente.md` (nuevo),
  `.harness/{ARCHITECTURE.md,CONSTRAINTS.md}`, `.harness/PROGRESS.md`.
- Estado: **FT00006 `accepted`**. Siguiente feature lista: `boe-parser-publicacion`
  (FT00007, depende de `boe-sumario-cliente`).
- Siguiente mejor paso: implementar `boe-parser-publicacion` (FT00007) con el flujo.

### Session 030

- Fecha: 2026-10-10
- Objetivo: **reparación de estilo de código** de `boe-sumario-cliente` (FT00006):
  dejar registrado como MUST durable el **retorno único** y refactorizar el código
  que lo incumplía (sin cambiar comportamiento ni firmas).
- Diagnóstico (decisión del owner): faltaba una regla durable y hay que aplicarla.
  Había *early returns* en `SingleOrArraySerializer.deserialize`,
  `BoeSeccionDto.entradas` (`BoeSumarioClient.kt`), `AppConfig.parsePort`
  (preexistente de FT00004) y un `return@runTest` en `BoeSumarioLiveTest`.
- Completado:
  - **MUST durable nuevo** en `CONSTRAINTS.md` §«Estilo de código»: cada
    función/método tiene **una sola salida** (`return` único); prohibido el *early
    return*; se resuelve con expresiones (`when`, Elvis, `if`/`else` como
    expresión, `buildList`…). Aplica **también a los tests**; los `return@…` se
    evitan con guardas `if`.
  - **Refactor sin cambios de comportamiento ni firmas**:
    - `SingleOrArraySerializer.deserialize`: `if (decoder !is JsonDecoder) return …`
      + `return when …` → una única `when (decoder)` (`is JsonDecoder -> …`,
      `else -> decodeSerializableValue(listSerializer)`).
    - `BoeSeccionDto.entradas` (`BoeSumarioClient.kt`): `?: return emptyList()` →
      `seccionBoeDe(codigo)?.let { … }.orEmpty()` (cuerpo de expresión).
    - `AppConfig.parsePort`: `if (raw == null) return DEFAULT_PORT` →
      `raw?.toIntOrNull()` + `require(raw == null || (port != null && port in
      MIN_PORT..MAX_PORT))` + `return port ?: DEFAULT_PORT`.
    - `BoeSumarioLiveTest`: `return@runTest` → guarda `if`/`else` que envuelve las
      aserciones; se mantiene el mensaje de aviso cuando `BOE_LIVE_TEST != 1`.
  - Nota de reparación en `docs/specs/boe-sumario-cliente.md` (sin reescribir el
    spec); cabecera del spec a `in_progress` (reabierta). `feature_list.json`
    (FT00006 → **`passing`**) y `docs/feature-ids.md` (FT00006 → `passing`).
- Verificación ejecutada (desde `..`, `JAVA_HOME` del JBR 21):
  - `./gradlew :backend:test --rerun-tasks` → BUILD SUCCESSFUL; XML sin
    failures/errors: SmokeTest 1/0/0, AppConfigTest 6/0/0, HealthTest 2/0/0,
    SumarioParsingTest 3/0/0, BoeSumarioClientTest 5/0/0, BoeSumarioLiveTest 1/0/0
    (**18 tests**, mismos recuentos).
  - Gate sin red ni BD: `./gradlew build --no-daemon` → BUILD SUCCESSFUL
    (**197 tareas**); `./gradlew test` → BUILD SUCCESSFUL (3 módulos);
    `env -u JAVA_HOME .harness/init.sh` → exit 0 («Gate OK…»).
  - Grep `return` en `backend/src`/`shared/src`/`composeApp/src` (`*.kt`,
    excluyendo KDoc `@return` y `return@`): solo quedan **5 salidas únicas**
    (`AppConfig.kt:44`, `SingleOrArraySerializer.kt:25`, `BoeSumarioHttpClient.kt:37`,
    `BoeSumarioClient.kt:34`, `SumarioParsingTest.kt:67`); sin *early returns*.
- Ficheros modificados (producto): `SingleOrArraySerializer.kt`,
  `BoeSumarioClient.kt`, `AppConfig.kt`, `BoeSumarioLiveTest.kt`; harness:
  `.harness/CONSTRAINTS.md`, `.harness/docs/specs/boe-sumario-cliente.md`,
  `.harness/feature_list.json`, `.harness/docs/feature-ids.md`, `.harness/PROGRESS.md`.
- Riesgo o duda sin resolver: commit/push/PR y CI los gestiona el orquestador;
  queda pendiente la **validación independiente** de la reparación. Es un refactor
  sin cambio de comportamiento (misma lógica observable y mismos recuentos).
- Estado: **FT00006 `passing`** (reparación aplicada y autoverificada), pendiente
  de validación independiente.
- Siguiente mejor paso: validación independiente de FT00006 tras el MUST de
  retorno único; después, `boe-parser-publicacion` (FT00007).

### Session 031

- Fecha: 2026-10-10
- Objetivo: cerrar la reparación de `boe-sumario-cliente` (FT00006): revalidación
  independiente → aceptación → commit de producto → CI, y **aclarar la convención
  de nombres** (decisión del owner) tras la duda sobre `EntradaSumario`.
- Completado:
  - **Revalidación independiente** (`feature-validator`) de la reparación:
    veredicto **`accept`**. Confirmó el MUST de retorno único en `CONSTRAINTS.md`,
    el refactor sin cambio de comportamiento (mismos casos/mensajes; equivalencia
    en `AppConfig.parsePort` con el mismo `IllegalArgumentException`), 5 salidas
    únicas y 0 `return@`, y reejecutó `:backend:test --rerun-tasks` (18 tests, 0
    fallos) y el gate (`build` 197 tareas, `test` 3 módulos, `init.sh` exit 0).
  - **Aclaración de la convención de nombres** (a raíz de «¿por qué
    `EntradaSumario` no tiene sufijo?»): sufijo `Dto` para **todo tipo
    `@Serializable`/de transporte** (contrato de `:shared` **y** DTOs de
    `:backend`, p. ej. `HealthDto`); `Entity`/`Row`/`Ui` en capas internas; y
    **sin sufijo** los **modelos de dominio/valor internos** (p. ej.
    `EntradaSumario`). Actualizado en `CONSTRAINTS.md` §«Nombres y contratos» y
    `ARCHITECTURE.md` §«Convenciones de nombres». `EntradaSumario` se mantiene sin
    sufijo; sin cambios de código.
  - Commit de producto `87af9dc refactor(FT00006): una sola salida por funcion` en
    `feat/ft00006-boe-sumario-cliente`; **PR #6**. **CI en verde**: run
    `38040596946`, job 'Build and test' SUCCESS (5m2s) para el head `87af9dc`.
  - `.harness/feature_list.json`: FT00006 → **`accepted`** (evidencia de la
    reparación y la revalidación). `docs/feature-ids.md`: `accepted`. Spec:
    cabecera `accepted`.
- Ficheros (harness): `.harness/{CONSTRAINTS.md,ARCHITECTURE.md,PROGRESS.md}`,
  `.harness/feature_list.json` y
  `.harness/docs/{feature-ids.md,specs/boe-sumario-cliente.md,validations/boe-sumario-cliente.md}`.
- Estado: **FT00006 `accepted`**. Siguiente feature lista: `boe-parser-publicacion`
  (FT00007).
- Siguiente mejor paso: implementar `boe-parser-publicacion` (FT00007) con el flujo.

### Session 032

- Fecha: 2026-10-10
- Objetivo: aplicar el **cambio de alcance** decidido por el owner (1.0.0 = **todo
  el BOE**, todas las secciones y todos los campos) y la **norma MUST de
  serialización** (`@SerialName` explícito en cada propiedad `@Serializable`) a las
  features reabiertas **FT00002** (`bootstrap-shared-dtos`, `:shared`) y **FT00006**
  (`boe-sumario-cliente`, `:backend`), sin ampliar más el alcance. Rama de producto
  `feat/ft00006-boe-sumario-cliente` (PR #6 abierto); **sin crear ramas ni commits**.
- Completado (`:shared`, FT00002):
  - `SeccionBoeDto`: ampliado a **8** valores — `I`, `II.A`, `II.B`, `III`, `IV`
    (`@SerialName("IV")`), `V.A` (`"V.A"`), `V.B`, `V.C` (`"V.C"`). Ninguna sección
    se excluye.
  - `@SerialName` explícito en **todas** las propiedades de `PublicacionDto` (10),
    `ResumenDto` (6), `PlazoDto` (2) y `ResumenDiarioDto` (2); `CategoriaDto`
    (11 valores) y `SeccionBoeDto` (8) ya anotaban sus valores de enum. JSON de
    wire invariante.
  - `CategoriaWireTest` actualizado a 8 secciones. `SerializationTest` sin cambios
    (round-trip intacto).
- Completado (`:backend`, FT00006):
  - `SumarioWireDto.kt`: `@SerialName` explícito en **las 36** propiedades de todos
    los DTOs de transporte. `BoeUrlPdfDto` amplía a los campos reales (`szBytes`,
    `szKBytes`, `pagina_inicial`, `pagina_final`, `texto`). Nuevo `BoeTextoDto` y
    campo `texto` en `BoeDepartamentoDto` para la envoltura `departamento.texto`.
  - `BoeSumarioClient.kt`: `seccionBoeDe` mapea los 8 códigos (`1→I`, `2A→II.A`,
    `2B→II.B`, `3→III`, `4→IV`, `5A→V.A`, `5B→V.B`, `5C→V.C`); **ya no se descarta
    ninguna sección**. El aplanado incorpora `departamento.texto.item[]`.
    `urlOficial = urlHtml ?: urlPdf?.texto.orEmpty()`. Estilo de retorno único
    mantenido.
  - `EntradaSumario`: nuevo campo `urlPdf: String?`. `Health.kt`: `HealthDto` con
    `@SerialName("status")`. `BoeSumarioHttpClient.kt` sin cambios funcionales.
  - Tests: `SumarioParsingTest` (4) con recuentos de **todas** las secciones
    (20261009 = 237; 20240102 = 143) y `urlPdf`; `BoeSumarioClientTest` (5) donde el
    test de filtrado ahora **incluye** V.A; `BoeSumarioLiveTest` usa 2024-01-09 (día
    con las 8 secciones) y espera el conjunto completo. Fixtures reales existentes,
    sin crear nuevos.
- **Cómo se resolvió `departamento.texto.item`**: las Secciones IV (Justicia) y V.C
  (anuncios particulares) cuelgan sus entradas de `departamento.texto.item[]` en
  lugar de `departamento.item` (verificado en `sumario-20240102.json`: la Sección IV
  es `texto.item[24]`, la V.C es `texto.item[4]`). Se modeló `BoeTextoDto`
  (`texto: BoeTextoDto? = null`, con `item` tolerante objeto/array vía
  `ItemListSerializer`) y `BoeDepartamentoDto.entradas` añade `texto?.item.orEmpty()`
  al `buildList`, con organismo = nombre del departamento y epígrafe = null.
- Verificación ejecutada (desde `..`, `JAVA_HOME` del JBR 21):
  - `./gradlew :shared:jvmTest --rerun-tasks` → BUILD SUCCESSFUL; XML: SmokeTest
    1/0/0, CategoriaWireTest 3/0/0, SerializationTest 7/0/0 (**11 tests**).
  - `./gradlew :backend:test --rerun-tasks` → BUILD SUCCESSFUL; XML sin
    failures/errors: SmokeTest 1/0/0, AppConfigTest 6/0/0, HealthTest 2/0/0,
    SumarioParsingTest 4/0/0, BoeSumarioClientTest 5/0/0, BoeSumarioLiveTest 1/0/0
    (**19 tests**).
  - **Recuentos por sección** (con todas las secciones): `20261009` = 237
    (I 5/II.A 16/II.B 31/III 69/V.A 32/V.B 84); `20240102` = 143
    (II.A 6/II.B 24/III 18/IV 24/V.A 51/V.B 16/V.C 4).
  - **Grep/script de `@SerialName`**: 0 propiedades sin anotar y 0 valores de enum
    sin anotar en `:shared` y `:backend` (SumarioWireDto 36/36, Health 1/1,
    PublicacionDto 10/10, ResumenDto 6/6, PlazoDto 2/2, ResumenDiarioDto 2/2;
    CategoriaDto 11/11 y SeccionBoeDto 8/8).
  - Gate sin red ni BD: `./gradlew build --no-daemon` → BUILD SUCCESSFUL (197
    tareas); `./gradlew test` → BUILD SUCCESSFUL (3 módulos);
    `env -u JAVA_HOME .harness/init.sh` → exit 0.
  - Llamada real (opt-in): `curl -H 'Accept: application/json'
    .../boe/sumario/20240102` → HTTP 200; con la lógica nueva se incluyen
    II.A 6/II.B 24/III 18/**IV 24**/**V.A 51**/V.B 16/**V.C 4** = 143. El test
    opt-in `BOE_LIVE_TEST=1` sobre 2024-01-09 falla solo por la raíz **FNMT-RCM**
    ausente en el `cacerts` del JBR (limitación de entorno ya documentada), no por
    parcheo; fuera del gate.
- Documentación durable: nota de reparación en
  `docs/specs/{bootstrap-shared-dtos,boe-sumario-cliente}.md`;
  `.harness/PROGRESS.md`, `.harness/feature_list.json` (FT00002/FT00006 →
  `passing`), `.harness/docs/feature-ids.md` (`passing`); producto
  `docs/desarrollo-local.md` y `ROADMAP.md` (alcance completo). `CONSTRAINTS.md`
  ya recogía ambos MUST; `ARCHITECTURE.md` ya los describe.
- Ficheros de producto: `shared/src/commonMain/.../model/{SeccionBoeDto,PublicacionDto,
  ResumenDto,PlazoDto,ResumenDiarioDto}.kt`, `shared/src/commonTest/.../CategoriaWireTest.kt`,
  `backend/src/main/.../ingesta/sumario/{SumarioWireDto,EntradaSumario,BoeSumarioClient}.kt`,
  `backend/src/main/.../plugins/Health.kt`,
  `backend/src/test/.../ingesta/sumario/{SumarioParsingTest,BoeSumarioClientTest,BoeSumarioLiveTest}.kt`,
  `docs/desarrollo-local.md`, `ROADMAP.md`.
- Estado: **FT00002 `passing`** y **FT00006 `passing`** (implementadas y
  autoverificadas), pendientes de **validación independiente**. Sin commit (lo
  gestiona el orquestador).
- Siguiente mejor paso: validación independiente (`feature-validator`) de FT00002 y
  FT00006 tras el cambio de alcance y la norma de serialización.

### Session 033

- Fecha: 2026-10-10
- Objetivo: portar del harness de Vuelantis las diferencias seleccionadas por el
  dueño (**Fase 1**: docs de decisión/flujo, reglas MUST, skills SDD, agentes;
  **Fase 2**: gate de calidad detekt+CPD, `init.sh` con flags, `opencode.json`).
- Decisiones: se adopta casi todo lo seleccionado salvo `fastlane`/workflows de
  release, `deploy`/`docker`/compose y docs de release/design (Fases 3–4), diferidos
  hasta que exista app/backend desplegable. **No** se adoptan los campos extra de
  `feature_list.json` (`phase`, `out_of_mvp`, `parts`, `supersedes`).
- Fase 1 (harness privado):
  - `docs/adr/` (README de convención + índice + ADR `0001` de los dos repositorios).
  - `docs/pr/` (convención de capturas antes/después).
  - `docs/sdd/` + skills `sdd-propose`/`sdd-apply`/`sdd-archive` adaptadas a
    `docs/sdd/<feature>/` (spec/design/tasks) y `docs/sdd/archive/`.
  - `docs/git-workflow.md`: + límite de 30 ficheros, mantener PR actualizado,
    capturas de interfaz y "Evitar problemas".
  - `AGENTS.md`: sección "Verificación y comandos"; reglas de trabajo y definición
    de terminado con las MUST nuevas; referencias a `docs/adr/` y `docs/pr/`.
  - `CONSTRAINTS.md`: KDoc, prohibir `else if`, 40 líneas/función, reutilización,
    crear la capa que falte, `@Preview`, nunca provocar crash, i18n, Material Icons,
    colores del tema, gate detekt+CPD y gate SDK-free; sección "Decisiones y flujo".
  - `ARCHITECTURE.md`: sección "Build y gate".
  - `.opencode/agents/*`: frontmatter al formato `permission:` (mapa) de Vuelantis;
    el implementer/validator permiten las skills de arquitectura.
  - `README.md` (harness): contenido ampliado.
- Fase 2 (producto):
  - `gradle/libs.versions.toml`: detekt 1.23.8 y CPD 3.5.
  - `build.gradle.kts`: plugins, `cpd{}` (kotlin, PMD 7.7.0, 100 tokens),
    `:cpdCheck` global y detekt por módulo (`buildUponDefaultConfig`, baseline);
    detekt depende de `:cpdCheck`; task `test` guardada por `skipClient`.
  - `config/detekt/detekt.yml` + `config/detekt/backend-baseline.xml` (deuda:
    `MatchingDeclarationName:Health.kt$HealthDto`).
  - `settings.gradle.kts`: `:composeApp` condicional con `-PskipClient`.
  - `opencode.json` en la raíz.
- Fase 2 (harness): `.harness/init.sh` con `--with-client`/`--with-ios`/`--with-all`,
  detección de Android SDK y Xcode, y gate de calidad; SDK-free por defecto.
- Verificación ejecutada (JAVA_HOME del JBR 21, desde `..`):
  - `./gradlew detekt` → BUILD SUCCESSFUL (backend/shared/composeApp + `:cpdCheck`).
  - `./gradlew build -PskipClient` + `./gradlew detekt -PskipClient` → verdes;
    `.harness/init.sh` (default) → exit 0.
  - `./gradlew build --no-daemon` (con `:composeApp`) → BUILD SUCCESSFUL (201 tareas).
  - `./gradlew test` y `./gradlew test -PskipClient` → verdes.
- Ficheros: `.harness/{AGENTS.md,CONSTRAINTS.md,ARCHITECTURE.md,README.md,init.sh,PROGRESS.md}`,
  `.harness/docs/{adr/*,pr/README.md,sdd/README.md,git-workflow.md}`,
  `.harness/.agents/skills/sdd-*/SKILL.md`, `.harness/.opencode/agents/*.md`;
  producto `gradle/libs.versions.toml`, `build.gradle.kts`, `settings.gradle.kts`,
  `config/detekt/{detekt.yml,backend-baseline.xml}`, `opencode.json`.
- Riesgo/duda: el árbol de producto ya tenía **WIP de FT00006** (`feat/ft00006-...`)
  sin commitear; por eso **no** se hizo commit/rama/PR (lo gestiona el orquestador).
  El baseline de `:backend` registra la deuda de `Health.kt` (renombrar a
  `HealthDto.kt` cuando toque). El default del gate pasa a SDK-free (`-PskipClient`);
  la CI sigue con `./gradlew build` (incluye `:composeApp`).
- Siguiente mejor paso: revisar/commitear Fase 1 (harness `main`) y Fase 2 (rama de
  producto + PR); validar FT00002/FT00006 pendientes.

### Session 034

- Fecha: 2026-10-10
- Objetivo: aplicar el **cambio de alcance 1.0.0 = todo el BOE** (todas las
  secciones y todos los campos) y la nueva norma de **`@SerialName` explícito** en
  los DTOs; reabrir y cerrar **FT00002** y **FT00006**.
- Decisiones del owner:
  - El corpus de la 1.0.0 es **todo el sumario del BOE** (secciones I, II.A, II.B,
    III, IV, V.A, V.B y V.C); **ninguna** sección ni campo se excluye. El principio
    «sin datos personales» aplica a **quien usa la app**, no al BOE (corrige
    `CONTEXT.md` §IV/§V.A, `build-brief.md`, `CONSTRAINTS.md` y `roadmap.md`).
  - **MUST**: en todo `@Serializable`, **cada propiedad lleva `@SerialName`**
    explícito aunque el nombre coincida (`CONSTRAINTS.md` §«Serialización»,
    `ARCHITECTURE.md`).
- Completado (producto, rama `feat/ft00006-boe-sumario-cliente`, PR #6):
  - `:shared`: `SeccionBoeDto` a **8** valores; `@SerialName` explícito en todas
    las propiedades de `PublicacionDto`/`ResumenDto`/`PlazoDto`/`ResumenDiarioDto`.
    Commit `5fbedd2` (→ `main` `a7b3749`).
  - `:backend`: `seccionBoeDe` mapea los 8 códigos (sin descartes); nueva envoltura
    `BoeTextoDto` para `departamento.texto.item[]` de IV/V.C; `EntradaSumario.urlPdf`
    y `urlOficial = urlHtml ?: urlPdf?.texto`; `BoeUrlPdfDto` completo;
    `@SerialName` en `SumarioWireDto`/`HealthDto`. Commit `bb0b185` (→ `main`
    `a347e72`).
  - Tests con fixtures reales: 20261009 → **237** (V.A incluida); 20240102 →
    **143** (II.A/II.B/III/**IV/V.A**/V.B/**V.C**); nuevo test de **unión de las 8
    secciones**. `:shared:jvmTest` 11 y `:backend:test` **20** tests, 0 fallos.
  - Docs de producto: `ROADMAP.md`, `docs/desarrollo-local.md`.
- Validación: `revise` (integridad de árbol por la **Session 033** concurrente) →
  reparado (L1 unión 8 secciones, L2 cuerpos de spec, B1 evidencia) → **`accept`**.
- Cierre: **PR #6 fusionado** en `main` (merge por rebase). CI en verde run
  `38043750790` (head `bb0b185`). `feature_list.json` FT00002 y FT00006 →
  **`accepted`**; `docs/feature-ids.md` igual; `docs/validations/boe-sumario-cliente.md`
  ampliado.
- Nota de coordinación: el workstream de tooling **Session 033** (detekt/CPD,
  `-PskipClient`, `opencode.json`) es **ajeno**; sus cambios de producto siguen sin
  commitear (rama propia).
- Estado: **FT00002 y FT00006 `accepted` y fusionadas**. Siguiente feature lista:
  `boe-parser-publicacion` (FT00007), que debe cubrir las **8 secciones** y **todos
  los campos** (incluido `urlPdf` y la envoltura `texto`).
- Siguiente mejor paso: implementar `boe-parser-publicacion` (FT00007) con el flujo.

### Session 035

- Fecha: 2026-10-10
- Objetivo: implementar `boe-parser-publicacion` (FT00007) en el repo público,
  rama `feat/ft00007-boe-parser-publicacion`: parser del **texto XML** del BOE que
  convierte cada `EntradaSumario` (FT00006) en una `Publicacion` con texto y
  metadatos.
- Completado (producto, `backend/src/main/kotlin/.../ingesta/publicacion/`):
  - Modelo interno `Publicacion` (id, título, fecha ISO, organismo, sección,
    epígrafe, texto, urlOficial, urlXml, urlPdf, rango, `categoria = null`) y
    `DocumentoBoe` + `MetadatosBoe` (rango, departamento, fechaDisposicion,
    numeroOficial, urlPdf, origenLegislativo).
  - `BoeXmlParser` (parser XML del JDK, **seguro**: `FEATURE_SECURE_PROCESSING`,
    `disallow-doctype-decl`, `ACCESS_EXTERNAL_DTD`/`SCHEMA` vacíos); texto por
    bloques (`p`/`li`/`dt`/`dd`) con saltos de párrafo y normalización de
    `\u00a0` y espacios; `<texto>` ausente/vacío → `null`; XML malformado →
    `BoeTextoException`. Selecciona `<metadatos>`/`<texto>` como **hijos directos**
    de `<documento>` (evita el `<texto>` anidado en `<analisis>`).
  - `BoeTextoClient` (interfaz) + `BoeTextoException`; `BoeTextoHttpClient` (Ktor
    con `HttpClient` inyectado, `GET <urlXml>` absoluto con `Accept:
    application/xml`, cuerpo UTF-8, `404` → `null`, resto → excepción tipada) +
    factory CIO `boeTextoHttpClient()` (`expectSuccess = false`, sin base URL).
  - `PublicacionParser` (puro; prioriza organismo/PDF del sumario, completa desde
    el XML) y `BoePublicacionParser` (interfaz) + `BoePublicacionHttpParser`
    (orquesta descarga + parseo; sin `urlXml` no hace petición).
  - Sin wiring: `Application.kt`, Flyway, `:shared`, `:composeApp` y CI intactos;
    sin cambios en `build.gradle.kts`/`libs.versions.toml`.
- Fixtures (capturados con `curl`, HTTP 200) en `backend/src/test/resources/boe/`:
  `texto-{I-2026-20979 (44.371 car./153 párrafos), IIA-2024-87, IIB-2024-93,
  III-2024-117, IV-2024-1, VA-2024-25, VB-2024-76, VC-2024-92}.xml` reales, más
  `texto-sin-texto.xml` **sintético** (marcado como tal, `<texto/>` → `null`).
- Tests (gate, sin red): `BoeXmlParserTest` (8: por sección, extensa, tablas/dl,
  normalización, sin texto, sin nodo texto, malformado, XXE/DTD),
  `PublicacionParserTest` (4), `BoeTextoClientTest` (6, `MockEngine`), y
  `BoePublicacionParserTest` (4; escenario 1 con `EntradaSumario` del sumario real
  y `MockEngine` que sirve los fixtures, las 8 secciones, sin `urlXml`, `404`).
- Verificación ejecutada (desde `..`, `JAVA_HOME` del JBR 21):
  - `./gradlew :backend:test --rerun-tasks` → BUILD SUCCESSFUL; **43** tests en
    `:backend`, 0 fallos (23 nuevos en `ingesta/publicacion`).
  - `./gradlew build --no-daemon -PskipClient` → BUILD SUCCESSFUL (23 tareas);
    `./gradlew test` → 3 módulos verdes; `./gradlew detekt -PskipClient` (Detekt +
    `:cpdCheck`) → sin hallazgos; `env -u JAVA_HOME .harness/init.sh` → exit 0.
  - Opt-in `BOE_LIVE_TEST=1 ./gradlew :backend:test --tests '*BoePublicacionLiveTest'`
    → fuera del gate; en el JBR de macOS falla con `SunCertPathBuilderException`
    (truststore sin la raíz **FNMT-RCM**, limitación ya documentada en FT00006).
    Los fixtures se capturaron con `curl` (llavero del sistema) con HTTP 200.
- Doc durable: `ARCHITECTURE.md` (`ingesta/publicacion/`, frontera Backend→BOE
  texto XML), `CONSTRAINTS.md` (nueva sección «Fuentes externas (ingesta)»: MUST de
  parseo XML seguro + red opt-in), `docs/desarrollo-local.md` (endpoint XML,
  captura de fixtures, test opt-in) y **ADR `docs/adr/0002-fuente-texto-boe-xml.md`**
  (+ índice). `docs/specs/boe-parser-publicacion.md`: `status: passing` + nota.
- Estado: **FT00007 `passing`** (autoverificado, listo para validación
  independiente). `categoria = null` (FT00012). Deuda: `Publicacion` expone `rango`
  del XML y deja el resto de metadatos en `DocumentoBoe`; el parser DOM mantiene el
  XML en memoria (aceptable por documento; vigilar una ley muy extensa).
- Siguiente mejor paso: validación independiente de FT00007 (`feature-validator`);
  después, `publicacion-persistencia` (FT00008).

### Session 036

- Fecha: 2026-10-10
- Objetivo: implementar `publicacion-persistencia` (FT00008) en el repo público,
  rama `feat/ft00008-publicacion-persistencia`: capa de persistencia sobre
  PostgreSQL (migración + repositorios JDBC) con sus tests.
- Completado (producto):
  - Migración `backend/src/main/resources/db/migration/V2__persistencia_publicaciones.sql`
    (V1 intacta) con `publicacion` (categoria y `plazo_*` nullable), `fragmento`
    (`UNIQUE (publicacion_id, orden)`), `resumen` (`publicacion_id UNIQUE`,
    `cifras_clave text[]`) y `cola_revision`; FK `ON DELETE CASCADE` e índices.
    **Sin** embedding ni HNSW (FT00016).
  - `infra/DatabaseConfig.kt` (data class pura; deriva `jdbc:postgresql://host:port/db`
    de `POSTGRES_*`, defaults no sensibles, fail-fast sin `POSTGRES_PASSWORD`,
    `toString` redacta la contraseña) e `infra/Database.kt` (factory de
    `HikariDataSource`, pool ≤5).
  - Paquete `persistence/`: `PublicationRepository` (+`PublicationEntity`,
    *upsert* `ON CONFLICT (id) DO UPDATE`), `FragmentRepository`,
    `SummaryRepository`, `ReviewQueueRepository` y helpers JDBC compartidos
    (`Jdbc.kt`). **Sin ORM** y **sin wiring** en `Application.kt`.
  - `Publicacion` gana `plazo: PlazoDto? = null` (aditivo). Driver PostgreSQL y
    HikariCP al `implementation` de `:backend` (`libs.versions.toml` +
    `backend/build.gradle.kts`).
- Tests (gate, sin BD): `DatabaseConfigTest` (8: derivación, defaults, overrides,
  fail-fast y redacción), `PublicationPersistenceTest` (5: mapeo ida/vuelta,
  nombres de enum, plazo, nulos) y `MigrationSqlTest` (4: cuatro tablas, FK en
  cascada, no-embedding). Opt-in real: `PublicationPersistenceLiveTest`
  (guardar/recuperar con categoría/sección/epígrafe/plazo, *upsert* sin duplicar
  con `actualizado_en` avanzado, nulos y FK CASCADE; lee `POSTGRES_*` del entorno
  o de `.env`).
- Verificación ejecutada (desde `..`, `JAVA_HOME` del JBR 21):
  - Gate sin BD (Docker parado): `./gradlew :backend:test --rerun-tasks -PskipClient`
    → **61 tests, 0 fallos**; `./gradlew build --no-daemon -PskipClient` →
    BUILD SUCCESSFUL; `./gradlew test --no-daemon` → 3 módulos; `./gradlew detekt
    -PskipClient --rerun-tasks` (Detekt + `:cpdCheck`) → sin hallazgos;
    `.harness/init.sh` → exit 0.
  - BD real: `docker compose up -d` (`datopublico-postgres` healthy);
    `:backend:flywayMigrate` → BUILD SUCCESSFUL; `:backend:flywayInfo` → `V1`+`V2`
    en **Success**; `\dt`/`information_schema.tables` con las cuatro tablas; FK
    `delete_rule = CASCADE`. Test opt-in `DB_LIVE_TEST=1 … '*PublicationPersistenceLiveTest'`
    → verde (1 test). Entorno limpiado (`docker compose down -v`, `.env` borrado).
- Doc durable: `ARCHITECTURE.md` (frontera **Backend → PostgreSQL**, `persistence/`
  e `infra/`), `CONSTRAINTS.md` (§«Persistencia y base de datos»), **ADR
  `docs/adr/0003-jdbc-hikari-sin-orm.md`** (+ índice), `docs/desarrollo-local.md`
  y skill `ktor-backend-architecture` (§Estado actual).
- Estado: **FT00008 `accepted`** (validación independiente `feature-validator`,
  2026-10-10, veredicto **`accept`**; informe en
  `docs/validations/publicacion-persistencia.md`). Sin hallazgos
  Critical/High/Medium; deuda Low (índice `cola_revision(resumen_id)` → FT00023;
  `.first()` sobre `RETURNING id`). Alcance amplio (4 tablas) pero repositorios
  secundarios mínimos.
- Cierre: commit de producto `015d882` en `feat/ft00008-publicacion-persistencia`
  (claim `35e09e0`); **PR #9** (https://github.com/AviferDev/DatoPublico/pull/9);
  CI en verde run `38048554781`, job 'Build and test' SUCCESS. Harness commiteado
  en `main` (`733b9a6 docs(FT00008): complete publicacion-persistencia`).
  Pendiente de revisión/fusión explícita del dueño.
- Limpieza post-aceptación (2026-10-10, petición del dueño, sin cambio de
  comportamiento): identificadores nuevos en **inglés** (clases, variables,
  funciones, params y ficheros; p. ej. `DatabaseConfig`/`Database`,
  `PublicationRepository`, `*Entity` con propiedades en inglés, paquete
  `persistence/`, métodos `save`/`findById`/`listByDate`), conservando los tipos
  de dominio existentes (`Publicacion`, `PlazoDto`, `SeccionBoeDto`,
  `CategoriaDto`); y se eliminaron las referencias al hardware («N100 / 8 GB»,
  «carga baja») del código y docs de la feature. Commit `d9f245c`; CI en verde
  run `38049632428`. Gate reejecutado en verde (61 tests/0 fallos; `build`,
  `detekt`+`:cpdCheck`, `init.sh` exit 0) y test opt-in `DB_LIVE_TEST=1` contra
  PostgreSQL real.
- Siguiente mejor paso: `ingesta-job-diario` (FT00009).
