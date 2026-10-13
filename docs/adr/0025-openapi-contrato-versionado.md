# ADR 0025: Contrato OpenAPI estático versionado, prefijo `/v1` en las rutas de dominio y test anti-deriva

## Estado

Aceptado (2026-10-13). Decisión del dueño del proyecto para FT00029
(`api-contratos-openapi`). Reutiliza los ADR 0021 (feed y pool único), 0022
(detalle y versionado del path diferido a FT00029), 0023 (búsqueda y wiring
condicional del proveedor de embeddings) y 0024 (chat y wiring condicional de
OpenCode); no supersede ninguno.

## Contexto

La 0.5.0 ya sirve los cuatro endpoints de datos (`/feed` FT00026,
`/publicacion/{id}` FT00027, `/buscar` FT00028 y `/chat` FT00031) pero **no**
publica ningún contrato ni fija una versión de API: el ADR 0022 difirió
explícitamente el versionado del path a FT00029. La tarea `0.5-T04` («Contratos
OpenAPI y versionado de API») exige que los clientes puedan consumir feed,
detalle, búsqueda y chat de forma estable antes de construir la UI (0.6.0).

Restricciones: el proyecto fija **Kotlin 2.1.20** y **Ktor 3.0.3**, y el
**compilador OpenAPI** de Ktor exige **Kotlin ≥ 2.2.20**; `ktor-server-openapi` y
`ktor-openapi-tools` solo **sirven/renderizan** un documento (no generan esquemas
desde los DTOs) y añaden artefactos y superficie. El gate y la CI corren **sin
red, sin base de datos, sin el modelo E5 y sin `OPENCODE_API_KEY`**; el arranque
debe funcionar en entornos parciales (solo salud). Es el **último momento barato**
para versionar el path (la UI 0.6.0 aún no existe) y **no** se deben cambiar los
contratos de dominio de `:shared` (los DTOs se reutilizan tal cual). Todo el
código en inglés con KDoc en castellano, un solo `return`, sin `else if` y
funciones ≤40 líneas. El contrato de error tipado, el CORS y el rate limiting son
FT00030.

## Decisión

- **Documento OpenAPI 3.1 estático y versionado en los recursos del backend**
  (`backend/src/main/resources/openapi/openapi.json`, ubicación ya prevista por la
  skill `ktor-backend-architecture`). **Sin** dependencia Gradle nueva y **sin**
  generación en tiempo de compilación: se descarta el compilador de Ktor (exigiría
  subir Kotlin a ≥ 2.2.20, *scope creep* y riesgo) y los artefactos que solo
  sirven una UI (Swagger UI/ReDoc quedan como feature futura opcional). El
  documento declara `openapi` 3.1.0, `info.title = "DatoPublico API"`,
  `info.version = "0.5.0"` (hito que agrupa los endpoints) y `servers = [{url: "/"}]`.
- **Ruta de solo lectura `GET /openapi.json`** (`plugins/OpenApi.kt`): carga el
  recurso **una sola vez** desde el classpath (*fail-fast* si falta) y lo sirve
  como `application/json`. No depende de la base de datos, el modelo ni OpenCode:
  se registra **siempre** y va **sin** versión (es meta/operacional y estable).
- **Versionado en el path**: los endpoints de **dominio** pasan a `/v1/…`
  (`/v1/feed`, `/v1/publicacion/{id}`, `/v1/buscar`, `/v1/chat`); `/health` y
  `/openapi.json` quedan **sin** prefijo. `configureRouting` anida las rutas de
  dominio bajo `route("/v1")` **reutilizando** `feedRoutes`/`publicationDetailRoutes`/
  `searchRoutes`/`chatRoutes` **sin** modificarlas; el versionado solo **prefija**,
  no cambia métodos, parámetros ni semántica. Una ruta de dominio sin `/v1`
  responde `404`. No se conservan aliases sin `/v1` (no hay clientes todavía).
- **El documento es la fuente de verdad del contrato** y los **DTOs `Dto` de
  `:shared` su implementación**. `components.schemas` es el espejo exacto de los
  DTOs de wire (`PublicacionDto`, `ResumenDto`, `PlazoDto`, `ResumenDiarioDto`,
  `HighlightDto`, `HighlightReasonDto`, `CategoriaDto`, `SeccionBoeDto`,
  `SearchResultsDto`, `ChatRequestDto`, `ChatResponseDto`, `ChatStatusDto`,
  `ChatCitationDto`) más el `HealthDto` operacional, con los **mismos nombres de
  propiedad** que sus `@SerialName` y los **mismos tokens** de enum. **Sin**
  esquema de error: los códigos (`400`/`404`/`500`/`502`) se documentan sin
  cuerpo tipado (FT00030).
