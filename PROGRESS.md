# Progress Log

## Current Verified State

- Harness (privado): `.harness/`
- Repositorio de producto (código): `..` (repo público `DatoPublico`)
- Camino de arranque estándar: `./init.sh` (desde `.harness/`)
- Camino de verificación estándar: `./gradlew build` y `./gradlew test` desde la
  raíz del repo público (`..`) — **bootstrapped** (Gradle 8.10.2 + JDK 21).
- Siguiente feature lista: `bootstrap-ktor-healthcheck` (FT00004, depende de
  FT00001). FT00003 (`bootstrap-postgres-pgvector`) queda **`accepted`** (ver
  Session 018). FT00002 (`bootstrap-shared-dtos`) **`accepted`** y **fusionada**
  (PR #2, merge `ca781f3`); habilita `contrato-resumen-ciudadano` (FT00019) y
  `boe-sumario-cliente` (FT00006).
- Bloqueo actual: ninguno para el bootstrap. Pendiente de producto: **nombre y
  marca** (bloquea la fase de producción, no el bootstrap).
- Convención de nombres (2026-10-10): **todos los tipos serializables del
  contrato** en `:shared` (data classes **y enums de wire**) llevan sufijo
  **`Dto`**; la config de serialización (`DatoPublicoJson`) sin `Dto`; sin
  prefijos. En `ARCHITECTURE.md` §«Convenciones de nombres» y **MUST** en
  `CONSTRAINTS.md`.
- Última verificación: 2026-10-10. **FT00002 `bootstrap-shared-dtos`:
  `accepted`** (validación independiente `accept` de los renombrados de
  contenedores y de enums); PR #2 con CI en verde (run 37998033440, head
  872fb2b) y **fusionado** (`ca781f3`). Gate verde desde `..` con JDK 21 (JBR):
  `./gradlew :shared:jvmTest`, `./gradlew test` (3 módulos) y `./gradlew build`.
  FT00001 `bootstrap-monorepo-gradle`: **`accepted`** (PR #1 fusionado, merge
  `912c328`). **FT00003 `bootstrap-postgres-pgvector`: `accepted`** (Session 018):
  Docker Compose con pgvector + migración `V1` de Flyway verificadas de verdad,
  `./gradlew build` verde sin base de datos (CI) y CI en verde (run 37999962253,
  head 9231452); PR #3.
- PoC exploratoria (no feature), **temporal y ya eliminada**: `poc/boe-rag`
  validó el RAG de punta a punta (embeddings locales ONNX + pgvector + generación
  con cita). Sus lecciones quedan en la skill `rag-datapublico`. Ver Session 002.
- Decisión de IA (2026-10-09): **embeddings locales `multilingual-e5-small` int8
  (ONNX/CPU)** por defecto (`-base` como alternativa tras la interfaz) +
  **OpenCode** (`deepseek-v4.1-flash`) para resumen y chat. OpenCode no ofrece
  endpoint de embeddings. El **chat RAG entra en el alcance de la 1.0.0**.
- Alcance 1.0.0 (2026-10-09): BOE **Secciones I, II.A, II.B, III y V.B**, con
  **categorías** curadas (11 valores) + sección/epígrafe del BOE como metadato;
  feed diario con **destacados**, búsqueda con filtros y **chat de verificación**
  contra el BOE. Ingesta **9:30 + segunda pasada**; backfill del **último año**.
  Fuera: Sección IV (Justicia, datos personales), V.A (licitaciones), PLACSP y
  fact-checking externo (1.x).

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
