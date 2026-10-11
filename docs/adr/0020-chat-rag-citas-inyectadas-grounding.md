# ADR 0020: Chat RAG tras el proveedor de texto intercambiable, con citas inyectadas desde la publicación y grounding léxico que degrada a `sin_fundamento`

## Estado

Aceptado (2026-10-11). Decisión del dueño del proyecto para FT00025
(`chat-generacion`). No supersede ningún ADR; reutiliza las decisiones de FT00017
(ADR 0012, recuperación híbrida), FT00020 (ADR 0015, proveedor de texto
intercambiable) y FT00022 (ADR 0017, grounding léxico).

## Contexto

La simplificación con IA ya tiene la **recuperación híbrida** (`HybridSearch` /
`SearchFilter`, FT00017), el **proveedor de texto intercambiable**
(`TextGenerationProvider` + `OpenCodeTextGenerationProvider`, FT00020), el contrato
del resumen (`CitizenSummaryValidator`, FT00019), el **cacheo** y el uso de tokens
(FT00021), los **guardrails anti-alucinación** con el normalizador léxico puro
`SummaryTextNormalizer` + `SummaryGroundingChecker` (FT00022) y la **disposición**
del resumen (FT00023). Falta la tarea `0.4-T07`, la contraparte de chat: dada una
**pregunta** o una **afirmación**, responder **solo** con el corpus del BOE y
**citar la fuente oficial**, refutando la afirmación si el corpus la contradice o
declarando `sin_fundamento` si no permite confirmarla.

Restricciones: el gate y la CI corren **sin red, sin base de datos, sin el modelo
E5 y sin `OPENCODE_API_KEY`**; la generación real depende de OpenCode y no es
determinista, así que **no** puede ser la unidad verificable del gate; `:backend`
es una **librería sin wiring** hasta que la API (FT00031) y la UI (FT00037) la
consuman; `FragmentEntity` **no** lleva la URL oficial (la publicación sí), así que
la cita no se puede derivar del fragmento; PostgreSQL + pgvector con **JDBC +
HikariCP sin ORM** (ADR 0003); todo el código en inglés con KDoc en castellano, un
solo `return`, sin `else if` y funciones ≤40 líneas.

## Decisión

- **Chat como librería pura en `rag/chat/`.** El servicio `RagChatService`
  compone `HybridSearch` + un `TextGenerationProvider` + un `CitationResolver` +
  `ChatPromptBuilder` + `ChatOutputParser`. **No** conoce Ktor, HTTP, JDBC ni el
  modelo concreto: el proveedor real se sustituye por un **doble** en los tests sin
  tocar el servicio. **No** se cablea en `Application.kt`/job/backfill y **no**
  añade endpoints, UI ni migración.
- **Resultado tipado con los tres estados del dominio.** `ChatStatus`
  (`ANSWERED`/`REFUTED`/`UNFOUNDED`) y `ChatResult`
  (`Answered`/`Refuted`/`Unfounded`) son valores **internos** (sin sufijo, **no**
  `@Serializable`): el wire de la API/UI es de FT00031/FT00037. `Answered`/`Refuted`
  **siempre** llevan ≥1 `ChatCitation`; `Unfounded` **nunca** lleva citas. Una
  salida no interpretable, un estado desconocido o un índice de fragmento fuera de
  rango es `ChatGenerationException` **tipada** (distinta de un resultado de
  dominio esperado).
- **La fuente oficial se inyecta, no la produce el modelo.** El modelo solo aporta
  **índices** de fragmento (`citas`); `CitationResolver` (un `fun interface`, misma
  costura que `Retriever`/`SummaryGenerator`) resuelve el `publicationId` del
  fragmento a `ChatCitation(publicationId, title, officialUrl)`. En **producción**
  (FT00031) se implementa sobre `PublicationRepository.findById`; en el gate, un
  doble determinista. Una publicación no resoluble **descarta** esa cita: no se
  inventa una fuente.
- **Grounding léxico que degrada, no publica.** `ChatGroundingChecker` (puro)
  reutiliza `SummaryTextNormalizer` y `SummaryGroundingChecker.MIN_CLAIM_SUPPORT`
  (= 0.6, **sin umbral nuevo**): considera afirmaciones las oraciones de la
  respuesta y exige que **todas** estén sustentadas (todas sus cifras en el
  contexto y ≥ 0.6 de sus términos de contenido). Una respuesta
  `respondida`/`refutada` no sustentada **degrada a `sin_fundamento`** con el
  mensaje de dominio `UNFOUNDED_MESSAGE` (no se publica la afirmación fuera del
  corpus). Es **conservador**: un falso negativo degrada, nunca publica una posible
  alucinación.
- **Contexto vacío sin invocar al proveedor.** Con cero fragmentos recuperados, el
  servicio devuelve `ChatResult.Unfounded(UNFOUNDED_MESSAGE)` **sin** llamar al
  proveedor (ahorro y ausencia de invención).
