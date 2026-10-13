# ADR 0026: Endurecimiento HTTP con plugins oficiales de Ktor (CORS por entorno, rate limiting por IP en memoria y cuerpo de error tipado)

## Estado

Aceptado (2026-10-13). Decisión del dueño del proyecto para FT00030
(`api-cors-ratelimit-errores`). Reutiliza los ADR 0021 (feed y pool único), 0024
(chat y wiring condicional) y 0025 (contrato OpenAPI, prefijo `/v1` y test
anti-deriva); **ajusta** la pauta «sin dependencias Gradle nuevas» de
FT00026–FT00029/FT00031 (que era un MUST NOT **de cada una de esas features**, no
una regla global) al añadir tres plugins oficiales de Ktor. No supersede ningún
ADR.

## Contexto

La 0.5.0 ya sirve los cuatro endpoints de dominio bajo `/v1` y publica su contrato
OpenAPI, pero la API está **desnuda**: no hay CORS (el futuro cliente Web Wasm
fallaría en el *preflight* de `POST /v1/chat` con `Content-Type: application/json`),
no hay rate limiting (el chat RAG es lo más caro por consulta y su abuso puede
agotar la cuota de OpenCode; riesgo explícito en `docs/risks-and-open-questions.md`)
y los errores responden **sin cuerpo** (`400`/`404`/`500`/`502`), lo que impide un
contrato de error estable para los clientes. Es la tarea `0.5-T05` («Rate limiting,
CORS y manejo de errores»), justo antes de construir la UI (0.6.0).

Restricciones: el gate y la CI corren **sin red, sin base de datos, sin el modelo
E5 y sin `OPENCODE_API_KEY`**; el arranque debe funcionar en entornos parciales
(solo salud) y registrar solo las rutas cuyas dependencias existen; la API es
**pública, de solo lectura, sin cuentas ni credenciales** (no hay datos de usuario
que proteger); el backend es un **único proceso** (Intel N100 / 8 GB), sin Redis ni
caché externa; el despliegue tras Nginx (trust de cabeceras de proxy) es FT00041;
el contrato de dominio de `:shared` no se cambia (solo se **añade** el DTO de
error); todo el código en inglés con KDoc en castellano, un solo `return`, sin
`else if` y funciones ≤40 líneas.

## Decisión

- **Se añaden tres plugins oficiales de Ktor** a la versión fijada **3.0.3**,
  todos **estables** (sin opt-in experimental): `ktor-server-cors` (plugin `CORS`),
  `ktor-server-rate-limit` (plugin `RateLimit`) y `ktor-server-status-pages`
  (plugin `StatusPages`). Es una **excepción deliberada** a la pauta «sin
  dependencias Gradle nuevas» de las features de API previas: implementar CORS
  correcto y un *rate limiter* robusto a mano sería más código, más frágil y con
  más superficie de error. Los plugins **no abren sockets ni servicios**: el gate
  sigue **offline** (los tests usan `testApplication`).
- **CORS configurable por entorno** (`plugins/Cors.kt` + `infra/CorsSettings`):
  métodos `GET`/`POST`/`OPTIONS`, `Content-Type` permitido
  (`allowNonSimpleContentTypes = true`, para el JSON de `/v1/chat`) y
  `allowCredentials = false`. Con `CORS_ALLOWED_ORIGINS` **vacía** se permite
  cualquier origen (`anyHost()`): es una API pública **sin credenciales**, así que
  no hay nada que proteger con una allowlist; con una lista, se aplica una
  **allowlist estricta**. El origen de producción se fijará en el despliegue
  (FT00039). Se instala a nivel de **aplicación** (afecta a todas las rutas).
- **Rate limiting por IP en memoria** (`plugins/RateLimiting.kt` +
  `infra/RateLimitSettings`): dos limitadores nombrados (`ApiRateLimiter.GENERAL` y
  `ApiRateLimiter.CHAT`) con clave `request.origin.remoteHost` (la **IP**). El cupo
  **general** (por defecto **60/60 s**) cubre los endpoints de dominio y el del
  **chat** es más **estricto** (por defecto **6/60 s**) porque es lo más caro.
  `/health` y `/openapi.json` quedan **fuera** (operacionales: deben seguir
  accesibles para monitorización). El plugin añade `X-RateLimit-*` a las
  permitidas y `Retry-After` a las rechazadas (`429`). Configurable por
  `RATE_LIMIT_*`/`CHAT_RATE_LIMIT_*`, con *fail-fast* si un valor no es un entero
  mayor que 0. **Sin** almacén distribuido/persistente (una instancia) y **sin**
  trust de cabeceras de proxy (FT00041).
- **Cuerpo de error tipado** (`plugins/Errors.kt` + `ApiErrorDto`/`ApiErrorCodeDto`
  en `:shared`): el plugin `StatusPages` mapea `400`→`solicitud_invalida`,
  `404`→`no_encontrado`, `429`→`demasiadas_peticiones` (conservando `Retry-After`),
  `500`→`error_interno` y `502`→`servicio_no_disponible` a un
  `ApiErrorDto`(`codigo`,`mensaje`) con `Content-Type` JSON y un mensaje **genérico**
  en castellano (**sin** filtrar detalles internos). Los `400`/`404` existentes y
  los `500`/`502` que produce `Chat.kt` pasan a llevar el cuerpo tipado **sin tocar
  las rutas**; un fallo no controlado se registra y responde `500` (relanzando
  `CancellationException`). El DTO vive en `:shared` (es contrato **público** que el
  cliente consumirá y el OpenAPI documenta), con `@SerialName` explícito y tokens
  `snake_case`; el `HealthDto` operacional sigue en `:backend`.
