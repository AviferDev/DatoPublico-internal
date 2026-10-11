# Feature Implementation Spec: Generación del chat RAG con OpenCode

## Source Feature

- `id`: chat-generacion
- `ft_id`: FT00025 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ~12 ficheros de producto, muy por debajo del límite de 30)
- `area`: simplificacion-ia
- `depends_on`: recuperacion-hibrida (FT00017, `accepted`) + generacion-resumen-go
  (FT00020, `accepted`). **Reutiliza además `guardrails-anti-alucinacion`
  (FT00022, `accepted`)**: el grounding léxico parte de `SummaryTextNormalizer` y
  de `SummaryGroundingChecker.MIN_CLAIM_SUPPORT` (ver *Risks*); el orquestador
  puede añadir `guardrails-anti-alucinacion` a `depends_on` (el planner **no**
  edita `feature_list.json`).
- `status`: not_started (al planificar)
- `source`: `feature_list.json`
- `claim`: rama `feat/ft00025-chat-generacion` ya reclamada en `origin`
  (commit `63daeb1 chore(FT00025): claim`); sin PR abierto hacia `main`.

> **Encaje con FT00017/FT00020/FT00022.** FT00025 **no** cambia la recuperación,
> el proveedor de texto ni los guardrails: **reutiliza** las piezas ya
> implementadas y sin wiring — `rag/retrieval/HybridSearch` + `SearchFilter`
> (FT00017), `rag/generation/TextGenerationProvider` + `GenerationRequest`/
> `GenerationResponse`/`TextGenerationException` + `OpenCodeConfig`/
> `OpenCodeTextGenerationProvider` (FT00020) y
> `rag/guardrails/SummaryTextNormalizer` (FT00022). Es la tarea `0.4-T07`, la
> contraparte de chat del resumen ciudadano (FT00020).

## Goal

Añadir en `:backend`, como **librería sin wiring**, la **generación del chat RAG**
(tarea `0.4-T07`): dada una **pregunta** o una **afirmación** en lenguaje natural,
recuperar los fragmentos relevantes con `HybridSearch` (FT00017), construir el
prompt con ese contexto, invocar el **proveedor de texto intercambiable** ya
existente (FT00020), parsear una salida estructurada (**estado + respuesta +
citas**) y devolver un **resultado tipado** con los tres estados del dominio
(`respondida` / `refutada` / `sin_fundamento`), **con citas a la fuente oficial**.

La respuesta se fundamenta **solo** en los fragmentos recuperados: un guardrail de
**grounding léxico** (que reutiliza el normalizador de FT00022) degrada a
`sin_fundamento` cualquier respuesta cuyas afirmaciones no estén sustentadas por el
contexto, y una respuesta `respondida`/`refutada` **exige** al menos una cita
resoluble. La **fuente oficial no la produce el modelo**: el modelo cita
**índices** de fragmento y el servicio **inyecta** la URL oficial de la publicación
de origen de forma determinista (mismo principio que FT00020 con
`Publicacion.urlOficial`). El proveedor se sustituye por un **doble** en los tests
del gate sin tocar el servicio.

## Non-Goals

- **Endpoints Ktor, API pública y rate limiting** del chat → FT00031 (`api-chat`).
  Aquí solo se construye la **librería**; **sin wiring** en
  `Application.kt`/job/backfill.
- **DTO de wire del chat en `:shared`** y contratos OpenAPI → FT00031/FT00029.
- **UI de chat** y textos visibles → FT00037 (`ui-chat`); este spec **no** produce
  textos de UI (solo un mensaje de dominio interno).
- **Persistencia del historial** del chat en el servidor → fuera de alcance
  (sin cuentas ni historial servidor; `CONSTRAINTS.md` §«Producto y datos»).
- **Aviso legal / «no asesoramiento jurídico»** visible → FT00044/FT00037.
- **Cacheo** de respuestas de chat y control de coste por consulta → no en esta
  feature (el control de cuota/rate limiting es FT00030/FT00031).
- **Evaluación del chat** con golden set (respuestas, refutaciones, sin
  fundamento) → tarea posterior; no se toca FT00024.
- **Reranking** o fusión léxica: se reutiliza `HybridSearch`/`SearchFilter` tal
  cual.
- Cambios en `TextGenerationProvider`/`OpenCodeTextGenerationProvider`/
  `OpenCodeConfig` (FT00020), `SummaryTextNormalizer`/`SummaryGroundingChecker`
  (FT00022), `ResumenDto`/`CitizenSummaryValidator` (FT00019), `rag/summary/`,
  `rag/review/` ni migraciones: se **reutilizan** sin modificar.

## Job Story

