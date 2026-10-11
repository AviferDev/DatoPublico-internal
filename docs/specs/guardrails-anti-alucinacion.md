# Feature Implementation Spec: Guardrails anti-alucinación y trazabilidad

## Source Feature

- `id`: guardrails-anti-alucinacion
- `ft_id`: FT00022 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ≈16 ficheros de producto, por debajo del límite de 30)
- `area`: simplificacion-ia
- `depends_on`: generacion-resumen-go (FT00020, `accepted`, ya en `main`)
- `status`: not_started (al planificar)
- `source`: `feature_list.json`
- `claim`: rama `feat/ft00022-guardrails-anti-alucinacion` ya reclamada en
  `origin` (commit `6b2a223 chore(FT00022): claim`); sin PR abierto hacia `main`.

## Goal

Añadir en `:backend`, como **librería sin wiring**, la **capa de guardrails
anti-alucinación y trazabilidad** (tarea `0.4-T03`) que se ejecuta **después de
generar** el resumen ciudadano (FT00020) y **antes de publicarlo**: verifica que
(a) la **fuente oficial** es un enlace **válido** (absoluto, oficial del BOE y
**idéntico** al `urlOficial` de la publicación; opcionalmente **alcanzable** con
un puerto inyectable) y (b) que las **afirmaciones** del resumen («¿Qué cambia?»,
«¿A quién afecta?» y «Cifras clave») están **sustentadas por el contexto
recuperado** (trazabilidad), reutilizando además el validador de **contrato** de
FT00019 (`CitizenSummaryValidator`).

El resultado es una **decisión tipada** — `PUBLISHABLE` (publicable),
`NEEDS_REVIEW` (baja confianza → cola de revisión, FT00023) o `DISCARDED`
(descartado) — más una **puntuación de grounding** `[0,1]` que FT00023 usará como
señal de confianza. **No** se implementa la cola de revisión ni se persiste nada:
la feature aporta la pieza y sus garantías, sustituible por dobles deterministas
en el gate, que corre **sin red ni BD**.

## Non-Goals

- **Cola de revisión**, estados del resumen (`pendiente`/`generado`/…), `estado`,
  `confianza` persistida y exigencia del **aviso de IA** → FT00023. Aquí solo se
  **exponen** la decisión y la puntuación; **no** se escribe en `cola_revision`
  ni en `resumen` ni se añade migración.
- **Publicación** del resumen en la tabla `resumen` → FT00023/FT00026.
- **Chat RAG** y su guardrail de `sin_fundamento`/`refutada` → FT00025.
- **Evaluación de calidad** con golden set de resúmenes → FT00024.
- **Endpoints Ktor**, API, UI y **wiring** en `Application.kt`/job/backfill: el
  puerto de alcanzabilidad y el servicio quedan **sin construir** en el arranque
  (lo hará FT00026+).
- **Reranking** de la recuperación o cambios en `HybridSearch`: se reutiliza tal
  cual.
- Cambios en `ResumenDto`/`CitizenSummaryValidator`/`HybridSearch` ni en el
  contrato de wire (congelado). **No** se modifica FT00020/FT00021.

## Job Story

When el backend ha generado el resumen ciudadano de una publicación del BOE,
I want comprobar que la fuente oficial es válida y que cada afirmación está
sustentada por el contexto recuperado antes de publicarlo,
so I can no publicar nunca una alucinación ni un resumen sin trazabilidad, y
marcar los de baja confianza para revisión sin bloquear el resto del feed.

## Users And Permissions

- **Backend (guardrails, FT00022):** consumidor interno; decide publicar,
  enviar a revisión o descartar. Sin cuentas ni datos personales.
- **FT00023 (cola de revisión):** consume `GuardrailDecision.NEEDS_REVIEW` y
  `groundingScore` para encolar; **no** se implementa aquí.
- **Operador/desarrollador:** ejecuta la prueba real **opt-in** de alcanzabilidad
  (`BOE_LIVE_TEST=1`), fuera del gate.
- **Usuario final (ciudadanía):** anónimo; solo verá resúmenes ya publicables
  (en FT00026+).

## Acceptance Scenarios

### Scenario 1: un resumen válido pasa los guardrails y queda publicable

