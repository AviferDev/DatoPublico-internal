# Feature Implementation Spec: Endurecimiento HTTP de la API (CORS, rate limiting y errores tipados)

## Source Feature

- `id`: api-cors-ratelimit-errores
- `ft_id`: FT00030 (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; ≈18 ficheros de producto, por debajo del límite de 30)
- `area`: api-publica
- `depends_on`: api-feed-diario (FT00026, `accepted`) + api-detalle-norma
  (FT00027, `accepted`) + api-busqueda (FT00028, `accepted`) + api-chat (FT00031,
  `accepted`). **Falta `api-contratos-openapi` (FT00029, `accepted`)**: el spec
  **actualiza el contrato OpenAPI** (`openapi/openapi.json`) y su test anti-deriva,
  que son de FT00029. El orquestador debe **añadir `api-contratos-openapi` a
  `depends_on`** en `feature_list.json` (el planner no lo edita). Ver
  *Dependencias* más abajo.
- `status`: not_started (al planificar)
- `source`: `feature_list.json` (`notes`: `docs/roadmap.md` 0.5-T05)
- `claim`: rama `feat/ft00030-api-cors-ratelimit-errores` ya reclamada en `origin`
  (`4c98087 chore(FT00030): claim api-cors-ratelimit-errores`).

> **Base de rama (PR apilado).** La rama está **apilada sobre
> `feat/ft00029-api-contratos-openapi`** (`64042ee`, PR **#31** abierto hacia
> `main` y **aún sin fusionar**). El árbol de trabajo **ya** tiene los cuatro
> endpoints bajo el prefijo `/v1` y el documento `openapi/openapi.json` servido en
> `GET /openapi.json` (verificado: `plugins/Routing.kt` con `route("/v1")`,
> `plugins/OpenApi.kt` y `backend/src/main/resources/openapi/openapi.json`). El PR
> de FT00030 tiene **base `feat/ft00029-api-contratos-openapi`** (no `main`): es un
> PR apilado que se rebasará sobre `main` cuando se fusione #31. El planner **no**
> edita ramas ni `feature_list.json`.

> **Dependencias.** Las cuatro features de `depends_on` están `accepted` y en la
> base. `api-contratos-openapi` (FT00029) es **necesaria** (contrato + `/v1` + test
> anti-deriva). `bootstrap-ktor-healthcheck` (FT00004) queda cubierta
> transitivamente (el esqueleto Ktor y `/health`). **No** se añaden FT00015/FT00017
> (ya cubiertas por FT00028/FT00031) ni FT00023 (cubierta por las features de API).

## Goal

Endurecer la **API pública de solo lectura** (tarea `0.5-T05`: «Rate limiting, CORS
y manejo de errores») antes de que se construya la UI (0.6.0), de modo que:

1. el futuro cliente **Web (Wasm)** pueda llamar a la API desde otro origen (CORS,
   incluido el *preflight* de `POST /v1/chat` con `Content-Type: application/json`);
2. el **abuso** —especialmente del **chat RAG**, que es lo más caro por consulta
   (`docs/risks-and-open-questions.md`: «Abuso del chat RAG … sin rate limiting
   puede agotar la cuota o degradar el servicio»)— quede **limitado por IP** con un
   cupo general para los endpoints de dominio y otro más estricto para `/v1/chat`;
3. cualquier error (`400`/`404`/`429`/`500`/`502`) devuelva un **cuerpo JSON
   consistente y tipado** (`ApiErrorDto`) en lugar de una respuesta sin cuerpo.

La feature añade **tres plugins oficiales de Ktor** (`CORS`, `RateLimit`,
`StatusPages`), su **configuración por entorno**, el **DTO de error** en `:shared`,
actualiza el **contrato OpenAPI 3.1** (esquema de error + `429`) y cubre todo con
tests de gate **sin red, sin BD, sin modelo y sin OpenCode**.

## Non-Goals

- **Autenticación/autorización y cuotas por usuario**: la API sigue **pública, sin
  cuentas ni datos personales**; el rate limiting es **por IP**, no por identidad.
- **Rate limiting distribuido o persistente** (Redis, tabla, contadores
  compartidos): **en memoria**, por instancia (el backend es un único proceso en el
  N100). El reparto entre instancias es una feature de escalado futura.
- **Presupuesto de tokens por consulta de chat** y control de coste del proveedor:
  el chat ya no expone `usage` (FT00031); aquí solo se limita la **frecuencia**.
- **Trust de cabeceras de proxy** (`X-Forwarded-For`/`Forwarded`) y topología
  Nginx: es despliegue (**FT00041**). Se documenta el riesgo, no se cablea.
- **Swagger UI / ReDoc** ni explorador interactivo del contrato.
- **Cambiar los contratos de dominio** de `:shared` (`PublicacionDto`,
  `ResumenDiarioDto`, `SearchResultsDto`, `Chat*Dto`…): se **reutilizan**; solo se
  **añade** el DTO de error.
- **Cambiar la semántica de los endpoints**: ni métodos, ni parámetros, ni códigos
  (los existentes se mantienen; solo cambia el **cuerpo** de los errores).
- **Cablear el pipeline de resumen o el indexado del corpus**: gaps ya registrados
  (Sessions 068/070).