When una persona pregunta algo sobre el BOE o pega una afirmación para
verificarla,
I want recuperar los fragmentos relevantes, responder **solo** con ellos y
**citar la fuente oficial**, refutando la afirmación si el corpus la contradice o
declarando `sin_fundamento` si el corpus no permite confirmarla,
so I can no inventar nunca información y ofrecer siempre trazabilidad a la fuente
oficial.

## Users And Permissions

- **Backend (chat, FT00025):** consumidor interno; sin cuentas, sin datos
  personales, sin autenticación de usuario.
- **FT00031 (`api-chat`):** consumirá el servicio y lo cableará (endpoint, rate
  limiting, errores); **no** se implementa aquí.
- **Operador/desarrollador:** ejecuta la prueba real **opt-in** con su clave de
  OpenCode; la clave vive **solo** en el servidor (variable de entorno).
- **Usuario final (ciudadanía):** anónimo; verá la respuesta y sus citas en la UI
  de chat (FT00037).

## Acceptance Scenarios

### Scenario 1: una pregunta sobre el corpus responde con cita a la fuente

Given una consulta con fragmentos recuperados que sustentan la respuesta y un
doble de `TextGenerationProvider` que devuelve `estado = "respondida"`, una
respuesta sustentada y `citas = [0]`
When se llama `RagChatService.answer(query)`
Then devuelve `ChatResult.Answered` con la respuesta y **≥1** `ChatCitation` cuya
`officialUrl` es la `urlOficial` de la publicación del fragmento citado.

### Scenario 2: una afirmación falsa se refuta con citas

Given una afirmación que el contexto contradice y una salida del modelo con
`estado = "refutada"`, respuesta sustentada y `citas` no vacías
When se genera
Then devuelve `ChatResult.Refuted` con **≥1** cita a la fuente oficial.

### Scenario 3: una pregunta sin base se declara sin fundamento

Given un corpus que no permite confirmar ni refutar y una salida del modelo con
`estado = "sin_fundamento"`
When se genera
Then devuelve `ChatResult.Unfounded` con la respuesta del modelo y **sin** citas
(no se inventa una respuesta).

### Scenario 4: sin contexto recuperado no se invoca al proveedor

Given una consulta para la que `HybridSearch` devuelve **cero** fragmentos
When se llama `answer(query)`
Then devuelve `ChatResult.Unfounded` (mensaje de dominio) y el proveedor **no**
se invoca (`calls == 0`).

### Scenario 5: el proveedor se sustituye por un doble sin tocar el servicio

Given un doble de `TextGenerationProvider` que registra la petición recibida
When se genera con el `RagChatService` real
Then el doble recibe un `GenerationRequest` con el prompt construido (la consulta
y el contexto numerado) y el servicio **no** conoce OpenCode, Ktor ni HTTP.

### Scenario 6: una respuesta no sustentada por el contexto se degrada a sin fundamento

Given una salida del modelo con `estado = "respondida"` cuya respuesta usa
términos de contenido que **no** aparecen en el contexto recuperado
When se genera
Then el guardrail degrada el resultado a `ChatResult.Unfounded` (no se publica
una afirmación fuera del corpus).

### Scenario 7: una respuesta `respondida`/`refutada` sin cita resoluble no se publica

Given una salida `respondida` con `citas` vacías, con un índice fuera de rango o
cuya publicación no se puede resolver a una fuente oficial
When se genera
Then no se devuelve una respuesta citada: `citas` vacías → `ChatResult.Unfounded`;
índice fuera de rango o estado desconocido → `ChatGenerationException` tipada.

### Scenario 8: el gate sigue sin red, BD, modelo ni OpenCode

Given el runner de CI sin PostgreSQL, sin Docker, sin el modelo E5 y sin
`OPENCODE_API_KEY`
When se ejecuta `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew
detekt` o `.harness/init.sh`
Then todo está en verde; la prueba real se omite sin abrir sockets.

### Scenario 9: extremo a extremo real contra OpenCode (opt-in)

Given `OPENCODE_LIVE_TEST=1` y `OPENCODE_API_KEY` definidos, con fragmentos de
prueba **en memoria** (sin PostgreSQL ni ONNX)
When se ejecuta `RagChatServiceLiveTest`
Then se genera una respuesta (pregunta respondida y/o afirmación refutada) con
cita a la fuente; sin la clave, el test falla en claro (fail-fast).

## Repository Research

### Files Inspected

- `shared/src/commonMain/kotlin/…/model/ResumenDto.kt` — patrón de contrato
  (`@SerialName` explícito); **no** se toca. No existe aún ningún DTO de chat en
  `:shared` (lo define FT00031).
- `backend/src/main/kotlin/…/rag/generation/TextGenerationProvider.kt` —
  **verificado**: interfaz `suspend` `TextGenerationProvider`, valores internos
  `GenerationRequest(systemPrompt, userPrompt)`/`GenerationResponse(text, usage)`
  y `TextGenerationException`; su KDoc ya anticipa que FT00025 es su consumidor de
  chat. Se **reutiliza** sin cambios.
