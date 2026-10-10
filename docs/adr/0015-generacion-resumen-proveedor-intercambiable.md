# ADR 0015: Generación del resumen ciudadano tras un proveedor de texto intercambiable, con la fuente inyectada

## Estado

Aceptado (2026-10-10). Decisión del dueño para FT00020 (`generacion-resumen-go`).

## Contexto

El pipeline RAG ya recupera contexto (FT00017, `HybridSearch`), el contrato del
resumen ciudadano está fijado y validado en `:shared` (FT00019,
`CitizenSummaryValidator`) y la decisión de IA usa **OpenCode** (endpoint
OpenAI-compatible, `deepseek-v4.1-flash`) para la generación. Faltaba la pieza que
**genera** el resumen: construir el prompt con el contexto recuperado, invocar al
modelo y encajar su salida con el contrato, sin acoplar el servicio a OpenCode ni
dejar que el modelo produzca la cita a la fuente (regla dura de **trazabilidad**).

OpenCode es una dependencia **externa de tiempo de ejecución** con una **clave**
que debe vivir solo en el servidor; el gate de build/tests y la CI **no** pueden
hacer red. Además, el modelo es **no confiable**: puede devolver *fences* de
Markdown, JSON inválido o inventar datos, y no debe decidir la fuente oficial.

## Decisión

Añadir en `:backend`, como **librería sin wiring**, dos paquetes:

- **`rag/generation/`** — el proveedor de texto tras una **interfaz
  intercambiable** (`TextGenerationProvider`, `suspend`; valores internos
  `GenerationRequest`/`GenerationResponse` sin sufijo y `TextGenerationException`
  tipada), su config por entorno con **fail-fast** de `OPENCODE_API_KEY`
  (`OpenCodeConfig`: base URL, modelo y temperatura con defaults) y la
  implementación **OpenCode** (`OpenCodeTextGenerationProvider`): `POST
  {baseUrl}/chat/completions` con `Authorization: Bearer <clave>`, DTOs de wire
  `@Serializable` con sufijo `Dto` y `@SerialName` explícito, parseo de
  `choices[0].message.content` y factory `openCodeHttpClient` (CIO +
  `ContentNegotiation` + `HttpTimeout`). La interfaz **no** conoce Ktor ni el
  modelo.
- **`rag/summary/`** — el **servicio** `CitizenSummaryGenerator`, que recupera con
  `HybridSearch`, construye el prompt puro (`CitizenSummaryPromptBuilder`, que
  delimita el contexto como **datos, no instrucciones** y pide plazo en la variante
  de empleo/beca), invoca el proveedor, parsea la salida
  (`SummaryOutputParser`, quita *fences*; vacío o JSON inválido ⇒
  `SummaryGenerationException`), **inyecta la fuente oficial** desde
  `Publicacion.urlOficial` (`SummaryGenerationDto.toResumenDto`, con `avisoIA =
  true`) y **valida** con `CitizenSummaryValidator`. Devuelve un resultado tipado
  `CitizenSummaryResult.Valid`/`Invalid` (un resumen inválido **no** se publica; no
  es una excepción). `publication.categoria` nula es fail-fast.

## Alternativas consideradas

- **Acoplar el servicio a OpenCode/Ktor.** Se descarta: el proveedor debe ser
  sustituible por un doble en los tests del gate (sin red) y por otro proveedor sin
  tocar el servicio; la clave y HTTP quedan confinados a una sola implementación.
- **Que el modelo produzca la `fuenteOficial`.** Se descarta: la cita a la fuente
  es una regla dura de trazabilidad y no puede depender de la IA; se **inyecta** de
  forma determinista desde `Publicacion.urlOficial`.
- **Lanzar una excepción ante un resumen inválido.** Se descarta: un resumen
  inválido es un estado de dominio esperado (guardrails FT00022 / cola de revisión
  FT00023), no un error de programación; el consumidor necesita la **lista** de
  violaciones. Se reserva `SummaryGenerationException` para la salida **no
  parseable**.
- **Validar el contrato de nuevo en `:backend`.** Se descarta: se **reutiliza** el
  validador puro de FT00019 (`:shared`), sin duplicar reglas.
- **Fijar `response_format`/JSON mode del proveedor.** Se descarta: no depender de
  una extensión del proveedor; se confía en el prompt + parser.

## Consecuencias

- La generación queda lista para el cacheo (FT00021), los guardrails de contenido
  (FT00022), la cola de revisión/aviso de IA (FT00023) y el chat (FT00025), que
  reutilizarán `TextGenerationProvider`.
- Nueva frontera **Backend → OpenCode** (solo salida, clave solo en el servidor,
  `HttpTimeout` explícito, prueba real **opt-in** `OPENCODE_LIVE_TEST=1`).
- Es una **librería sin wiring**: no se cablea en `Application.kt`/job/backfill, no
  añade endpoints/UI ni migración, y no toca `ResumenDto`/`CitizenSummaryValidator`/
  `HybridSearch`.
- Riesgos asumidos y documentados: la recuperación no se acota a la publicación
  (filtro heurístico por metadatos), la inyección de prompt solo se **mitiga** aquí
  (defensa de contenido en FT00022), el contexto se acota por constantes y el uso de
  OpenCode como backend de app pública consume cuota (cacheo/rate limiting
  posteriores).