- **Tocar `:composeApp`/CI/`init.sh`**, ni añadir migración (`V1`…`V5` intactas), ni
  modificar `rag/*`, `persistence/*`, los servicios de dominio ni los repositorios.

## Job Story

When un cliente (hoy el navegador de la futura Web Wasm, mañana móvil) llama a la
API pública desde otro origen,
I want que el servidor resuelva el CORS, me limite con un cupo razonable y me
devuelva errores JSON claros y estables,
so I can consumir la API sin bloqueos del navegador, sin que un abuso del chat
agote la cuota compartida, y pudiendo tratar los fallos con un contrato tipado.

## Users And Permissions

- **Ciudadanía (usuario final):** anónima, solo lectura; sin cuentas ni datos
  personales. CORS la habilita; el rate limiting la protege de terceros abusivos.
- **Cliente CMP (FT00032+):** consumidor de `/v1/…`; hoy solo lo necesita el target
  **Web (Wasm)** (el preflight CORS lo dispara el navegador). Android/iOS no lo
  requieren.
- **Operador/desarrollador:** arranca el backend (con o sin BD) y ajusta los
  límites/orígenes por variables de entorno; ejecuta el gate.
- Sin autenticación, sin autorización y sin escritura.

## Acceptance Scenarios

### Scenario 1: el *preflight* CORS del cliente se resuelve

Given el backend arrancado con CORS activo,
When el navegador envía `OPTIONS /v1/feed` (o `POST /v1/chat`) con `Origin` y
`Access-Control-Request-Method`,
Then responde `200` con `Access-Control-Allow-Origin`, `Access-Control-Allow-Methods`
(con el método pedido) y, si aplica, `Access-Control-Allow-Headers: Content-Type`
(para el JSON de `/v1/chat`), y la petición real posterior también incluye
`Access-Control-Allow-Origin`.

### Scenario 2: orígenes configurables por entorno

Given `CORS_ALLOWED_ORIGINS` **sin definir**,
When llega una petición con cualquier `Origin`,
Then se permite (API pública sin credenciales). Given `CORS_ALLOWED_ORIGINS` con una
lista de orígenes, Then solo se permite un `Origin` de la lista; uno fuera de la
lista **no** recibe `Access-Control-Allow-Origin`.

### Scenario 3: superar el límite devuelve 429

Given el backend con el límite general configurado (p. ej. `RATE_LIMIT_REQUESTS`),
When un mismo cliente (misma IP) supera el cupo en la ventana,
Then las peticiones dentro del cupo responden normal (con `X-RateLimit-*`) y las
que lo superan responden **`429`** con cabecera `Retry-After` y cuerpo
`ApiErrorDto` (`codigo = "demasiadas_peticiones"`).

### Scenario 4: el chat tiene un cupo más estricto que el resto

Given `CHAT_RATE_LIMIT_REQUESTS` < `RATE_LIMIT_REQUESTS`,
When se alternan peticiones a `/v1/feed` y `/v1/chat`,
Then `/v1/chat` agota su cupo antes que el general (es el endpoint más caro);
`/health` y `/openapi.json` **no** están limitados.

### Scenario 5: una petición inválida devuelve un JSON de error consistente

Given cualquier endpoint de dominio,
When la petición es inválida (`400`), el recurso no existe (`404`), se supera el
límite (`429`), falla la inferencia local (`500`) o falla el proveedor de texto
(`502`),
Then la respuesta tiene el `Content-Type` JSON y el cuerpo
`{"codigo":"…","mensaje":"…"}` con el token de [ApiErrorCodeDto] que corresponde al
estado, **sin** filtrar detalles internos.

### Scenario 6: arranque sin BD/modelo/clave intacto

Given un entorno sin `POSTGRES_PASSWORD` (o sin modelo/clave para `/v1/chat`),
When arranca el backend,
Then `/health` responde `200` (y CORS/errores operativos), `/openapi.json` responde
`200`; las rutas de dominio no registradas responden `404` **con el cuerpo de error
tipado**; con las dependencias presentes, `/v1/…` se registra como hasta ahora y el
rate limiting sigue activo.

### Scenario 7: el gate sigue sin red, BD, modelo ni OpenCode

Given el runner de CI sin PostgreSQL, sin Docker, sin el modelo E5 y sin
`OPENCODE_API_KEY`,
When se ejecuta `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew
detekt` o `.harness/init.sh`,
Then todo está en verde; CORS, rate limiting y errores se prueban con
`testApplication` y dobles deterministas (los *plugins* no abren sockets).

### Scenario 8: contrato OpenAPI alineado con el error tipado

Given el documento `openapi.json` y los DTOs de `:shared`,
When el test anti-deriva compara los esquemas documentados con los contratos,
Then `ApiErrorDto`/`ApiErrorCodeDto` figuran en el documento, sus propiedades y
tokens coinciden con los `@SerialName`, las respuestas de error (`400`/`404`/`429`/
`500`/`502`) referencian `ApiErrorDto`, `info.version` refleja el cambio aditivo y
una divergencia **falla** el test.

## Repository Research

### Files Inspected