Given un `ResumenDto` que cumple el contrato (FT00019), con `fuenteOficial`
https oficial idéntica a `Publicacion.urlOficial`, y un contexto recuperado que
sustenta todas sus afirmaciones y cifras
When `SummaryGuardrail.evaluate(publication, summary, context)` se ejecuta
Then devuelve `decision = PUBLISHABLE`, `isPublishable = true`,
`groundingScore >= REVIEW_THRESHOLD` y sin violaciones.

### Scenario 2: una afirmación fuera del contexto no se publica

Given un resumen con una oración de «¿Qué cambia?» cuyos términos de contenido
no aparecen en el contexto recuperado
When se evalúa
Then `decision != PUBLISHABLE`, `guardrailViolations` contiene
`UNSUPPORTED_CLAIM` y `groundingScore` baja (no publicable).

### Scenario 3: una cifra no sustentada no se publica

Given un resumen cuyo «Cifras clave» incluye un número que no aparece en el
contexto recuperado
When se evalúa
Then `guardrailViolations` contiene `UNSUPPORTED_FIGURE` y el resultado **no**
es publicable.

### Scenario 4: una fuente inexistente o no oficial se descarta

Given un resumen con `fuenteOficial` en blanco, no https, con host ajeno al BOE,
o **distinta** de `Publicacion.urlOficial`
When se evalúa
Then `guardrailViolations` contiene `SOURCE_NOT_OFFICIAL` y
`decision = DISCARDED`.

### Scenario 5: una fuente estructuralmente válida pero no alcanzable se descarta

Given una fuente oficial bien formada y un doble de `SourceReachability` que
devuelve `false` para esa URL
When se evalúa
Then `guardrailViolations` contiene `SOURCE_NOT_REACHABLE` y
`decision = DISCARDED`.

### Scenario 6: un incumplimiento de contrato se descarta

Given un resumen con `aQuienAfecta` vacío (violación de contrato de FT00019)
When se evalúa
Then `contractViolations` contiene `MISSING_WHO_IS_AFFECTED` y
`decision = DISCARDED` (el contrato roto no es recuperable por revisión).

### Scenario 7: un resumen de baja confianza va a revisión (sin publicar)

Given un resumen con contrato y fuente válidos y un grounding en
`[DISCARD_THRESHOLD, REVIEW_THRESHOLD)` (p. ej. la mitad de las afirmaciones
sustentadas)
When se evalúa
Then `decision = NEEDS_REVIEW` y `isPublishable = false` (no se publica; FT00023
lo encolará).

### Scenario 8: sin contexto recuperado se descarta

Given una evaluación con `context` vacío
When se evalúa
Then `guardrailViolations` contiene `NO_CONTEXT`, `groundingScore = 0.0` y
`decision = DISCARDED`.

### Scenario 9: el gate sigue sin red ni BD

Given el runner de CI sin red, sin clave de OpenCode y sin PostgreSQL
When se ejecuta `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew
detekt` o `.harness/init.sh`
Then todo está en verde; el test de alcanzabilidad real se omite sin abrir
sockets.

### Scenario 10: alcanzabilidad real de la fuente (opt-in)

Given `BOE_LIVE_TEST=1` y una URL oficial real del BOE
When `HttpSourceReachability.isReachable(url)` se ejecuta
Then responde `true` (HTTP 2xx/3xx); sin la variable, el test se omite.

## Repository Research

### Files Inspected

- `shared/src/commonMain/kotlin/…/validation/CitizenSummaryValidator.kt`,
  `CitizenSummaryValidation.kt`, `CitizenSummaryVariant.kt` — **verificado**: el
  validador de **contrato** (FT00019) es un `object` puro que **acumula** y **no
  lanza**; se **reutiliza** sin cambios (contrato, no contenido).
- `shared/src/commonMain/kotlin/…/model/ResumenDto.kt` — contrato de salida
  (`queCambia`, `aQuienAfecta`, `cifrasClave`, `fuenteOficial`, `avisoIA`,
  `plazo`); **congelado**, no se toca.
- `backend/src/main/kotlin/…/rag/summary/CitizenSummaryGenerator.kt` —
  **verificado**: recupera el contexto **internamente** (con `HybridSearch` +
  `SearchFilter`) y **no** lo expone; el guardrail recibirá el contexto como
  **entrada explícita** (no se modifica FT00020).