- **Prompt y parser puros.** `ChatPromptBuilder` numera el contexto `[0]`, `[1]`…
  con su `reference`/`content`, lo delimita como **datos, no instrucciones** y fija
  el esquema JSON (`estado`/`respuesta`/`citas`); `ChatOutputParser` quita las
  *fences* de Markdown, parsea con `DatoPublicoJson` y traduce el token de estado
  con **fail-fast** si es desconocido (sin `else if`). No se fija
  `response_format` para no depender de una extensión del proveedor.
- **El `usage` se propaga.** El consumo de tokens de `GenerationResponse` viaja en
  el resultado (control de coste futuro, FT00030/FT00031); `null` si el proveedor
  no lo aporta. No se implementa cacheo ni rate limiting aquí.
- **Verificación *offline* + opt-in.** El gate cubre prompt, parser, grounding y
  servicio con **dobles deterministas**, sin red ni BD; la prueba real contra
  OpenCode es **opt-in** (`OPENCODE_LIVE_TEST=1`, fail-fast sin clave, sin
  PostgreSQL ni ONNX), fuera de `build`/`test`/`init.sh` y de la CI.

## Alternativas consideradas

- **Que el modelo devuelva las URLs de las citas.** Descartado: el modelo puede
  alucinar la fuente y no tiene la URL oficial; se **inyecta** de forma
  determinista desde la publicación (mismo principio que la fuente del resumen,
  ADR 0015).
- **Reutilizar `SummaryGroundingChecker` directamente.** Descartado: su API toma un
  `ResumenDto`, no una respuesta de texto libre; se reutiliza la **primitiva**
  (`SummaryTextNormalizer`) y la **constante** (`MIN_CLAIM_SUPPORT`), no la regla
  del resumen.
- **Grounding semántico (embeddings).** Descartado en esta feature: exigiría el
  modelo E5 en el gate y perdería el determinismo; el grounding léxico es
  conservador por diseño (fail-safe) y el umbral es ajustable.
- **Un umbral de revisión propio del chat (`NEEDS_REVIEW`).** Descartado: el chat
  no publica resúmenes ni tiene cola; el desenlace es binario
  (`respuesta citada` o `sin_fundamento`). La degradación es la respuesta segura.
- **Devolver la respuesta del modelo en `Unfounded` tras degradar.** Descartado:
  expondría a la UI una afirmación no sustentada; se usa el mensaje de dominio
  `UNFOUNDED_MESSAGE` (la UI puede sustituirlo, FT00037). En cambio, cuando el
  propio modelo declara `sin_fundamento`, sí se devuelve su respuesta (es una
  explicación de ausencia, no una afirmación).
- **Cachear respuestas de chat o limitar la cuota aquí.** Descartado: control de
  coste/cuota y rate limiting son FT00030/FT00031; el `usage` se propaga para
  habilitarlos.
- **DTO de wire del chat en `:shared`.** Descartado: el contrato de la API es
  FT00031; aquí solo se construye la librería.
- **Extraer un parser/grounding compartido con el resumen.** Descartado salvo que
  el CPD lo exija: mantenerlos **mínimos y locales** evita acoplar dos dominios
  distintos; no se modifican los de FT00020/FT00022.

## Consecuencias

- **Habilita** el chat de verificación del BOE con trazabilidad a la fuente: la
  respuesta se fundamenta solo en el corpus, cita la publicación oficial y nunca
  inventa (contexto vacío o respuesta no sustentada ⇒ `sin_fundamento`). Deja
  listo el consumidor para el endpoint/API (FT00031), el rate limiting (FT00030) y
  la UI (FT00037), que definirán su wire.
- **Cuesta** un `CitationResolver` sin implementación de producción hasta FT00031:
  el servicio es una pieza sin consumidor de runtime; el valor de la feature es la
  librería y sus garantías. La resolución de citas hace **hasta `limit` consultas**
  por publicación distinta (el wiring podrá optimizarlo por lote).
- **Riesgos asumidos y documentados**: el grounding es **léxico y conservador** (una
  paráfrasis válida puede degradar a `sin_fundamento`; se acepta el falso negativo
  como fail-safe); la recuperación **no** se acota a una publicación (riesgo
  heredado de FT00017/FT00020); el prompt trata los fragmentos como **datos no
  confiables**, pero la defensa de contenido es el grounding y el endurecimiento de
  FT00030; el contexto largo encarece la consulta (el prompt lo acota y el `usage`
  se propaga).
- **Documentación/código**: `ARCHITECTURE.md` (`rag/chat/`), regla MUST en
  `CONSTRAINTS.md` §«Chat RAG», estado actual en la skill `rag-datapublico` §5/§7,
  sección en `docs/desarrollo-local.md` (producto) y este ADR.
- **Verificación**: `ChatPromptBuilderTest`/`ChatOutputParserTest`/
  `ChatGroundingCheckerTest`/`RagChatServiceTest` (gate, escenarios 1–7) y
  `RagChatServiceLiveTest` (opt-in, escenario 9). Sin dependencias Gradle nuevas,
  sin migración y sin wiring.