- Rama `feat/ft00030-api-cors-ratelimit-errores` (`4c98087`) sobre
  `feat/ft00029-api-contratos-openapi` (`64042ee`, PR **#31** abierto); `main` ya
  contiene FT00026–FT00031. `git ls-remote` confirma el *claim* de FT00030.
- `backend/.../Application.kt` — composition root: `configureSerialization()`,
  `configureMonitoring()`, pool JDBC único, wiring condicional
  (embeddings/OpenCode) y `configureRouting(...)`; punto donde se instalan los
  plugins de endurecimiento.
- `backend/.../plugins/Routing.kt` — `configureRouting(feed, detail, search, chat)`
  con `/health` y `/openapi.json` en la raíz y las rutas de dominio bajo
  `route("/v1")`, registradas **solo** si su servicio no es `null`.
- `backend/.../plugins/Feed.kt` / `PublicationDetail.kt` / `Search.kt` / `Chat.kt` —
  rutas delgadas que responden `400`/`404`/`500`/`502` **sin cuerpo** (el contrato
  de error es FT00030). `Chat.kt` traduce `TextGenerationException`/
  `ChatGenerationException` → `502` y `EmbeddingException` → `500` con
  `call.respond(HttpStatusCode.X)` (sin cuerpo).
- `backend/.../plugins/OpenApi.kt` + `resources/openapi/openapi.json` — contrato
  OpenAPI 3.1 estático (`GET /openapi.json`), con los cuatro endpoints `/v1/…`,
  `/health` y `/openapi.json`; **sin** esquema de error; `info.version = "0.5.0"`;
  `description` dice explícitamente que error/CORS/rate limiting son FT00030.
- `backend/.../plugins/Serialization.kt` / `Health.kt` / `Monitoring.kt` —
  patrón `Application.configureX()` / `Route.xRoutes(dep)` con KDoc en castellano.
- `backend/src/test/.../plugins/{Feed,PublicationDetail,Search,Chat,OpenApiRoute,
  OpenApiContract}RouteTest.kt` — patrón `testApplication { application { … } }`;
  los caminos de error solo comprueban el **código** de estado (añadir cuerpo no
  los rompe). `ChatRouteTest` ya tiene dobles (`FakeTextGenerationProvider`,
  `FakeEmbeddingProvider`) que provocan `502`/`500`.
- `shared/src/commonMain/.../model/*.kt` — DTOs de wire con sufijo `Dto` y
  `@SerialName` explícito; enums de wire con tokens `snake_case`
  (`ChatStatusDto`, `CategoriaDto`); `DatoPublicoJson` (`ignoreUnknownKeys`,
  `encodeDefaults`).
- `gradle/libs.versions.toml` + `backend/build.gradle.kts` — Kotlin **2.1.20**,
  Ktor **3.0.3**, `:shared` ya dependencia, `ktor-server-test-host` en test; **sin**
  artefactos de CORS/RateLimit/StatusPages todavía.
- `backend/.../infra/AppConfig.kt` / `rag/embeddings/EmbeddingConfig.kt` /
  `rag/generation/OpenCodeConfig.kt` — patrón de configuración por entorno con
  `fromEnv(env = System.getenv())` y *fail-fast* con mensaje claro.
- Ktor (artefactos verificados en Maven Central a la versión fijada **3.0.3**):
  `io.ktor:ktor-server-cors`, `io.ktor:ktor-server-rate-limit` y
  `io.ktor:ktor-server-status-pages` existen. Inspeccionado el **código fuente** de
  los tres: `RateLimit` es un plugin **estable** en 3.0.3 (sin `@KtorExperimentalAPI`),
  con *token bucket* (`rateLimiter(limit, refillPeriod)`), `requestKey`, y
  `Route.rateLimit(RateLimitName)`; `StatusPages` expone `status(HttpStatusCode)`
  (la propia documentación de Ktor muestra `status(TooManyRequests)` para
  personalizar el cuerpo del `429`); el *preflight* de `CORS` responde `200`.
- Harness: `feature_list.json` (FT00030), `PROGRESS.md` (Sessions 066–072),
  `docs/feature-ids.md`, `docs/roadmap.md` §0.5 (`0.5-T05` y nota de riesgo del
  chat), `docs/technical-discovery.md`, `docs/risks-and-open-questions.md`,
  `CONTEXT.md`, `ARCHITECTURE.md`, `CONSTRAINTS.md` (§«API pública: …» y
  §«API pública: contratos y versionado»), ADR 0020–0025 y los specs
  `api-{feed-diario,detalle-norma,busqueda,chat,contratos-openapi}.md`; skill
  `feature-spec` y **`ktor-backend-architecture`** (§«Layout de paquetes» ya prevé
  `plugins/` con «CORS, rate limit … errors»; §«API» menciona CORS/rate limiting/
  errores JSON como FT00030).

### Existing Patterns To Follow

- **Ruta/plugin delgado en `plugins/`**: `fun Application.configureX()` (plugins) y
  `fun Route.xRoutes(dep)` (rutas), sin lógica de negocio.
- **Configuración por entorno en `infra/`** con `fromEnv(env)` y *fail-fast*; nada
  de secretos en el repositorio.
- **Registro condicional** de rutas y **arranque sin dependencias externas**
  (`/health` y `/openapi.json` siempre operativos).
- **Tests de gate con `testApplication`** y `DatoPublicoJson`, sin red/BD/modelo.
- **Estilo MUST**: identificadores en inglés (KDoc en castellano), un solo
  `return`, sin `else if`, funciones ≤40 líneas, `@SerialName` explícito en los DTO.
- **Contrato OpenAPI estático + test anti-deriva** (FT00029): el documento es la
  fuente de verdad y se actualiza a mano; el test falla si diverge de los DTOs.

### Current Gaps

- **No hay CORS**: el *preflight* del navegador (Web Wasm futura) fallaría y
  `POST /v1/chat` con `Content-Type: application/json` no se resolvería.
- **No hay rate limiting**: el chat (lo más caro) puede agotar la cuota de OpenCode
  (riesgo explícito en `risks-and-open-questions.md`).
- **No hay cuerpo de error tipado**: los errores responden sin cuerpo
  (`400`/`404`/`429`/`500`/`502`), lo que impide un contrato de error estable para
  los clientes.
- **No existe** ningún DTO de error en `:shared` ni esquema de error en el OpenAPI.
- **No hay** dependencias Gradle de `ktor-server-cors`/`-rate-limit`/
  `-status-pages` (se añaden en esta feature).

## Technical Approach

Deriva de `docs/roadmap.md` 0.5-T05 («Rate limiting, CORS y manejo de errores»),
`docs/risks-and-open-questions.md` (abuso del chat RAG, límites de uso y coste) y
`CONSTRAINTS.md`. La decisión durable se fija en un **ADR 0026**.

### Evaluación de dependencias (decisión clave)

Se **añaden tres artefactos oficiales de Ktor**, todos disponibles a la versión
fijada **3.0.3** (verificado en Maven Central) y **estables** (sin opt-in
experimental):

- `io.ktor:ktor-server-cors` — plugin `CORS` (resuelve el *preflight* y las
  cabeceras `Access-Control-*`; hacerlo a mano es propenso a errores).
- `io.ktor:ktor-server-rate-limit` — plugin `RateLimit` (*token bucket* por clave,
  cabeceras `X-RateLimit-*` y `Retry-After`; en 3.0.3 es **estable**).
- `io.ktor:ktor-server-status-pages` — plugin `StatusPages` (`status(...)` y
  `exception<Throwable>`), que **unifica el cuerpo de error** y personaliza el `429`
  del plugin de rate limiting (patrón que la propia documentación de Ktor propone).

Es una **excepción deliberada** a la pauta «sin dependencias Gradle nuevas» de
FT00026–FT00029/FT00031 (aquellas lo declaraban como MUST NOT **de su propia
feature**): implementar CORS correcto y un *rate limiter* robusto a mano sería más
código, más frágil y con más superficie de error. Los plugins son oficiales, de la
misma versión que el resto de Ktor y **no abren sockets ni servicios**: el gate
sigue **offline** (los tests usan `testApplication`). La primera resolución de
artefactos la hace Gradle como cualquier otra dependencia (igual que hoy con Ktor);
los **tests** no requieren red.

Alternativa descartada: implementar CORS/rate limiting/errores **sin dependencias**
(*scope* mayor, preflight y algoritmo de *bucket* a mano, más riesgo). Se documenta
en el ADR 0026.

### 1. DTO de error tipado (`:shared`, create)

- `shared/src/commonMain/.../model/ApiErrorDto.kt`:
  - `@Serializable data class ApiErrorDto(@SerialName("codigo") val code:
    ApiErrorCodeDto, @SerialName("mensaje") val message: String)`.
  - `@Serializable enum class ApiErrorCodeDto` con tokens `snake_case` (contrato de
    wire, como `ChatStatusDto`): `solicitud_invalida` (`400`), `no_encontrado`
    (`404`), `demasiadas_peticiones` (`429`), `error_interno` (`500`) y
    `servicio_no_disponible` (`502`).
- `@SerialName` explícito en cada propiedad y valor (regla MUST). **Sin** detalles
  internos ni trazas en el cuerpo.
- Vive en `:shared` porque es **contrato de transporte público** que el cliente
  consumirá y que el OpenAPI documenta (a diferencia de `HealthDto`, operacional,
  que vive en `:backend`).

### 2. Configuración por entorno (`infra/HttpHardeningConfig.kt`, create)

- `CorsSettings(allowedOrigins: List<String>)`:
  - `CORS_ALLOWED_ORIGINS` (lista separada por comas; vacío/ausente ⇒ lista vacía).
  - `default()` = lista vacía; `fromEnv(env)` parsea y normaliza (trim, sin vacíos).
- `RateLimitSettings(requests: Int, window: Duration, chatRequests: Int,
  chatWindow: Duration)`:
  - `RATE_LIMIT_REQUESTS` (default **60**), `RATE_LIMIT_WINDOW_SECONDS` (default
    **60**), `CHAT_RATE_LIMIT_REQUESTS` (default **6**), `CHAT_RATE_LIMIT_WINDOW_SECONDS`
    (default **60**). El chat es lo más caro ⇒ cupo más bajo.
  - `default()` y `fromEnv(env)`; *fail-fast* (`IllegalArgumentException`) si un
    valor no es entero o es `≤ 0`, con mensaje claro (patrón `AppConfig`).
- Todo en `infra/` (config, sin lógica Ktor).

### 3. CORS (`plugins/Cors.kt`, create)

- `fun Application.configureCors(settings: CorsSettings)` instala `CORS`:
  - métodos `GET`, `POST`, `OPTIONS`; `allowHeader(Content-Type)` y
    `allowNonSimpleContentTypes = true` (el JSON de `/v1/chat` dispara *preflight*);
    `allowCredentials = false` (no hay cookies ni sesión).
  - `allowedOrigins` vacío ⇒ `anyHost()` (API pública **sin credenciales**: no hay
    datos de usuario que proteger; habilita la Web Wasm sin conocer su origen aún).
  - `allowedOrigins` no vacío ⇒ `allowOrigins { origin -> origin in
    settings.allowedOrigins }` (allowlist estricta; el origen de producción se
    fijará en el despliegue FT00039).
- Se instala en `Application.module()` (afecta a todas las rutas, incluidas
  `/health` y `/openapi.json`).

### 4. Rate limiting (`plugins/RateLimiting.kt`, create)

- `object ApiRateLimiter { val GENERAL = RateLimitName("api"); val CHAT =
  RateLimitName("chat") }`.
- `fun Application.configureRateLimit(settings: RateLimitSettings)` instala
  `RateLimit` con dos limitadores nombrados, ambos con
  `requestKey { call -> call.request.origin.remoteHost }` (**por IP**):
  - `GENERAL`: `rateLimiter(settings.requests, settings.window)`.
  - `CHAT`: `rateLimiter(settings.chatRequests, settings.chatWindow)`.
- El plugin añade `X-RateLimit-Limit/Remaining/Reset` a las peticiones permitidas y
  `Retry-After` a las rechazadas (`429`).

### 5. Errores consistentes (`plugins/Errors.kt`, create)

- `fun Application.configureErrorHandling()` instala `StatusPages` y mapea los
  códigos a `ApiErrorDto` con mensajes genéricos en castellano (constantes):
  - `status(400)` → `solicitud_invalida`;
  - `status(404)` → `no_encontrado`;
  - `status(429)` → `demasiadas_peticiones` (**conservando** `Retry-After`);
  - `status(500)` → `error_interno`;
  - `status(502)` → `servicio_no_disponible`;
  - `exception<Throwable>` → registra el fallo **sin** volcar internos y responde
    `500` `error_interno` (relanza `CancellationException`).
- Así los `400`/`404` existentes (sin cuerpo) y los `500`/`502` que `Chat.kt` ya
  produce (sin cuerpo) pasan a llevar el cuerpo tipado **sin tocar las rutas**.
- Se instala en `Application.module()`. No cambia ningún **código** de estado.

### 6. Integración en routing (`plugins/Routing.kt`, modify)

- `configureRouting(...)` gana un parámetro **aditivo** `applyRateLimits: Boolean =
  false`. Con `true` (solo `Application.module()` y el test de rate limiting) las
  rutas de dominio se envuelven:
  - `rateLimit(ApiRateLimiter.GENERAL) { feedRoutes/publicationDetailRoutes/
    searchRoutes }` (si su servicio existe);
  - `if (chatService != null) rateLimit(ApiRateLimiter.CHAT) { chatRoutes(chatService) }`.
- Con `false` (valor por defecto, usado por los tests de ruta existentes) las rutas
  se registran como hoy, **sin** invocar `rateLimit(...)`. Es necesario porque
  `Route.rateLimit(...)` **falla en el arranque** si el plugin `RateLimit` no está
  instalado (comprobado en el código de Ktor 3.0.3), y así los tests `accepted`
  existentes **no** se tocan.
- `/health` y `/openapi.json` quedan **fuera** del rate limiting (operacionales:
  deben seguir accesibles para monitorización).

### 7. Composition root (`Application.kt`, modify)

- `Application.module()` instala, tras `configureSerialization()`/
  `configureMonitoring()`: `configureCors(CorsSettings.fromEnv())`,
  `configureErrorHandling()` y `configureRateLimit(RateLimitSettings.fromEnv())`;
  llama a `configureRouting(..., applyRateLimits = true)`.
- Ninguna de las tres depende de la BD, el modelo o la clave: se instalan
  **siempre** y el arranque parcial (solo salud) sigue funcionando.

### 8. Contrato OpenAPI (`resources/openapi/openapi.json`, modify)

- Añadir `components.schemas.ApiErrorDto` (propiedades `codigo`, `mensaje`) y
  `ApiErrorCodeDto` (enum con los cinco tokens) — espejo exacto de los DTOs.
- Añadir a cada operación de dominio las respuestas de error con
  `content.application/json.schema.$ref = ApiErrorDto` (`400`/`404` según aplique,
  `429` con cabecera `Retry-After`; `500`/`502` en `/v1/chat`), y actualizar la
  `description` (ya **no** dice que el error tipado/CORS/rate limiting están
  pendientes).
- **`info.version`**: cambio **aditivo y compatible** (nuevos esquemas y cuerpos de
  error, sin quitar nada) ⇒ según la política del ADR 0025, **sube** de `0.5.0` a
  **`0.5.1`** manteniendo `/v1`. (Alternativa del dueño: conservar `0.5.0` si se
  prefiere versionar por hito; ver *Risks*.)

### 9. Tests anti-deriva (modify) y nuevos

- `OpenApiContractTest`: añadir `ApiErrorDto` a `SCHEMA_SERIALIZERS` y
  `ApiErrorCodeDto` a `ENUM_SERIALIZERS` (para que el gate cubra el nuevo contrato).
- `OpenApiRouteTest`: actualizar el assert de `info.version` a `0.5.1` y comprobar
  que el esquema de error está documentado.

### Sin anticipar lo diferido

Sin autenticación, sin rate limiting distribuido/persistente, sin cuotas por
usuario, sin trust de proxy (`FT00041`), sin Swagger UI, sin UI (`FT00032+`), sin
migración, sin cambios en `:composeApp`/CI/`init.sh` ni en `rag/*`/`persistence/*`/
servicios.

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico` se abrevia `…`:

- `gradle/libs.versions.toml` — modify; tres artefactos Ktor
  (`ktor-server-cors`, `ktor-server-rate-limit`, `ktor-server-status-pages`).
- `backend/build.gradle.kts` — modify; cablear las tres dependencias.
- `shared/src/commonMain/…/model/ApiErrorDto.kt` — create; `ApiErrorDto` +
  `ApiErrorCodeDto`.
- `backend/src/main/kotlin/…/backend/infra/HttpHardeningConfig.kt` — create;
  `CorsSettings` + `RateLimitSettings`.
- `backend/src/main/kotlin/…/backend/plugins/Cors.kt` — create;
  `configureCors(settings)`.
- `backend/src/main/kotlin/…/backend/plugins/RateLimiting.kt` — create;
  `ApiRateLimiter` + `configureRateLimit(settings)`.
- `backend/src/main/kotlin/…/backend/plugins/Errors.kt` — create;
  `configureErrorHandling()`.
- `backend/src/main/kotlin/…/backend/plugins/Routing.kt` — modify; `applyRateLimits`
  y los *scopes* `rateLimit(...)`.
- `backend/src/main/kotlin/…/backend/Application.kt` — modify; instalar los tres
  plugins y pasar `applyRateLimits = true`.
- `backend/src/main/resources/openapi/openapi.json` — modify; esquema de error,
  respuestas de error, `info.version` `0.5.1`, `description`.
- `backend/src/test/kotlin/…/backend/infra/HttpHardeningConfigTest.kt` — create;
  defaults, overrides y *fail-fast*.
- `backend/src/test/kotlin/…/backend/plugins/CorsRouteTest.kt` — create; preflight y
  orígenes configurables.
- `backend/src/test/kotlin/…/backend/plugins/RateLimitRouteTest.kt` — create; `429`,
  cupo del chat más estricto y rutas operacionales sin límite.
- `backend/src/test/kotlin/…/backend/plugins/ErrorsRouteTest.kt` — create; cuerpo
  tipado para `400`/`404`/`429`/`500`/`502`.
- `backend/src/test/kotlin/…/backend/plugins/OpenApiContractTest.kt` — modify;
  esquemas de error en el anti-deriva.
- `backend/src/test/kotlin/…/backend/plugins/OpenApiRouteTest.kt` — modify;
  `info.version` y esquema de error.
- `shared/src/commonTest/kotlin/…/model/ErrorContractTest.kt` — create; serialización
  de `ApiErrorDto` (tokens y `@SerialName`).
- `docs/desarrollo-local.md` (producto) — modify; variables de entorno y `curl` de
  CORS/`429`/error tipado.

Harness (privado): `ARCHITECTURE.md`, `CONSTRAINTS.md` (nueva sección),
ADR `0026` + índice, skill `ktor-backend-architecture`, `PROGRESS.md`,
`feature_list.json` (ver *Durable Documentation Impact*).

Total ≈ **18 ficheros de producto/código**: muy por debajo del límite de 30 →
**no** requiere división en partes `FT00030-PTn`.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos.
- Design source: no aplica.
- Screens or states affected: ninguno (la UI consumidora es FT00032+).
- New design artifact required: no.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — la frontera «Cliente → API HTTP» incorpora CORS,
  rate limiting (por IP) y el **contrato de error tipado**; `:backend` gana
  `plugins/{Cors,RateLimiting,Errors}.kt` e `infra/HttpHardeningConfig.kt`, y tres
  dependencias Ktor nuevas.
- `CONSTRAINTS.md`: **update** — nueva sección **«API pública: endurecimiento HTTP»**:
  CORS configurable por entorno (público sin credenciales), rate limiting **por IP**
  en memoria (general + chat más estricto; `/health` y `/openapi.json` exentos), y
  **cuerpo de error tipado** `ApiErrorDto` para `400`/`404`/`429`/`500`/`502` con
  `@SerialName` explícito y sin filtrar internos; los tres plugins oficiales de Ktor
  a la versión fijada; **no** autenticación, **no** límites por usuario, **no**
  estado persistente.
- `AGENTS.md`: **not needed** — no cambia el flujo, el arranque ni las reglas.
- Other docs: `docs/adr/0026-endurecimiento-http-cors-ratelimit-errores.md` —
  **create** (plugins oficiales, CORS por entorno, rate limiting por IP en memoria,
  error tipado, política de `info.version`) + índice `docs/adr/README.md`;
  `.agents/skills/ktor-backend-architecture/SKILL.md` — **update** (§«API» y §«Estado
  actual»: CORS/rate limiting/errores implementados); `docs/desarrollo-local.md` —
  **update**.

## Implementation Plan

1. Añadir los tres artefactos Ktor a `libs.versions.toml` y `backend/build.gradle.kts`.
2. Crear `ApiErrorDto`/`ApiErrorCodeDto` en `:shared` y su `ErrorContractTest`.
3. Crear `infra/HttpHardeningConfig.kt` (`CorsSettings`, `RateLimitSettings`) y su
   test.
4. Crear `plugins/Cors.kt`, `plugins/RateLimiting.kt` y `plugins/Errors.kt`;
   integrarlos en `Application.kt` y añadir `applyRateLimits` en `Routing.kt`.
5. Crear `CorsRouteTest`, `RateLimitRouteTest` y `ErrorsRouteTest` (gate con
   `testApplication`, dobles deterministas y límites pequeños).
6. Actualizar `openapi.json` (esquema de error + respuestas + `info.version`) y los
   tests `OpenApiContractTest`/`OpenApiRouteTest`.
7. Pasar el gate sin red/BD/modelo/OpenCode; actualizar `ARCHITECTURE.md`,
   `CONSTRAINTS.md`, ADR 0026 + índice, la skill y `docs/desarrollo-local.md`;
   `PROGRESS.md`/`feature_list.json` los cierra el orquestador.

## Implementation Tasks

- [ ] `libs.versions.toml` + `backend/build.gradle.kts`: `ktor-server-cors`,
      `ktor-server-rate-limit`, `ktor-server-status-pages` (3.0.3).
- [ ] `:shared` `ApiErrorDto.kt` (`ApiErrorDto` + `ApiErrorCodeDto`) y
      `ErrorContractTest`.
- [ ] `infra/HttpHardeningConfig.kt` (`CorsSettings`, `RateLimitSettings`) y
      `HttpHardeningConfigTest`.
- [ ] `plugins/Cors.kt`, `plugins/RateLimiting.kt`, `plugins/Errors.kt`.
- [ ] `Application.kt` (instalar los tres) y `Routing.kt` (`applyRateLimits` +
      *scopes*).
- [ ] `CorsRouteTest`, `RateLimitRouteTest`, `ErrorsRouteTest`.
- [ ] `openapi.json` (esquema de error, respuestas, `info.version` `0.5.1`) y
      `OpenApiContractTest`/`OpenApiRouteTest`.
- [ ] Docs: `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0026 + índice, skill,
      `docs/desarrollo-local.md`.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Gate sin red, BD, modelo ni OpenCode (obligatorio)**: `./gradlew :backend:test
  --rerun-tasks` y `./gradlew :shared:jvmTest` → BUILD SUCCESSFUL con los tests
  nuevos en verde (0 fallos) y el resto **intacto**; `./gradlew build --no-daemon
  -PskipClient` (incluye `detekt` + `:cpdCheck`), `./gradlew test`, `./gradlew
  detekt` y `env -u JAVA_HOME .harness/init.sh` → exit 0.
- **CORS (gate)**: `CorsRouteTest` comprueba el *preflight* `OPTIONS /v1/feed` y
  `OPTIONS /v1/chat` (`Access-Control-Allow-Origin/Methods/Headers`) y que la
  petición real incluye `Access-Control-Allow-Origin`; con `CORS_ALLOWED_ORIGINS`
  fijado, un origen fuera de la lista no se permite.
- **Rate limiting (gate)**: `RateLimitRouteTest` con límites pequeños
  (`RateLimitSettings`) comprueba que superar el cupo devuelve `429` +
  `Retry-After` + cuerpo `demasiadas_peticiones`; que `/v1/chat` agota antes que el
  general; y que `/health`/`/openapi.json` **no** se limitan.
- **Errores (gate)**: `ErrorsRouteTest` comprueba `ApiErrorDto` en
  `400`/`404`/`429`/`500`/`502` (dobles de chat que lanzan `EmbeddingException` →
  `500` y `TextGenerationException` → `502`) y que **no** se filtran internos.
- **Contrato (gate)**: `OpenApiContractTest` verifica el esquema de error contra los
  `@SerialName`; `OpenApiRouteTest` verifica `info.version = "0.5.1"` y la presencia
  del esquema; `GET /openapi.json` sigue `200` `application/json`.
- **Arranque sin BD/modelo/clave**: `./gradlew :backend:run` sin
  `POSTGRES_PASSWORD` → `/health` `200`, `/openapi.json` `200`, `/v1/feed`/`/v1/chat`
  `404` **con cuerpo de error tipado**; con dependencias, `/v1/…` responde y el
  rate limiting aplica.
- **Dependencias**: comprobar que `libs.versions.toml`/`backend/build.gradle.kts`
  **solo** añaden los tres artefactos Ktor; `git diff` sin migraciones
  (`V1`…`V5` intactas) ni `:composeApp`/CI/`init.sh`.
- **E2E**: no aplica — el repo no tiene comando E2E persistente (el cliente CMP aún
  no consume `:shared`); el flujo HTTP se cubre con `testApplication` en el gate.
- `init.sh` (harness): **no** se modifica.

## Evidence To Capture

- Salida de los tests nuevos y del gate (`build -PskipClient`, `test`, `detekt`,
  `init.sh` exit 0) con recuento y 0 fallos.
- Ejemplo real de *preflight* CORS (`curl -X OPTIONS`), de un `429` con
  `Retry-After` y de un error tipado (`400`/`404`) sobre `:backend:run`.
- Confirmación de que `libs.versions.toml`/`backend/build.gradle.kts` solo añaden los
  tres artefactos Ktor y de que las migraciones `V1`…`V5` quedan intactas.
- Ficheros del commit `FT00030`, PR (base apilada `feat/ft00029-api-contratos-openapi`)
  y run de CI; entradas en `PROGRESS.md` y `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo CORS, rate limiting y error tipado (+ contrato OpenAPI y
      docs); **sin** autenticación, **sin** rate limiting distribuido/persistente,
      **sin** cuotas por usuario, **sin** proxy/forwarded headers, **sin** Swagger
      UI, **sin** UI, **sin** migración, **sin** cambios en los DTOs de dominio,
      servicios, `rag/*` o `persistence/*`.
- [ ] Escenarios 1–8 pasan; **todo el gate corre sin red, BD, modelo ni OpenCode**.
- [ ] Un *preflight* CORS del cliente se resuelve; superar el límite devuelve `429`
      (con `Retry-After`); una petición inválida devuelve el JSON de error
      consistente (`ApiErrorDto`).
- [ ] El rate limiting es **por IP**, general para `/v1/…` y **más estricto** para
      `/v1/chat`; `/health` y `/openapi.json` **no** están limitados; es **en
      memoria** (documentado).
- [ ] Los **tres** artefactos Ktor nuevos son los únicos cambios de dependencias y
      están a la versión fijada (3.0.3); no hay generación en compilación.
- [ ] El **test anti-deriva** cubre `ApiErrorDto`/`ApiErrorCodeDto` y falla ante
      divergencia; `info.version` refleja el cambio aditivo.
- [ ] El arranque **no** depende de la BD/modelo/clave (`/health` y
      `/openapi.json` operativos; rutas condicionales); los tests de ruta
      `accepted` existentes **no** se rompen (`applyRateLimits` por defecto `false`).
- [ ] DTOs con `@SerialName` explícito; identificadores en inglés y KDoc en
      castellano; un solo `return`, sin `else if`, funciones ≤40 líneas; sin
      secretos ni datos personales; sin filtrar internos en el error.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR 0026 + índice, skill,
      `docs/desarrollo-local.md`, `PROGRESS.md` y `feature_list.json` actualizados.
- [ ] Sin comportamiento de producto no relacionado ni ficheros fuera de alcance.

## Risks / Open Questions

- **PR apilado (bloqueante de proceso, no de planificación).** La rama de FT00030
  tiene base `feat/ft00029-api-contratos-openapi` (PR **#31**, sin fusionar). El PR
  de FT00030 se abrirá contra esa rama y se rebasará sobre `main` cuando se fusione
  #31; al rebasar, resolver conflictos **aditivos** en `Routing.kt`/`Application.kt`
  (colaboradores opcionales) y actualizar la descripción del PR.
- **`depends_on` incompleto.** Falta `api-contratos-openapi` (FT00029): la feature
  edita su contrato y su test anti-deriva. El **orquestador** debe añadirlo; el
  planner no edita `feature_list.json`.
- **Rate limiting por IP detrás de proxy.** En producción el backend irá tras Nginx
  (FT00041): sin `Forwarded`/`X-Forwarded-For`, `origin.remoteHost` será el proxy y
  **todos** los clientes compartirán un cupo. Se documenta como riesgo y se deja la
  configuración de cabeceras de proxy a FT00041 (fuera de alcance aquí).
- **Límites en memoria, por instancia.** Con varias instancias el cupo se multiplica;
  el N100 sirve un único proceso, así que es aceptable en la 1.0.0. Escalado
  horizontal ⇒ rate limiting compartido (feature futura).
- **Distribución de abuso.** Un atacante con muchas IPs no se frena con un límite
  por IP; es un *trade-off* consciente (sin cuentas ni identidad). El chat, lo más
  caro, lleva el cupo más bajo.
- **`info.version`.** El spec sube `0.5.0` → `0.5.1` por la política aditiva del
  ADR 0025; si el dueño prefiere versionar por hito (mantener `0.5.0` porque el
  hito 0.5.0 aún no se ha publicado), es un ajuste de una línea en el documento y
  en `OpenApiRouteTest` (decisión del dueño).
- **CORS permisivo por defecto (`anyHost()`).** Justificado por ser una API
  pública, de solo lectura y **sin credenciales** (no hay datos de usuario que
  proteger); el origen de producción se restringirá con `CORS_ALLOWED_ORIGINS` en
  FT00039. Si el dueño prefiere un default **estricto** (allowlist vacía ⇒ sin
  CORS), cambia el comportamiento de Scenario 2 pero el mecanismo es el mismo.
- **Nuevas dependencias Ktor.** Revierte la pauta «sin dependencias» de features
  previas; se justifica (plugins oficiales, versión fijada, gate offline) y se
  documenta en el ADR 0026. Requiere que Gradle resuelva los artefactos la primera
  vez (la CI ya resuelve dependencias; los tests no usan red).
- **Tests `accepted` que llaman a `configureRouting()`.** Se mantienen verdes
  porque `applyRateLimits` por defecto es `false` (no se invoca `rateLimit(...)` sin
  plugin). Si se optara por activar el rate limiting por defecto, habría que
  instalar el plugin en esos tests (churn mecánico) — se descarta.
- **División.** ≈18 ficheros: por debajo de 30 → **atómica**; no se recomienda
  partir en `FT00030-PTn`.