- `backend/src/main/kotlin/…/rag/generation/OpenCodeTextGenerationProvider.kt` y
  `OpenCodeConfig.kt` — **verificado**: impl OpenCode + factory
  `openCodeHttpClient()`, DTOs de wire con sufijo `Dto` y `@SerialName`, fail-fast
  de `OPENCODE_API_KEY`. Se **reutilizan** (la CLI/test opt-in los construyen).
- `backend/src/main/kotlin/…/rag/summary/{CitizenSummaryGenerator,CitizenSummaryPromptBuilder,SummaryOutputParser,SummaryGenerationDto,CitizenSummaryResult}.kt`
  — **verificado**: patrón exacto a seguir (servicio sin Ktor, prompt puro que
  delimita el contexto como **datos, no instrucciones**, parser puro que quita
  *fences*, resultado tipado, fuente inyectada). Se **reutilizan como referencia**,
  no se modifican.
- `backend/src/main/kotlin/…/rag/retrieval/{HybridSearch,SearchFilter}.kt` —
  **verificado**: `search(query, filter, limit): List<FragmentMatch>` y filtro de
  metadatos interno (sin sufijo). Punto de recuperación del chat.
- `backend/src/main/kotlin/…/persistence/FragmentRepository.kt` — **verificado**:
  `FragmentEntity(publicationId, order, reference, content)` (sin URL) y
  `FragmentMatch(fragment, distance)`.
- `backend/src/main/kotlin/…/persistence/PublicationRepository.kt` —
  **verificado**: `findById(id): Publicacion?` con `urlOficial`/`titulo`; será la
  base del `CitationResolver` de producción (FT00031), **no** se modifica.
- `backend/src/main/kotlin/…/rag/guardrails/{SummaryTextNormalizer,SummaryGroundingChecker,OfficialSourceValidator}.kt`
  — **verificado**: `SummaryTextNormalizer` (object puro: `tokens`/`contentTokens`/
  `figures`/`sentences`) y `SummaryGroundingChecker.MIN_CLAIM_SUPPORT = 0.6`
  públicos; se **reutilizan** (constante + normalizador). `OfficialSourceValidator`
  exige **igualdad** con una URL esperada (no aplica al chat, donde no hay
  publicación de origen única).
- `backend/src/main/kotlin/…/rag/evaluation/RetrievalEvaluator.kt` — patrón de
  **costura inyectable** `fun interface Retriever` y de agregación pura; se sigue
  para el `CitationResolver`.
- `backend/src/test/kotlin/…/rag/summary/CitizenSummaryGeneratorTest.kt` y
  `CitizenSummaryGeneratorLiveTest.kt` — patrón de **dobles deterministas**
  (`FakeTextGenerationProvider`/`FakeEmbeddingProvider`/`FakeFragmentRepository`)
  y de **test opt-in** con fragmentos en memoria (sin BD/ONNX). Modelo a seguir.
- `backend/build.gradle.kts` + `gradle/libs.versions.toml` — ya disponibles
  `ktor-client-core`/`-cio`, `ktor-serialization-kotlinx-json`,
  `kotlinx-coroutines-core`, `ktor-client-mock` (test) y el plugin de
  serialización. **Sin dependencias nuevas.**
- `docs/domain-model.md` (§Consulta: `recibida → respondida | refutada |
  sin_fundamento`; §Edge Cases: afirmación no cubierta → `sin_fundamento`),
  `CONTEXT.md` (§Consulta / chat RAG), `docs/technical-discovery.md` (chat RAG,
  OpenCode), `docs/roadmap.md` §0.4 (`0.4-T07`), `.agents/skills/rag-datapublico/SKILL.md`
  §5/§7, `CONSTRAINTS.md` §«IA y coste»/§«Guardrails», `docs/adr/0015`/`0017`,
  `docs/risks-and-open-questions.md` («Guardrails y umbral del chat RAG»).

### Existing Patterns To Follow

- **Interfaz de proveedor intercambiable** (`TextGenerationProvider`) + doble
  determinista en el gate; el servicio no conoce Ktor ni OpenCode.
- **Prompt puro** que delimita el contexto como **datos, no instrucciones** y
  prohíbe el conocimiento propio (`CitizenSummaryPromptBuilder`).
- **Parser puro** que quita *fences* de Markdown y falla con error **tipado**
  (`SummaryOutputParser`).
- **Resultado tipado** (no excepción) para los estados de dominio esperados
  (`CitizenSummaryResult.Valid`/`Invalid`); **excepción tipada** para salida no
  interpretable.