- `backend/src/main/kotlin/…/rag/summary/{CitizenSummaryResult,SummaryGenerationDto}.kt`
  — resultado tipado y salida del modelo; `fuenteOficial` se **inyecta** desde
  `Publicacion.urlOficial` (por eso el guardrail puede exigir igualdad).
- `backend/src/main/kotlin/…/persistence/FragmentRepository.kt` — `FragmentEntity`
  (`reference`, `content`) es la unidad de **contexto**; `FragmentMatch` añade la
  distancia.
- `backend/src/main/kotlin/…/rag/retrieval/{HybridSearch,SearchFilter}.kt` —
  recuperación y filtro de metadatos; **no** se modifican.
- `backend/src/main/kotlin/…/persistence/{SummaryRepository,ReviewQueueRepository}.kt`
  — tablas `resumen` (`estado`, `confianza`) y `cola_revision` (FT00008); son de
  FT00023/FT00026 y **no** se usan aquí.
- `backend/src/main/kotlin/…/rag/generation/OpenCodeTextGenerationProvider.kt` y
  `ingesta/sumario/BoeSumarioHttpClient.kt` — patrón de **cliente HTTP con
  `HttpClient` inyectado + factory** (CIO + `ContentNegotiation` + `HttpTimeout`),
  aplicable al puerto de alcanzabilidad.
- `backend/src/test/kotlin/…/rag/summary/CitizenSummaryGeneratorTest.kt` — patrón
  de **dobles deterministas** (`FakeTextGenerationProvider`, `FakeFragmentRepository`,
  `FakeEmbeddingProvider`).
- `backend/src/test/kotlin/…/ingesta/sumario/BoeSumarioLiveTest.kt` — patrón de
  **test opt-in** por variable de entorno que se **omite sin abrir sockets**.
- `docs/domain-model.md` (§Resumen ciudadano: `generado →
  validado_por_guardrails → publicado | en_cola_revision`, `descartado`),
  `docs/roadmap.md` 0.4-T03, `.agents/skills/rag-datapublico/SKILL.md` §6,
  `CONSTRAINTS.md` §«IA y coste» y §«Contrato del resumen ciudadano»,
  `docs/adr/0014`/`0015`/`0016`, `docs/risks-and-open-questions.md`
  («Alucinaciones del modelo…»).

### Existing Patterns To Follow

- **Puerto + implementación + factory + excepción tipada** para integraciones
  externas (`EmbeddingProvider`/`E5EmbeddingProvider`, `TextGenerationProvider`/
  `OpenCodeTextGenerationProvider`).
- **Cliente HTTP con `HttpClient` inyectado**, factory con motor CIO,
  `ContentNegotiation` (`DatoPublicoJson`) y `HttpTimeout`; `MockEngine` en el
  gate, prueba real **opt-in**.
- **Composición pura** de piezas de `rag/` (servicios sin Ktor ni SQL), sin
  wiring en `Application.kt`.
- **Estilo MUST**: identificadores en inglés, KDoc en castellano, un solo
  `return`, sin `else if`, funciones ≤40 líneas, `@SerialName` explícito en todo
  `@Serializable`, sufijo `Dto` en tipos de transporte y **sin sufijo** en
  valores internos.

### Current Gaps

- No existe ninguna verificación de **contenido** del resumen: el contrato
  (FT00019) solo comprueba estructura y presencia de la fuente.
- No hay mecanismo de **grounding** contra el contexto recuperado ni puntuación
  de confianza.
- No hay ninguna noción de **decisión de guardrail** (publicar/revisar/descartar)
  ni puerto de **alcanzabilidad** de la fuente.

## Technical Approach

Nuevo paquete en `:backend`: `es.aviferdev.datopublico.backend.rag.guardrails`
(librería **pura** salvo el puerto de alcanzabilidad), que compone la validación
de contrato (FT00019) con la verificación de **fuente** y de **grounding**. La
dirección de dependencia es correcta: `rag/guardrails/` → `rag/retrieval/`,
`persistence/` (`FragmentEntity`), `ingesta/publicacion/` (`Publicacion`) y
`:shared` (`ResumenDto`, `CitizenSummaryValidator`).

### 1. Normalización de texto (pura) — `SummaryTextNormalizer.kt`

