# FT00048 — Cliente HTTP del detalle de publicación

## Source Feature

- `id`: `cliente-http-detalle`
- `ft_id`: `FT00048` (registrado en `docs/feature-ids.md`)
- `parts`: none (atómica; 7 ficheros de producto)
- `area`: `cliente-cmp`
- `depends_on`: `api-detalle-norma` (FT00027), `ui-detalle` (FT00033)
- `status`: `in_progress` (al escribir este spec; entregada en `main` y pendiente de
  validación/aceptación)
- `source`: `feature_list.json` (petición directa del dueño, sesión 082)
- `delivered_in`: commit `21f7299` (PR #41), fusionado en `main` (sesión 083)

> **Spec retroactivo.** Escrito **después** de la entrega (commit `21f7299`, PR #41 ya
> fusionado en `main`) para cerrar la gobernanza: la feature se implementó como petición
> directa del dueño, sin spec previo. Describe el **contrato realmente entregado**, no
> planifica trabajo nuevo. El orquestador mantiene `feature_list.json`/`PROGRESS.md`.

## Goal

Sustituir el repositorio **en memoria** del detalle (`InMemoryDetailRepository`, con
solo dos identificadores de ejemplo) por el **cliente HTTP real** del cliente Compose
Multiplatform, de modo que al abrir una publicación desde el feed o la búsqueda se
muestre su **detalle real** (resumen, plazo, fuente oficial y aviso de IA) servido por
`GET /v1/publicacion/{id}` (FT00027).

## Non-Goals

- **Backend, contrato de `:shared` y migraciones**: intactos. Solo se toca la capa de
  datos del cliente y su cableado.
- **Caché offline del detalle**: no se añade (el feed sí la tiene desde FT00035).
- **UI del detalle** (`DetailScreen`/`DetailRoute`/estados): sin cambios de píxeles ni
  de `DetailUiState`; es FT00033.
- **Navegación**: sin cambios; el destino `detail/{publicationId}` ya existía
  (FT00034-PT1).
- **Búsqueda/chat/feed**: no se tocan sus repositorios ni clientes.
- **Reemplazar el repositorio en memoria**: se **conserva** para `@Preview` y tests.

## Acceptance Scenarios

Derivados de `feature_list.json.verification` y del comportamiento real entregado:

### Scenario 1: detalle real desde la API
Given el backend accesible con la publicación publicada,
When se abre su detalle (feed o búsqueda),
Then la app pide `GET {baseUrl}/v1/publicacion/{id}` y muestra el detalle real
(resumen con «¿Qué cambia?», «¿A quién afecta?» y cifras clave, plazo si aplica,
fuente oficial y aviso de IA).

### Scenario 2: `200` mapea el DTO al dominio
Given una respuesta `200` del contrato,
When el repositorio la procesa,
Then devuelve `DetailLoadResult.Success` con el `PublicationDetail` mapeado (id,
título, categoría, fecha, resumen, plazo, `officialSourceUrl` y `showsAiNotice`).

### Scenario 3: `404` es «no encontrada»
Given una publicación inexistente o con resumen no publicado,
When el servidor responde `404`,
Then el repositorio devuelve `DetailLoadResult.NotFound` (no es un fallo).

### Scenario 4: `5xx` y fallo de red son error
Given el servidor responde `500` (u otro no-2xx distinto de `404`) o falla la red,
When el repositorio procesa la respuesta,
Then devuelve `DetailLoadResult.Failure`; **nunca** propaga la excepción a la UI.

### Scenario 5: el `id` viaja en la ruta
Given una llamada `load("BOE-A-2026-21321")`,
When se construye la petición,
Then la URL es `{baseUrl}/v1/publicacion/BOE-A-2026-21321`.

### Scenario 6: la UI sigue funcionando sin red
Given el repositorio HTTP inyectado en el *composition root*,
When una `@Preview` o un test monta el grafo sin backend,
Then el valor por defecto `InMemoryDetailRepository` cubre esos casos y no se lanza
ninguna petición de red.

### Scenario 7: el gate sigue verde
Given el entorno de CI sin red ni BD,
When se ejecutan `:composeApp:detekt`, `:cpdCheck` y `:composeApp:jvmTest`,
Then todo queda en verde (5/5 del nuevo test) y `:shared`/`:backend`/CI/`init.sh`
no cambian.

## Delivered Changes (Expected File Changes)

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico` se abrevia `…`:

- `composeApp/src/commonMain/kotlin/…/feature/detail/data/remote/DetailPublicationDto.kt` — **create**; DTOs de wire (`DetailPublicationDto`, `DetailSummaryDto`) con `@SerialName` explícito.
- `composeApp/src/commonMain/kotlin/…/feature/detail/data/remote/DetailDtoMapper.kt` — **create**; mapeo **puro** del DTO a `PublicationDetail` (reutiliza `feed…toDomain`).
- `composeApp/src/commonMain/kotlin/…/feature/detail/data/remote/DetailApi.kt` — **create**; `GET {baseUrl}/v1/publicacion/{id}` sobre `HttpClient` común + `toApiResult`; fallo de transporte → `ApiFailure.Network`.
- `composeApp/src/commonMain/kotlin/…/feature/detail/data/HttpDetailRepository.kt` — **create**; implementa `DetailRepository`; `200`→`Success`, `404`→`NotFound`, resto→`Failure`.
- `composeApp/src/commonMain/kotlin/…/app/App.kt` — **modify**; construye `HttpDetailRepository(DetailApi(httpClient))` y lo inyecta en `AppNavHost`.
- `composeApp/src/commonMain/kotlin/…/app/AppNavHost.kt` — **modify**; nuevo parámetro `detailRepository: DetailRepository = InMemoryDetailRepository()` y se pasa a `detailDestination`.
- `composeApp/src/commonTest/kotlin/…/feature/detail/data/HttpDetailRepositoryTest.kt` — **create**; 5 tests con `MockEngine` (200/404/500/red/ruta).

## Technical Approach (real entregado)

- **Contrato consumido**: `GET {baseUrl}/v1/publicacion/{id}` (FT00027). DTO de wire
  con los tokens del contrato: `id`, `titulo`, `fechaPublicacion`, `categoria`
  (reutiliza `FeedCategoryDto`), `urlOficial`, `resumen?`
  (`queCambia`/`aQuienAfecta`/`cifrasClave`/`avisoIA`) y `plazo?` (reutiliza
  `FeedDeadlineDto`). Los campos de wire no usados por la pantalla (`organismo`,
  `seccion`, `epigrafe`, `fuenteOficial`) se **ignoran** en el DTO del cliente.
- **Capa anti-corrupción**: el DTO del cliente **replica** el subconjunto del contrato
  (no cablea `:shared`, coherente con FT00035/ADR 0028).
- **Mapeo puro** (`DetailDtoMapper`): compone `PublicationDetail` con `CitizenSummary`
  y `Deadline`; `officialSourceUrl = officialUrl`; `showsAiNotice = resumen.avisoIA`
  (por defecto `true`). **No lanza**: campos ausentes usan valores seguros.
- **Traducción tipada**: `HttpDetailRepository` convierte `ApiResult` en
  `DetailLoadResult`; `ApiFailure.Server(status = 404)` ⇒ `NotFound`, cualquier otro
  fallo ⇒ `Failure`. `CancellationException` se re-lanza en `DetailApi`.
- **Wiring manual (sin DI)**: `App()` es el *composition root*; `AppNavHost` recibe el
  repositorio con valor por defecto en memoria para `@Preview`/tests.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — la sección de `:composeApp` debe reflejar que el
  detalle ya **no** lee de un repositorio en memoria en runtime: `feature/detail/data/`
  gana `DetailApi`/`HttpDetailRepository`/DTOs de wire sobre `core/network` (FT00048),
  y el *composition root* inyecta el HTTP (el en memoria queda para `@Preview`/tests).
  Hoy el documento solo describe FT00033/FT00035 y **no** menciona FT00048.
- `CONSTRAINTS.md`: **not needed** — no introduce ninguna regla MUST nueva (el cliente
  HTTP común, los errores tipados y la capa anti-corrupción ya son reglas de
  FT00035/ADR 0028/0029).
- `AGENTS.md`: **not needed** — no cambia el flujo, el arranque ni la verificación.
- Other docs: `docs/desarrollo-local.md` (producto) — **update menor** (anotar que la
  pantalla de detalle consume `GET /v1/publicacion/{id}` vía HTTP); ADR — **not needed**
  (decisión ya cubierta por ADR 0028/0029).

## Verification Plan

Desde la raíz del producto (`..`, JDK 21; Android SDK para el cliente):

- **Gate del cliente**: `./gradlew :composeApp:detekt` y `./gradlew :cpdCheck` → verde.
- **Tests (sin red)**: `./gradlew :composeApp:jvmTest` →
  `HttpDetailRepositoryTest` **5/5** (200 mapea; 404 → no encontrada; 500 → error;
  red → error; el `id` viaja en la ruta), resto intacto.
- **Gate completo (opt-in)**: `.harness/init.sh --with-client` → exit 0.
- **Manual (emulador)**: con el backend en `:8080` y datos, abrir una publicación real
  y comprobar resumen, plazo, fuente oficial y aviso de IA (evidencia registrada en
  `PROGRESS.md`, sesión 083).
- **E2E**: no aplica — el repo no tiene comando E2E persistente para el cliente; la
  cobertura es unitaria/integración con `MockEngine`.

## Evidence To Capture

- Salida de `:composeApp:jvmTest` (5/5 del nuevo test), `:composeApp:detekt` y
  `:cpdCheck` en verde; `.harness/init.sh --with-client` OK.
- Ficheros del commit `21f7299`, PR #41 y confirmación de fusión en `main` (sesión 083).
- Comprobación manual del detalle real en el emulador.

## Validator Checklist

- [ ] El detalle se sirve por HTTP (`GET /v1/publicacion/{id}`) y no por el repositorio
      en memoria en runtime; el en memoria queda para `@Preview`/tests.
- [ ] `200`→`Success`, `404`→`NotFound`, `5xx`/red→`Failure`; sin excepciones hacia la UI.
- [ ] DTOs con `@SerialName` explícito y sufijo `Dto`; mapeo puro sin `throw`.
- [ ] Sin cambios en `:shared`/`:backend`/CI/`init.sh`/`DESIGN.md`/`DetailScreen`.
- [ ] Gate del cliente verde; `ARCHITECTURE.md` actualizado; ≤30 ficheros en el PR.

## Risks / Open Questions

- **Referencias `FT00035` en el código nuevo.** El KDoc de `DetailApi`,
  `HttpDetailRepository`, `DetailDtoMapper` y `DetailPublicationDto` cita **FT00035**
  (la feature del cliente HTTP común) en lugar de FT00048; es una inconsistencia de
  trazabilidad del comentario, no de comportamiento. Decidir si se corrige a FT00048.
- **Sin caché offline del detalle.** A diferencia del feed (FT00035), un fallo de red
  en el detalle muestra el estado de error; no hay respaldo cacheado.
- **`fechaPublicacion` como cadena ISO-8601.** No se valida ni se formatea en el
  cliente (coherente con FT00032/FT00035); un valor no-ISO se pinta tal cual.
- **Contrato de error.** Un `404` sin cuerpo tipado se trata como `NotFound`; el
  `ApiFailure.Server.code` puede ser `null`. El contrato de error es FT00030.
