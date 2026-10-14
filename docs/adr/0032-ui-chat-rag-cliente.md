# ADR 0032: UI del chat RAG en el cliente CMP (estados de dominio, citas y HTTP real)

## Estado

Aceptado (2026-10-14). Decisión del dueño del proyecto al ejecutar `ui-chat`
(FT00037). Continúa los ADR 0027 (base del cliente), 0029 (cliente HTTP común) y
0031 (navegación + ViewModel/`StateFlow`); no supersede ninguno.

## Contexto

La API de chat RAG (`POST /v1/chat`, FT00031) existe y devuelve tres estados de
dominio (`respondida`/`refutada`/`sin_fundamento`) con citas a la fuente oficial.
Faltaba la **pantalla** en `:composeApp`. El spec se planificó **antes** de que
existiera el cliente HTTP (FT00035), con un repositorio en memoria como
placeholder.

## Decisión

1. **Capa `feature/chat/{domain,data,ui}`** con el patrón del cliente: dominio
   propio (`ChatStatus`/`ChatCitation`/`ChatAnswer`/`ChatLoadResult`), puerto
   `ChatRepository`, `AskChatQuestion` (`MAX_QUERY_LENGTH=1000`, consulta en blanco
   no llama) y UI stateless (`ChatScreen`/`ChatQuestionField`/`ChatAnswerCard`/
   `ChatCitations`) con `ChatViewModel` (`StateFlow`, UDF).
2. **`sin_fundamento` es un estado, no un error**: se muestra con información (sin
   botón de reintento) y **citas vacías**; `respondida`/`refutada` llevan **≥1
   cita** y el **aviso de IA** siempre visible.
3. **HTTP real (ajuste del orquestador):** además del repositorio en memoria
   (previews/tests), `HttpChatRepository` + `ChatApi` sobre `core/network`
   (ADR 0029) llaman a `POST /v1/chat` con DTOs propios (`@SerialName`) y mapeo a
   dominio; el *composition root* inyecta el real en `App()`.
4. **Navegación aditiva:** `AppRoutes.CHAT`, destino `chat` en `AppNavHost` y
   acción «Preguntar al BOE» en el encabezado del feed (visible en **todos** los
   estados, no solo con contenido). `AiNotice(text=…)` y `isHttpUrl` aditivos.

## Alternativas consideradas

- **Solo repositorio en memoria** (como el spec original): descartado tras
  aterrizar FT00035; se conserva para previews/tests.
- **Duplicar DTOs por ítem**: descartado; los DTOs+mapeo viven en un fichero
  (`ChatDtos.kt`) para no superar el límite de 30 ficheros.
- **Estado `sin_fundamento` como error**: descartado; es un resultado válido del
  guardrail.

## Consecuencias

- La UI del chat queda funcional y conectada a la API real; completa el alcance de
  UI del cliente CMP junto con FT00032–FT00036.
- Coste asumido: duplicación del contrato de wire (capa anti-corrupción, ADR 0029);
  en runtime, sin el pipeline de resumen/indexado cableados, el chat devuelve
  `sin_fundamento`.
- Documentación afectada: `ARCHITECTURE.md` (§`:composeApp`), `CONSTRAINTS.md`
  (§«Cliente»), skill `compose-multiplatform-architecture`, `docs/desarrollo-local.md`.