- `object SummaryTextNormalizer` (sin red/BD/estado, determinista):
  - `tokens(text): List<String>` — minúsculas (`Locale.ROOT`), **sin acentos**
    (NFD + descarte de marcas), no alfanumérico → espacio, colapsa y recorta.
  - `contentTokens(text): List<String>` — `tokens` menos las **palabras vacías**
    castellanas (lista curada, constante documentada) y los tokens de longitud
    `< MIN_TOKEN_LENGTH` (= 3); **conserva** los numéricos.
  - `figures(text): List<String>` — tokens que contienen algún dígito.
  - `sentences(text): List<String>` — divide por `.`, `;` y salto de línea;
    recorta y descarta los vacíos.
- Límite documentado: es **léxico** (sin *stemming* ni sinónimos), así que una
  paráfrasis puede no coincidir; se compensa siendo **conservador** (el falso
  negativo lleva a revisión/descarte, no a publicar).

### 2. Validez de la fuente oficial (pura) — `OfficialSourceValidator.kt`

- `object OfficialSourceValidator.isOfficial(source: String, expected: String):
  Boolean` — `true` solo si `source` recortado empieza por `https://`, su **host**
  está en la **lista blanca oficial** (`www.boe.es`, `boe.es`) y `source` es
  **igual** a `expected` (`Publicacion.urlOficial`). La igualdad garantiza la
  **trazabilidad** a la publicación de origen (la fuente se inyecta desde ella en
  FT00020); la lista blanca garantiza que apunta al BOE.
- No comprueba **alcanzabilidad** (es red; ver §4).

### 3. Grounding de las afirmaciones (puro) — `SummaryGroundingChecker.kt`

- `data class GroundingAssessment(val score: Double, val violations:
  List<SummaryGuardrailViolation>)` (valor interno, sin sufijo).
- `object SummaryGroundingChecker.check(summary: ResumenDto, context:
  List<FragmentEntity>): GroundingAssessment`:
  - `contextTokens` = unión de `contentTokens(reference + content)` de los
    fragmentos; `contextFigures` = unión de `figures(reference + content)`.
  - **Afirmaciones**: `sentences(queCambia)` + `sentences(aQuienAfecta)` + cada
    entrada no vacía de `cifrasClave`.
  - Una afirmación es **sustentada** si: (i) sus `figures` están **todas** en
    `contextFigures` (regla estricta de cifras; si falta alguna, no sustentada) y
    (ii) la fracción de sus `contentTokens` presentes en `contextTokens` es
    `>= MIN_CLAIM_SUPPORT` (= 0.6). Una afirmación sin `contentTokens` (solo
    palabras vacías) cuenta como sustentada (no hay nada que verificar).
  - `score = afirmacionesSustentadas / totalAfirmaciones` (si no hay
    afirmaciones → `1.0`); añade `UNSUPPORTED_FIGURE` si alguna cifra no está en
    el contexto y `UNSUPPORTED_CLAIM` si alguna afirmación no alcanza el umbral.
- Límite documentado: el umbral es **conservador** y el grounding es **léxico**;
  se ajusta por constantes sin cambiar la firma.

### 4. Alcanzabilidad de la fuente (puerto) — `SourceReachability.kt` + `HttpSourceReachability.kt`

- `fun interface SourceReachability { suspend fun isReachable(url: String):
  Boolean }` — **puerto interno** (sin sufijo): el guardrail no conoce Ktor.
- `HttpSourceReachability(httpClient, timeout…)`: implementa el puerto con un
  `HttpClient` **inyectado** (`GET`, `expectSuccess = false`), devuelve `true` si
  el estado es 2xx/3xx. Factory `sourceReachabilityHttpClient()` (CIO +
  `HttpTimeout`) siguiendo `boeSumarioHttpClient`/`openCodeHttpClient`.
- El guardrail lo recibe **opcional** (`SourceReachability? = null`): sin puerto
  solo se valida la **estructura**; con puerto se valida además la
  **alcanzabilidad**. En producción lo inyectará el wiring (FT00026+); en el gate
  se usa un doble determinista. La prueba real es **opt-in** (`BOE_LIVE_TEST=1`).

### 5. Resultado y decisión — `GuardrailDecision.kt`, `SummaryGuardrailViolation.kt`, `SummaryGuardrailResult.kt`

- `enum GuardrailDecision { PUBLISHABLE, NEEDS_REVIEW, DISCARDED }`.
- `enum SummaryGuardrailViolation { SOURCE_NOT_OFFICIAL, SOURCE_NOT_REACHABLE,
  NO_CONTEXT, UNSUPPORTED_CLAIM, UNSUPPORTED_FIGURE }`.