- **Integración en el routing sin romper los tests `accepted`**
  (`plugins/Routing.kt`): `configureRouting(...)` gana un parámetro **aditivo**
  `applyRateLimits: Boolean = false`. Con `true` (solo `Application.module()` y el
  test de rate limiting) las rutas de dominio se envuelven con `rateLimit(...)`;
  con `false` (tests de ruta existentes) se registran como hasta ahora. Es
  necesario porque `Route.rateLimit(...)` **falla en el arranque** si el plugin
  `RateLimit` no está instalado. El composition root instala los tres plugins
  **siempre** (no dependen de BD/modelo/clave).
- **Contrato OpenAPI actualizado** (ADR 0025): se añaden los esquemas
  `ApiErrorDto`/`ApiErrorCodeDto`, las respuestas de error con
  `content.application/json.schema.$ref = ApiErrorDto` (`400`/`404`/`429` y
  `500`/`502` en el chat) y la cabecera `Retry-After` en el `429`; el cambio es
  **aditivo y compatible**, así que `/v1` se mantiene y `info.version` sube de
  `0.5.0` a **`0.5.1`**. El test anti-deriva (`OpenApiContractTest`) cubre los
  nuevos esquemas y `OpenApiRouteTest` verifica la versión y su presencia.

## Alternativas consideradas

- **Implementar CORS, rate limiting y errores sin dependencias.** Descartado:
  *scope* mayor (preflight y algoritmo de *bucket* a mano), más superficie de error
  y más código que mantener; los plugins son oficiales, de la misma versión que el
  resto de Ktor y no abren sockets.
- **Allowlist de CORS vacía ⇒ sin CORS (default estricto).** Descartado: la API es
  pública y **sin credenciales**; un default estricto rompería la Web Wasm antes de
  conocer su origen. Se documenta que el origen de producción se restringe con
  `CORS_ALLOWED_ORIGINS` (FT00039).
- **Rate limiting distribuido o persistente (Redis/tabla).** Descartado: el backend
  es un **único proceso** en el N100; el reparto entre instancias es una feature de
  escalado futura. Se documenta que, tras un proxy sin `Forwarded`, todos los
  clientes compartirían cupo (FT00041).
- **Rate limiting por identidad/cuotas por usuario.** Descartado: la API no tiene
  cuentas ni datos personales; el límite es por **IP**.
- **`HealthDto`-style error en `:backend`.** Descartado: el error es contrato
  **público** que el cliente consume y el OpenAPI documenta; debe vivir en
  `:shared` como el resto del contrato de wire.
- **Activar el rate limiting por defecto en `configureRouting`.** Descartado:
  obligaría a instalar el plugin en todos los tests de ruta `accepted` (churn
  mecánico); el valor por defecto `false` los mantiene verdes.
- **Versionar por hito (mantener `info.version = 0.5.0`).** Descartado: el ADR 0025
  fija que un cambio aditivo sube la *patch*; `0.5.1` refleja el cambio.
- **Swagger UI/ReDoc interactivos.** Descartado: no los pide la verificación y
  añadirían artefactos y superficie; feature futura opcional.

## Consecuencias

- **Habilita** que el cliente Web (Wasm) consuma la API desde otro origen
  (incluido el *preflight* JSON del chat), que un abuso del chat no agote la cuota
  compartida y que los clientes traten los fallos con un **contrato de error
  estable**. El chat, lo más caro, lleva el cupo más bajo.
- **Cuesta** que el rate limiting sea **por instancia** (el cupo se multiplica con
  varias instancias) y **por IP** (un atacante con muchas IPs no se frena; un proxy
  sin `Forwarded` comparte cupo). Son *trade-offs* conscientes, documentados, y el
  despliegue (FT00041) los revisará.
- **Cuesta** mantener el documento OpenAPI a mano con los nuevos esquemas y
  respuestas; el **test anti-deriva** convierte el olvido en un fallo del gate.
- **Revierte la pauta «sin dependencias»** de las features de API previas: la
  primera resolución de artefactos la hace Gradle como cualquier otra dependencia
  (igual que hoy con Ktor); los tests **no** requieren red.
- **Sin migración** (`V1`…`V5` intactas), **sin** cambios en los DTOs de dominio,
  servicios, `rag/*` o `persistence/*`, **sin** autenticación ni cuotas por usuario
  y **sin** tocar `:composeApp`/CI/`init.sh`.
- **Documentación/código**: `ARCHITECTURE.md`, `CONSTRAINTS.md` §«API pública:
  endurecimiento HTTP», la skill `ktor-backend-architecture`,
  `docs/desarrollo-local.md` (producto) y este ADR.
- **Verificación**: `HttpHardeningConfigTest`, `CorsRouteTest`,
  `RateLimitRouteTest`, `ErrorsRouteTest` (con `testApplication` y dobles
  deterministas) y el `ErrorContractTest` de `:shared`, más
  `OpenApiContractTest`/`OpenApiRouteTest` actualizados; todo en el gate, sin red,
  BD, modelo ni OpenCode. No aplica E2E persistente.