- **Costura inyectable** con `fun interface` para lo que toca red/BD
  (`Retriever`, `SummaryGenerator`).
- **Grounding léxico conservador** reutilizando `SummaryTextNormalizer` (FT00022).
- **Tests opt-in** por variable de entorno fuera del gate/CI.
- **Estilo MUST**: identificadores en inglés, KDoc en castellano, un solo
  `return`, sin `else if`, funciones ≤40 líneas, `@SerialName` explícito en todo
  `@Serializable`, sufijo `Dto` en tipos de transporte y **sin sufijo** en valores
  internos.

### Current Gaps

- No existe ninguna generación de respuesta de chat, ni prompt, ni parser de la
  salida del chat.
- No existe ningún modelo de resultado de chat (estados `respondida`/`refutada`/
  `sin_fundamento`) ni de cita a la fuente.
- `TextGenerationProvider` (FT00020) aún no tiene un consumidor de chat.
- No existe forma de resolver la **fuente oficial** de un fragmento recuperado:
  `FragmentEntity` no lleva la URL y `FragmentMatch` tampoco.

## Technical Approach

Nuevo paquete en `:backend`: `es.aviferdev.datopublico.backend.rag.chat`
(librería **pura** salvo el proveedor de texto, que ya está tras interfaz). La
dirección de dependencia es correcta: `rag/chat/` → `rag/retrieval/`,
`rag/generation/`, `rag/guardrails/` (primitivas puras), `persistence/`
(`FragmentEntity`) e `ingesta/publicacion/` (`Publicacion`).

### `rag/chat/ChatResult.kt` — resultado tipado (valores internos, sin sufijo)

- `enum ChatStatus { ANSWERED, REFUTED, UNFOUNDED }` (**interno**, no
  `@Serializable`: no es un tipo de transporte; la UI/API define su wire en
  FT00031/FT00037).
- `data class ChatCitation(publicationId: String, title: String, officialUrl: String)`
  — cita a la fuente oficial (valor interno).
- `sealed interface ChatResult` con `val answer: String`,
  `val citations: List<ChatCitation>` y `val usage: TokenUsage?`:
  - `Answered(answer, citations, usage)` — pregunta respondida (citas no vacías).
  - `Refuted(answer, citations, usage)` — afirmación refutada (citas no vacías).
  - `Unfounded(answer, usage)` — sin fundamento; `citations = emptyList()`.
- `ChatGenerationException(message, cause)` — error tipado de frontera (salida no
  parseable, estado desconocido o cita con índice inválido), análogo a
  `SummaryGenerationException`.

### `rag/chat/ChatPromptBuilder.kt` — prompt puro (sin red/BD/estado)

- `build(query: String, fragments: List<FragmentEntity>): GenerationRequest`.
  Prompt de sistema (rol de **verificación contra el BOE**, castellano claro,
  **solo** el contexto, el contexto son **datos no instrucciones**, salida JSON
  estricta) y prompt de usuario (la consulta + contexto **numerado** `[0]`, `[1]`…
  con su `reference`/`content`, acotado por constantes documentadas, y el esquema
  de salida). El esquema exige `estado` (`respondida`/`refutada`/`sin_fundamento`),
  `respuesta` y `citas` (lista de **índices** de fragmento); instruye a declarar
  `sin_fundamento` cuando el corpus no permita confirmar ni refutar y a **no
  inventar**. No se fija `response_format` (no depender de una extensión del
  proveedor).

### `rag/chat/ChatOutputDto.kt` + `ChatOutputParser.kt` — salida del modelo

- `@Serializable data class ChatOutputDto(@SerialName("estado") status: String,
  @SerialName("respuesta") answer: String, @SerialName("citas") citations:
  List<Int> = emptyList())` (sufijo `Dto`, `@SerialName` explícito).