- `data class SummaryGuardrailResult(decision, contractViolations:
  List<CitizenSummaryViolation>, guardrailViolations:
  List<SummaryGuardrailViolation>, groundingScore: Double)` con
  `val isPublishable: Boolean get() = decision == GuardrailDecision.PUBLISHABLE`.

### 6. Servicio evaluador — `SummaryGuardrail.kt`

- `class SummaryGuardrail(private val reachability: SourceReachability? = null)`:
  `suspend fun evaluate(publication: Publicacion, summary: ResumenDto, context:
  List<FragmentEntity>): SummaryGuardrailResult`.
  - `sourceValid = OfficialSourceValidator.isOfficial(summary.fuenteOficial,
    publication.urlOficial)`.
  - `contractValidation = CitizenSummaryValidator.validate(summary,
    requireCategory(publication))` (fail-fast `IllegalArgumentException` si la
    categoría es nula, igual que el generador).
  - `grounding = SummaryGroundingChecker.check(summary, context)`.
  - `reachable` = si `reachability != null` y `sourceValid`, su resultado;
    en otro caso `true`.
  - `violations` = `buildList { if (!sourceValid) add(SOURCE_NOT_OFFICIAL);
    if (context.isEmpty()) add(NO_CONTEXT); if (!reachable)
    add(SOURCE_NOT_REACHABLE); addAll(grounding.violations) }`.
  - `decision = decide(contractValid, sourceValid, reachable, grounding)` con
    `when` (sin `else if`), recibiendo el `GroundingAssessment` completo (no solo
    el `score`):
    - contrato inválido, fuente inválida o no alcanzable → `DISCARDED`;
    - `score < DISCARD_THRESHOLD` (= 0.5) → `DISCARDED`;
    - `score < REVIEW_THRESHOLD` (= 0.8) **o `grounding.violations` no vacía**
      (hay `UNSUPPORTED_CLAIM`/`UNSUPPORTED_FIGURE`) → `NEEDS_REVIEW`;
    - en otro caso (score ≥ `REVIEW_THRESHOLD` **y sin violaciones**) →
      `PUBLISHABLE`.
  - **Invariante de trazabilidad**: una afirmación o cifra no sustentada por el
    contexto **nunca** es publicable. Como el `score` es una fracción, un caso
    límite (p. ej. 4 de 5 afirmaciones sustentadas = 0.8) podría alcanzar
    `REVIEW_THRESHOLD` con violaciones presentes; por eso publicar exige además
    que `grounding.violations` esté vacía. Con violaciones de grounding, el
    resumen va a revisión (`NEEDS_REVIEW`).
- Constantes documentadas: `MIN_CLAIM_SUPPORT = 0.6`, `MIN_TOKEN_LENGTH = 3`,
  `DISCARD_THRESHOLD = 0.5`, `REVIEW_THRESHOLD = 0.8`; host oficial
  `{www.boe.es, boe.es}`. Ajustables sin cambiar firmas.

### Sin wiring y sin anticipar lo diferido