- **Test anti-deriva obligatorio en el gate** (`OpenApiContractTest`): para cada
  esquema de objeto, el conjunto de claves documentadas debe coincidir con los
  `@SerialName` de su `serializer().descriptor.elementNames`, y para cada enum de
  wire, los valores documentados con sus tokens. Una divergencia (un DTO que
  cambia sin actualizar el documento) **falla** el test. `OpenApiRouteTest`
  comprueba además `200`, `application/json`, el JSON válido, `info.version` y las
  rutas documentadas. Todo con `testApplication`, sin red/BD/modelo/OpenCode.
- **Política de versionado** (durable): los cambios **aditivos y compatibles**
  mantienen `/v1` y suben la *minor/patch* de `info.version`; un cambio
  **incompatible** exige un prefijo nuevo (`/v2`) con `/v1` conservado hasta su
  deprecación.

## Alternativas consideradas

- **Compilador OpenAPI de Ktor (`ktor-server-openapi`) o `ktor-openapi-tools`.**
  Descartado: exige Kotlin ≥ 2.2.20 (el proyecto fija 2.1.20) y/o dependencias
  nuevas; además solo sirve/renderiza un documento, no genera esquemas desde los
  DTOs. Sería *scope creep* con riesgo para el gate.
- **Generar el documento en `build`/`check`.** Descartado: rompería la regla de
  que el gate corre sin servicios externos y añadiría una dependencia y un paso de
  build; el documento es un artefacto revisable en el repositorio.
- **Swagger UI/ReDoc interactivos.** Descartado: no los pide la verificación y
  añadirían artefactos y superficie; feature futura opcional.
- **Versionar también `/health` y `/openapi.json`.** Descartado: son
  operacionales/meta y deben ser estables; versionarlos obligaría a moverlos en
  cada cambio incompatible sin aportar nada.
- **No versionar el path (solo `info.version` + política).** Descartado: era la
  alternativa más pequeña, pero desaprovecha el último momento barato (la UI aún
  no existe) y el ADR 0022 ya difirió la decisión aquí; versionar ahora evita un
  cambio incompatible futuro.
- **Cambiar los DTOs de `:shared` para derivarlos del documento.** Descartado: los
  DTOs están congelados y son la implementación; el documento se espeja a mano y el
  test lo protege.
- **Documentar un esquema de error compartido.** Descartado: el contrato de error
  tipado es FT00030.

## Consecuencias

- **Habilita** que los clientes (CMP, 0.6.0) consuman la API de forma estable con
  una versión explícita y un contrato consultable (`GET /openapi.json`), y fija el
  mecanismo de versionado (`/v1` → `/v2`) antes de que existan clientes.
- **Cuesta** mantener el documento a mano: un cambio de DTO de `:shared` exige
  actualizar `openapi.json`; el **test anti-deriva** convierte ese olvido en un
  fallo del gate.
- **Toca tests de features `accepted`**: el prefijo `/v1` obliga a actualizar las
  URLs de `FeedRouteTest`/`PublicationDetailRouteTest`/`SearchRouteTest`/
  `ChatRouteTest` (y `ChatRouteLiveTest`). Es **mecánico y sancionado**: el ADR
  0022 difirió explícitamente el versionado del path a FT00029.
- **Sin migración** (`V1`…`V5` intactas), **sin** dependencias Gradle nuevas,
  **sin** cambios en los DTOs de `:shared` ni en los servicios/rutas de dominio
  (solo el prefijo) y **sin** tocar `:composeApp`/CI/`init.sh`.
- **Documentación/código**: `ARCHITECTURE.md`, `CONSTRAINTS.md` §«API pública:
  contratos y versionado», la skill `ktor-backend-architecture`,
  `docs/desarrollo-local.md` (producto) y este ADR.
- **Verificación**: `OpenApiRouteTest` y `OpenApiContractTest` en el gate con
  `testApplication`, sin red/BD/modelo/OpenCode; los tests de ruta de dominio usan
  `/v1/…` y `HealthTest` sigue con `/health`. No aplica E2E persistente.