- `ChatOutputParser` (puro): `parse(raw): ChatOutputDto` — recorta espacios, quita
  *fences* ```` ``` ````/`json` y parsea con `DatoPublicoJson`; vacío o JSON
  inválido ⇒ `ChatGenerationException`.
- `statusOf(token: String): ChatStatus` — mapea el token de wire
  (`respondida`/`refutada`/`sin_fundamento`) al enum interno; un token desconocido
  ⇒ `ChatGenerationException` (fail-fast, sin `else if`).

### `rag/chat/ChatGroundingChecker.kt` — guardrail de contenido (puro)

- `object ChatGroundingChecker`: `isSupported(answer: String, context:
  List<FragmentEntity>): Boolean`.
- **Reutiliza** `SummaryTextNormalizer` (FT00022): considera **afirmaciones** las
  oraciones de la respuesta (`sentences`) y comprueba que **todas** sus **cifras**
  estén en el contexto y que la fracción de sus **términos de contenido**
  presentes alcance `SummaryGroundingChecker.MIN_CLAIM_SUPPORT` (= 0.6, constante
  reutilizada). Una afirmación sin términos de contenido cuenta como sustentada.
- Límite documentado: el grounding es **léxico** y **conservador** (una paráfrasis
  válida puede degradar a `sin_fundamento`); el falso negativo **nunca** publica
  una posible alucinación (fail-safe).

### `rag/chat/CitationResolver.kt` — costura inyectable de la fuente

- `fun interface CitationResolver { fun resolve(publicationId: String):
  ChatCitation? }` — puerto interno (sin sufijo): el servicio no conoce
  `PublicationRepository` ni JDBC. En **producción** (FT00031) se implementa sobre
  `PublicationRepository.findById` (`Publicacion.id` → `ChatCitation(id, titulo,
  urlOficial)`); en el **gate** se usa un doble determinista. Devuelve `null` si la
  publicación no se puede resolver.

### `rag/chat/RagChatService.kt` — servicio (sin Ktor)

- `class RagChatService(hybridSearch: HybridSearch, textGenerationProvider:
  TextGenerationProvider, citationResolver: CitationResolver, promptBuilder:
  ChatPromptBuilder = ChatPromptBuilder(), parser: ChatOutputParser =
  ChatOutputParser())`.
- `suspend fun answer(query: String, filter: SearchFilter = SearchFilter(),
  limit: Int = DEFAULT_LIMIT): ChatResult`:
  1. `require(query.isNotBlank())` (fail-fast antes de recuperar).
  2. Recupera con `HybridSearch.search(query, filter, limit)` y toma los
     `FragmentEntity`. **Contexto vacío ⇒ `ChatResult.Unfounded(UNFOUNDED_MESSAGE)`
     sin invocar al proveedor**.
  3. Construye el prompt, invoca al proveedor y parsea la salida.
  4. Si el estado es `UNFOUNDED` ⇒ `Unfounded(respuesta del modelo)`.
  5. Si el estado es `ANSWERED`/`REFUTED`: verifica el grounding con
     `ChatGroundingChecker`; si **no** está sustentada ⇒ `Unfounded` (degradación,
     no se publica una afirmación fuera del corpus).
  6. Resuelve las citas (índices del modelo → fragmentos → `CitationResolver`,
     **deduplicadas** por `publicationId`); índice fuera de rango ⇒
     `ChatGenerationException`. Sin ninguna cita resoluble ⇒ `Unfounded` (una
     respuesta `respondida`/`refutada` **exige** cita).
  7. Devuelve `Answered`/`Refuted` con la respuesta y las citas.
- El `usage` de `GenerationResponse` se propaga al resultado (control de coste
  futuro, FT00030/FT00031); `null` si el proveedor no lo aporta.
- `UNFOUNDED_MESSAGE` es un **mensaje de dominio** (no texto de UI); la UI puede
  sustituirlo (FT00037). `DEFAULT_LIMIT` documentado y ajustable.

### Sin wiring y sin anticipar lo diferido

`Application.kt`, `ingesta/`, `persistence/`, `rag/retrieval/`, `rag/generation/`,
`rag/guardrails/`, `rag/summary/`, `rag/review/`, `rag/evaluation/`, migraciones,
`:shared`, `:composeApp`, CI e `init.sh` quedan **intactos**. Sin dependencias
Gradle nuevas. Sin migración. Sin endpoints ni UI.

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico/backend` se abrevia
como `…/backend`:

- `backend/src/main/kotlin/…/backend/rag/chat/ChatResult.kt` — create; `ChatStatus`,
  `ChatCitation`, `ChatResult` (sealed) y `ChatGenerationException`.
- `backend/src/main/kotlin/…/backend/rag/chat/ChatPromptBuilder.kt` — create;
  prompt puro (contexto numerado, esquema JSON).
- `backend/src/main/kotlin/…/backend/rag/chat/ChatOutputDto.kt` — create; DTO de
  salida `@Serializable`.
- `backend/src/main/kotlin/…/backend/rag/chat/ChatOutputParser.kt` — create; parser
  puro (*fences* + JSON + estado).
- `backend/src/main/kotlin/…/backend/rag/chat/ChatGroundingChecker.kt` — create;
  grounding léxico (reutiliza `SummaryTextNormalizer`).
- `backend/src/main/kotlin/…/backend/rag/chat/CitationResolver.kt` — create; costura
  `fun interface`.
- `backend/src/main/kotlin/…/backend/rag/chat/RagChatService.kt` — create; servicio
  de chat.
- `backend/src/test/kotlin/…/backend/rag/chat/ChatPromptBuilderTest.kt` — create;
  gate, prompt (consulta, contexto numerado, no-inyección).