`Application.kt`, `ingesta/`, `job`, `backfill`, `persistence/`,
`HybridSearch`, `CitizenSummaryValidator`, `ResumenDto`, `:shared`, `:composeApp`,
migraciones, CI e `init.sh` quedan **intactos**. Sin dependencias Gradle nuevas
(se reutilizan `ktor-client-core`/`-cio` y `ktor-client-mock`). Sin migración ni
persistencia: la cola de revisión (FT00023) y la publicación (FT00026) **no** se
anticipan. Nota de integración: el **contexto** que el guardrail verifica debe
ser el mismo que alimentó la generación; como `CitizenSummaryGenerator` recupera
internamente, el wiring (FT00026+) aportará los fragmentos (o un cambio
compatible posterior los expondrá). Se documenta como riesgo.

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico/backend` se abrevia
como `…/backend`:

- `backend/src/main/kotlin/…/backend/rag/guardrails/GuardrailDecision.kt` —
  create; enum de decisión.
- `backend/src/main/kotlin/…/backend/rag/guardrails/SummaryGuardrailViolation.kt`
  — create; enum de violaciones de contenido.
- `backend/src/main/kotlin/…/backend/rag/guardrails/SummaryGuardrailResult.kt` —
  create; resultado tipado + `isPublishable`.
- `backend/src/main/kotlin/…/backend/rag/guardrails/SummaryTextNormalizer.kt` —
  create; normalización pura (tokens, cifras, oraciones, palabras vacías).
- `backend/src/main/kotlin/…/backend/rag/guardrails/OfficialSourceValidator.kt` —
  create; validez de la fuente oficial (pura).
- `backend/src/main/kotlin/…/backend/rag/guardrails/SummaryGroundingChecker.kt` —
  create; grounding léxico por afirmación (puro).
- `backend/src/main/kotlin/…/backend/rag/guardrails/SourceReachability.kt` —
  create; puerto `suspend` de alcanzabilidad.
- `backend/src/main/kotlin/…/backend/rag/guardrails/HttpSourceReachability.kt` —
  create; impl con `HttpClient` inyectado + factory.
- `backend/src/main/kotlin/…/backend/rag/guardrails/SummaryGuardrail.kt` —
  create; servicio evaluador + umbrales.
- `backend/src/test/kotlin/…/backend/rag/guardrails/SummaryTextNormalizerTest.kt`
  — create; gate.
- `backend/src/test/kotlin/…/backend/rag/guardrails/OfficialSourceValidatorTest.kt`
  — create; gate.
- `backend/src/test/kotlin/…/backend/rag/guardrails/SummaryGroundingCheckerTest.kt`
  — create; gate (sustentado / no sustentado / cifra / contexto vacío).
- `backend/src/test/kotlin/…/backend/rag/guardrails/SummaryGuardrailTest.kt` —
  create; gate, dobles (escenarios 1–8; `SourceReachability` falso).
- `backend/src/test/kotlin/…/backend/rag/guardrails/HttpSourceReachabilityTest.kt`
  — create; gate, `MockEngine` (2xx ⇒ `true`; 404/500/fallo ⇒ `false`).
- `backend/src/test/kotlin/…/backend/rag/guardrails/SummaryGuardrailLiveTest.kt` —
  create; **opt-in** `BOE_LIVE_TEST=1` (alcanzabilidad real de una URL del BOE).
- `docs/desarrollo-local.md` (producto) — modify; sección de guardrails y comando
  opt-in.

Harness (privado): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR `0017` + índice,
`.agents/skills/rag-datapublico/SKILL.md`, `feature_list.json`, `PROGRESS.md`
(ver *Durable Documentation Impact*).

Total ≈ **16 ficheros de producto** + docs: por debajo del límite de 30. **No**
requiere división en partes.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI (la UI de detalle es
  FT00033).
- Design source: no aplica.
- Screens or states affected: ninguno.
- New design artifact required: no.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — `rag/` gana `guardrails/` (evaluador puro de
  fuente + grounding, decisión tipada y puerto de alcanzabilidad); se documenta
  la etapa «generación → **guardrails** → publicación/revisión» y la frontera
  contrato (FT00019) vs. contenido (FT00022).
- `CONSTRAINTS.md`: **update** — nueva sección **«Guardrails anti-alucinación y
  trazabilidad»** (MUST): ningún resumen se publica sin fuente oficial válida
  (absoluta, host del BOE e **idéntica** a `Publicacion.urlOficial`) ni con
  afirmaciones no sustentadas por el contexto recuperado; la decisión es tipada
  (`PUBLISHABLE`/`NEEDS_REVIEW`/`DISCARDED`) y expone una puntuación de
  grounding; **sin** persistir la cola (FT00023) ni wiring; prueba real **opt-in**
  (`BOE_LIVE_TEST=1`).
- `AGENTS.md`: **not needed** — no cambian el flujo, el arranque ni las reglas
  operativas.
- Other docs: `docs/adr/0017-guardrails-anti-alucinacion-trazabilidad.md` —
  **create** (decisión durable: guardrail de contenido **offline y determinista**
  tras la generación, grounding léxico por afirmación con umbrales, fuente
  estructural + puerto de alcanzabilidad, decisión tipada sin persistencia) +
  índice; `.agents/skills/rag-datapublico/SKILL.md` §6 — **update** (estado
  FT00022); `docs/desarrollo-local.md` — **update**.

## Implementation Plan

1. Crear `SummaryTextNormalizer` (puro) y `OfficialSourceValidator` (puro) con
   sus tests de gate.
2. Crear `GuardrailDecision`, `SummaryGuardrailViolation`, `SummaryGuardrailResult`
   y `SummaryGroundingChecker` (puro) con su test de gate (sustentado, no
   sustentado, cifra fuera de contexto, contexto vacío).
3. Crear el puerto `SourceReachability` y `HttpSourceReachability` (+ factory) con
   su test `MockEngine`.
4. Crear `SummaryGuardrail` (reutiliza `CitizenSummaryValidator`; decide con
   `when`; umbrales) y su test de gate con dobles (escenarios 1–8, incluida la
   alcanzabilidad falsa).
5. Añadir `SummaryGuardrailLiveTest` (**opt-in** `BOE_LIVE_TEST=1`; se omite sin
   abrir sockets).
6. Pasar el gate sin red ni BD y registrar evidencia; actualizar `ARCHITECTURE.md`,
   `CONSTRAINTS.md`, ADR 0017 + índice, skill RAG y `docs/desarrollo-local.md`.
   `PROGRESS.md`/`feature_list.json` los cierra el orquestador.

## Implementation Tasks

- [ ] `SummaryTextNormalizer` (tokens, contentTokens, figures, sentences;
      palabras vacías y `MIN_TOKEN_LENGTH`).
- [ ] `OfficialSourceValidator.isOfficial(source, expected)` (https + host del
      BOE + igualdad con la publicación).
- [ ] `GuardrailDecision`, `SummaryGuardrailViolation`, `SummaryGuardrailResult`
      (`isPublishable`).
- [ ] `SummaryGroundingChecker` (grounding léxico por afirmación + regla estricta
      de cifras; `GroundingAssessment`).
- [ ] `SourceReachability` (puerto `suspend`) + `HttpSourceReachability` + factory.
- [ ] `SummaryGuardrail.evaluate(publication, summary, context)` (contrato +
      fuente + grounding → decisión; fail-fast sin categoría).
- [ ] Tests de gate: normalizador, validador de fuente, grounding, evaluador con
      dobles, `MockEngine` de alcanzabilidad.
- [ ] `SummaryGuardrailLiveTest` opt-in (`BOE_LIVE_TEST=1`).
- [ ] Docs durables: ARCHITECTURE, CONSTRAINTS, ADR 0017 + índice, skill RAG,
      `docs/desarrollo-local.md`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red ni BD (obligatorio)**: `./gradlew :backend:test --rerun-tasks` →
  BUILD SUCCESSFUL con los tests nuevos en verde (0 fallos) y los **278 de
  FT00021** intactos. `./gradlew build --no-daemon -PskipClient` (incluye
  `:backend:detekt` y `:cpdCheck`), `./gradlew test`, `./gradlew detekt` y
  `env -u JAVA_HOME .harness/init.sh` → exit 0.
- **Offline confirmado**: sin `BOE_LIVE_TEST`, el test live se **omite** sin abrir
  sockets; el cliente HTTP real solo lo ejerce ese test. Ningún test del gate toca
  la red ni la BD.
- **Escenarios 1–8 (gate)**: cubiertos por `SummaryGuardrailTest`,
  `SummaryGroundingCheckerTest`, `OfficialSourceValidatorTest`,
  `SummaryTextNormalizerTest` y `HttpSourceReachabilityTest` con dobles/`MockEngine`.
- **Escenario 10 (opt-in, fuera del gate y de la CI)**:
  ```sh
  BOE_LIVE_TEST=1 ./gradlew :backend:test --tests '*SummaryGuardrailLiveTest'
  ```
  Esperado: la URL oficial del BOE responde alcanzable; sin la variable, el test
  se omite. Nota: el `cacerts` del JBR puede no incluir la raíz FNMT que firma
  `*.boe.es` (igual que en FT00006); no afecta al gate.
- **E2E**: no aplica — librería sin flujo de usuario ni endpoint nuevo (el repo no
  tiene comando E2E; el cliente es Compose Multiplatform).
- `init.sh` (harness): **no** se modifica; no se le añade ningún paso de red ni de
  BD.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con los tests nuevos de gate (recuento, 0
  fallos) y del gate (`build -PskipClient`, `test`, `detekt`, `init.sh` exit 0).
- Confirmación de que los **278 tests de FT00021 siguen verdes** y de que
  `ResumenDto`/`CitizenSummaryValidator`/`HybridSearch`/`CitizenSummaryGenerator`/
  `CachedCitizenSummaryGenerator`/`Application.kt`/migraciones/`:shared`/
  `:composeApp`/CI/`init.sh` quedan intactos.
- Casos negativos por test: afirmación no sustentada, cifra fuera del contexto,
  fuente no oficial/inexistente, fuente no alcanzable, contrato roto, contexto
  vacío y baja confianza (revisión).
- Salida del test live opt-in de alcanzabilidad (o su omisión sin
  `BOE_LIVE_TEST`).
- Ficheros del commit `FT00022`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo `rag/guardrails/` + sus tests; **sin** cola de
      revisión/estados/confianza persistida (FT00023), **sin** chat (FT00025),
      **sin** endpoints/UI ni wiring; `ResumenDto`/`CitizenSummaryValidator`/
      `HybridSearch`/`CitizenSummaryGenerator`/`Application.kt`/migraciones/
      `:shared`/`:composeApp`/CI/`init.sh` intactos.
- [ ] Escenarios 1–10 pasan; **todo el gate corre sin red ni BD** y el test live
      se omite sin `BOE_LIVE_TEST`.
- [ ] El guardrail se ejecuta **después de generar** y **antes de publicar**;
      devuelve una **decisión tipada** y una **puntuación de grounding**; **no**
      persiste nada ni escribe en `resumen`/`cola_revision`.
- [ ] Reutiliza `CitizenSummaryValidator` (FT00019) para el contrato, **sin**
      duplicar reglas ni cambiar el wire.
- [ ] Ningún resumen con afirmación fuera del contexto, cifra no sustentada,
      fuente no oficial/inexistente o no alcanzable queda **publicable**.
- [ ] El grounding es **puro, determinista y offline**; los umbrales están
      documentados y son constantes; el resultado es sustituible por dobles.
- [ ] `SourceReachability` es un **puerto** y la impl HTTP usa `HttpClient`
      inyectado con `HttpTimeout`; el guardrail no conoce Ktor.
- [ ] `return` único, sin `else if`, funciones ≤40 líneas, KDoc en castellano con
      identificadores en inglés; `@SerialName` explícito donde aplique y sufijo
      `Dto` solo en tipos de transporte.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0017 + índice, skill RAG,
      `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] Sin comportamiento de producto no relacionado ni ficheros fuera de alcance.