- `backend/src/test/kotlin/…/backend/rag/chat/ChatOutputParserTest.kt` — create;
  gate, *fences*/JSON inválido/vacío/estado desconocido.
- `backend/src/test/kotlin/…/backend/rag/chat/ChatGroundingCheckerTest.kt` — create;
  gate, sustentado/no sustentado/cifra/contexto vacío.
- `backend/src/test/kotlin/…/backend/rag/chat/RagChatServiceTest.kt` — create; gate,
  dobles (escenarios 1–7: respondida, refutada, sin fundamento, contexto vacío,
  proveedor sustituible, degradación por grounding, cita no resoluble/índice
  inválido).
- `backend/src/test/kotlin/…/backend/rag/chat/RagChatServiceLiveTest.kt` — create;
  **opt-in** `OPENCODE_LIVE_TEST=1` (OpenCode real; fragmentos en memoria; sin
  PostgreSQL ni ONNX; fail-fast sin clave).
- `docs/desarrollo-local.md` (producto) — modify; sección de chat y comando opt-in.

Harness (privado): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0020` + índice,
`.agents/skills/rag-datapublico/SKILL.md`, `feature_list.json`, `PROGRESS.md`
(ver *Durable Documentation Impact*).

Total ≈ **12 ficheros de producto** + docs: muy por debajo del límite de 30.
**No** requiere división en partes.

## Rename Mapping

No aplica: la feature es **código nuevo** con identificadores en **inglés** y KDoc
en castellano (regla MUST vigente); **no** renombra identificadores existentes
(eso es FT00047). Los tokens de wire del estado (`respondida`/`refutada`/
`sin_fundamento`) son **datos de la fuente/dominio** y se conservan tal cual.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI (la UI de chat es
  FT00037; `DESIGN.md` §«Respuesta de chat» se implementará allí).
- Design source: no aplica.
- Screens or states affected: ninguno.
- New design artifact required: no.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — `rag/` gana `chat/` (prompt, parser, grounding,
  costura de citas y servicio de chat RAG); se documenta la etapa «consulta →
  recuperación → generación → grounding → respuesta con citas o `sin_fundamento`»
  y la frontera **Backend → OpenCode** (ya existente, ahora también para chat).
- `CONSTRAINTS.md`: **update** — nueva sección **«Chat RAG»** con MUST: el chat
  responde **solo** con el contexto recuperado y **cita la fuente oficial**; el
  modelo **no** produce la URL (se **inyecta** desde la publicación vía
  `CitationResolver`); una respuesta `respondida`/`refutada` **exige** al menos una
  cita resoluble; un guardrail de grounding léxico (reutiliza
  `SummaryTextNormalizer` y `MIN_CLAIM_SUPPORT`) **degrada a `sin_fundamento`** las
  respuestas no sustentadas y el **contexto vacío** declara `sin_fundamento` **sin
  invocar al proveedor**; el chat es una **librería sin wiring** (endpoint/rate
  limiting FT00030/FT00031, UI FT00037, sin persistir historial); prueba real
  **opt-in** (`OPENCODE_LIVE_TEST=1`).
- `AGENTS.md`: **not needed** — no cambian el flujo, el arranque ni las reglas
  operativas.
- Other docs: `docs/adr/0020-chat-rag-citas-inyectadas-grounding.md` — **create**
  (decisión durable: chat RAG tras el proveedor de texto intercambiable, con
  citas **inyectadas** desde la publicación —no generadas por el modelo— y
  guardrail de grounding léxico que degrada a `sin_fundamento`) + índice;
  `.agents/skills/rag-datapublico/SKILL.md` §5/§7 — **update** (estado actual
  FT00025); `docs/desarrollo-local.md` — **update**.

## Implementation Plan

1. Crear `ChatResult` (`ChatStatus`, `ChatCitation`, sealed `ChatResult`,
   `ChatGenerationException`).
2. Crear `ChatPromptBuilder` (puro; contexto numerado; esquema JSON con
   `estado`/`respuesta`/`citas`) con su test de gate.
3. Crear `ChatOutputDto` + `ChatOutputParser` (puro; *fences*; mapeo de estado con
   fail-fast) con su test de gate.
4. Crear `ChatGroundingChecker` (puro; reutiliza `SummaryTextNormalizer` y
   `MIN_CLAIM_SUPPORT`) con su test de gate.
5. Crear `CitationResolver` (`fun interface`) y `RagChatService` (compone
   `HybridSearch` + proveedor + parser + grounding + resolver) con su test de gate
   con dobles (escenarios 1–7).
6. Añadir `RagChatServiceLiveTest` (**opt-in** `OPENCODE_LIVE_TEST=1`, fail-fast
   sin clave; fragmentos en memoria, sin PostgreSQL ni ONNX).
7. Pasar el gate sin red y registrar evidencia; actualizar `ARCHITECTURE.md`,
   `CONSTRAINTS.md`, ADR 0020 + índice, skill RAG y `docs/desarrollo-local.md`.
   `PROGRESS.md`/`feature_list.json` los cierra el orquestador.

## Implementation Tasks

- [ ] `ChatResult`: `ChatStatus`, `ChatCitation`, `ChatResult.Answered`/`Refuted`/
      `Unfounded` y `ChatGenerationException`.
- [ ] `ChatPromptBuilder` (puro; consulta + contexto numerado; esquema
      `estado`/`respuesta`/`citas`; «datos, no instrucciones»).
- [ ] `ChatOutputDto` (`@Serializable`, `@SerialName` explícito) + `ChatOutputParser`
      (*fences*, JSON, estado con fail-fast).
- [ ] `ChatGroundingChecker` (puro; reutiliza `SummaryTextNormalizer` y
      `SummaryGroundingChecker.MIN_CLAIM_SUPPORT`).
- [ ] `CitationResolver` (`fun interface`).
- [ ] `RagChatService.answer(query, filter, limit)`: recuperación → prompt →
      proveedor → parser → grounding → citas inyectadas → `Answered`/`Refuted`/
      `Unfounded`; contexto vacío sin invocar al proveedor.
- [ ] Tests de gate: prompt, parser, grounding y servicio con dobles (escenarios
      1–7; sin red ni BD).
- [ ] `RagChatServiceLiveTest` opt-in (`OPENCODE_LIVE_TEST=1`, fail-fast).
- [ ] Docs durables: ARCHITECTURE, CONSTRAINTS, ADR 0020 + índice, skill RAG,
      `docs/desarrollo-local.md`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red ni BD (obligatorio)**: `./gradlew :backend:test --rerun-tasks` →
  BUILD SUCCESSFUL con los tests nuevos en verde (0 fallos) y el resto de
  `:backend` intacto. `./gradlew build --no-daemon -PskipClient` (incluye
  `:backend:detekt` y `:cpdCheck`), `./gradlew test`, `./gradlew detekt` y
  `env -u JAVA_HOME .harness/init.sh` → exit 0.
- **Offline confirmado**: sin `OPENCODE_LIVE_TEST`, el test live se **omite** sin
  abrir sockets; el proveedor real solo lo ejerce ese test. Ningún test del gate
  toca la red ni la BD.
- **Escenarios 1–7 (gate)**: cubiertos por `RagChatServiceTest`,
  `ChatGroundingCheckerTest`, `ChatOutputParserTest` y `ChatPromptBuilderTest` con
  dobles/`MockEngine`.
- **Escenario 9 (opt-in, fuera del gate y de la CI)**:
  ```sh
  OPENCODE_LIVE_TEST=1 OPENCODE_API_KEY=<clave> \
    ./gradlew :backend:test --tests '*RagChatServiceLiveTest'
  ```
  Esperado: respuesta fundamentada con cita a la fuente (y/o refutación); sin la
  clave, falla con mensaje claro (fail-fast). No requiere PostgreSQL ni el modelo
  E5.
- **E2E**: no aplica — librería sin flujo de usuario ni endpoint nuevo (el repo no
  tiene comando E2E; el cliente es Compose Multiplatform). El endpoint es FT00031.
- `init.sh` (harness): **no** se modifica; no se le añade ningún paso de red ni de
  proveedor.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con los tests nuevos de gate (recuento, 0
  fallos) y del gate (`build -PskipClient`, `test`, `detekt`, `init.sh` exit 0).
- Salida del test live opt-in (respuesta con cita a la fuente y/o refutación) y
  del fail-fast sin clave.
- Confirmación de que **no** se tocó `TextGenerationProvider`/
  `OpenCodeTextGenerationProvider`/`OpenCodeConfig`/`SummaryTextNormalizer`/
  `SummaryGroundingChecker`/`HybridSearch`/`SearchFilter`/`ResumenDto`/
  `CitizenSummaryValidator`/`rag/summary/`/`rag/review/`/`Application.kt`/
  migraciones/`:shared`/`:composeApp`/CI/`init.sh`.
- Casos negativos por test: respuesta no sustentada (degradación), contexto vacío
  (sin invocar al proveedor), cita vacía/no resoluble, índice fuera de rango y
  estado desconocido.
- Ficheros del commit `FT00025`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `rag/chat/` + sus tests; **sin** endpoints/API/rate
      limiting (FT00031), **sin** UI (FT00037), **sin** DTO de wire en `:shared`,
      **sin** persistir historial, **sin** wiring en `Application.kt`/job/backfill
      ni migración; `TextGenerationProvider`/`OpenCodeTextGenerationProvider`/
      `OpenCodeConfig`/`SummaryTextNormalizer`/`SummaryGroundingChecker`/
      `HybridSearch`/`SearchFilter`/`ResumenDto`/`CitizenSummaryValidator`/
      `rag/summary/`/`rag/review/`/`:shared`/`:composeApp`/CI/`init.sh` intactos.
- [ ] Escenarios 1–9 pasan; **todo el gate corre sin red, BD, modelo ni OpenCode**
      y el test live se omite sin `OPENCODE_LIVE_TEST`.
- [ ] El proveedor está tras `TextGenerationProvider` y se sustituye por un doble
      sin tocar `RagChatService`; la impl OpenCode es la única que conoce
      Ktor/HTTP y la clave (solo servidor).
- [ ] La respuesta se fundamenta **solo** en el contexto recuperado: una respuesta
      no sustentada **degrada a `sin_fundamento`**; el **contexto vacío** declara
      `sin_fundamento` **sin invocar al proveedor**.
- [ ] La **fuente oficial se inyecta** desde la publicación vía `CitationResolver`
      (el modelo solo aporta **índices** de fragmento, nunca URLs); una respuesta
      `respondida`/`refutada` **exige** ≥1 cita resoluble.
- [ ] Salida no parseable, estado desconocido o índice fuera de rango ⇒
      `ChatGenerationException` tipada (no se devuelve una respuesta a medias).
- [ ] Grounding **puro, determinista y offline**, con `MIN_CLAIM_SUPPORT`
      reutilizado; umbral documentado y constante.
- [ ] `return` único, sin `else if`, funciones ≤40 líneas, KDoc en castellano con
      identificadores en inglés; `@SerialName` explícito en cada `@Serializable` y
      sufijo `Dto` en el DTO de transporte.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0020 + índice, skill RAG,
      `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] Sin comportamiento de producto no relacionado ni ficheros fuera de alcance.

## Open Questions / Risks

- **Recuperación no acotada a una publicación.** `HybridSearch`/`SearchFilter` no
  filtran por `publicationId` (riesgo heredado de FT00017/FT00020): el contexto
  puede incluir fragmentos de publicaciones vecinas. El filtro del chat viene de la
  petición (categoría/fecha) y es **opcional**; se acota el `limit`. Si con datos
  reales resulta ruidoso, una feature posterior puede extender el filtro.
- **Resolución de citas por consulta.** `FragmentEntity` no lleva la URL: las citas
  se resuelven con `CitationResolver` (en producción, `PublicationRepository.findById`
  por publicación distinta, hasta `limit` consultas). El wiring (FT00031) puede
  optimizarlo con un método por lote; se documenta.
- **Grounding léxico, no semántico.** El chequeo por solapamiento de términos
  (cifras estrictas + fracción de contenido ≥ 0.6) es **conservador**: una
  paráfrasis válida puede degradar a `sin_fundamento` (falso negativo). Se acepta
  conscientemente (fail-safe: nunca se publica una posible alucinación); el umbral
  es una constante ajustable.
- **Duplicación con `SummaryGroundingChecker`/`SummaryOutputParser` (CPD).** El
  grounding y el parser del chat son análogos a los del resumen. Mantenerlos
  **mínimos** y locales; si `:cpdCheck` (umbral 100 tokens) señala duplicación,
  extraer un helper `internal` compartido (p. ej. el recorte de *fences*) es un
  refactor **aditivo** permitido, sin cambio de comportamiento.