## Open Questions / Risks

- **Grounding léxico, no semántico.** El chequeo por solapamiento de términos de
  contenido (y regla estricta de cifras) es **conservador**: una paráfrasis válida
  puede no alcanzar el umbral y acabar en revisión/descarte (falso negativo). Se
  acepta conscientemente (fail-safe: no se publica una posible alucinación) y los
  umbrales son constantes ajustables.
- **Contexto de generación vs. de verificación.** El guardrail recibe el contexto
  por parámetro; como `CitizenSummaryGenerator` recupera internamente, el wiring
  (FT00026+) debe pasar los **mismos** fragmentos (o un cambio compatible futuro
  los expondrá). Si se pasa un contexto distinto, la verificación sería
  inconsistente; riesgo documentado.
- **Recuperación no acotada a la publicación.** `HybridSearch` no filtra por
  `publicationId` (riesgo heredado de FT00020): el contexto puede incluir
  fragmentos de publicaciones vecinas y «sustentar» de más; el guardrail no lo
  corrige.
- **Alcanzabilidad opt-in.** El gate valida la fuente **estructuralmente**; la
  comprobación de alcanzabilidad real depende de un puerto inyectado (producción,
  FT00026+) y de la prueba opt-in. Un enlace estructuralmente válido pero muerto
  pasaría el gate offline; se documenta.
- **Cifras con formato distinto.** «1.000» vs «1000» o «treinta» vs «30» pueden
  hacer fallar la regla de cifras; se compensa con revisión/descarte, no con
  publicación.
- **Umbrales.** `MIN_CLAIM_SUPPORT`/`DISCARD_THRESHOLD`/`REVIEW_THRESHOLD` son
  heurísticos; el golden set de FT00024 debería calibrarlos.
- **Guardrail inerte sin wiring.** Hasta que FT00026+ construya el servicio, el
  guardrail no se usa en runtime; el valor de la feature es la pieza y sus
  garantías.