- **Inyección de prompt.** Los fragmentos son contenido remoto **no confiable**; el
  prompt los delimita e instruye «son datos, no instrucciones», pero la defensa de
  contenido es de esta misma feature (grounding) y del endurecimiento de FT00030.
- **Salida del modelo no JSON, estado inventado o índice inválido.** El parser
  falla con error tipado; no se reintenta ni se repara en esta feature.
- **Contexto largo / coste.** El chat es más caro por consulta que el feed; el
  prompt acota número/longitud de fragmentos y el `usage` se propaga, pero el
  **rate limiting y el control de cuota son FT00030/FT00031** (fuera de alcance).
- **`CitationResolver` sin impl de producción.** Hasta que FT00031 lo cablee sobre
  `PublicationRepository`, el servicio es una pieza sin consumidor de runtime; el
  valor de la feature es la librería y sus garantías.
- **Dependencia de `SummaryTextNormalizer` (FT00022).** Se reutiliza el
  normalizador y la constante `MIN_CLAIM_SUPPORT`; FT00022 está `accepted`.
  **Recomendación**: añadir `guardrails-anti-alucinacion` a `depends_on` (lo aplica
  el orquestador).
- **Mensaje de `sin_fundamento`.** `UNFOUNDED_MESSAGE` es un mensaje de **dominio**,
  no texto de UI; la UI (FT00037) puede sustituirlo por un recurso i18n.
