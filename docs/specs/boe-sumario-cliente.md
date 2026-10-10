# Feature Implementation Spec: Cliente del sumario diario del BOE

## Source Feature

- `id`: boe-sumario-cliente
- `ft_id`: FT00006
- `parts`: none (atomic — 1 integración + 1 modelo + tests)
- `area`: ingesta-boe
- `depends_on`: bootstrap-shared-dtos (FT00002, `accepted`), bootstrap-ktor-healthcheck (FT00004, `accepted`)
- `status`: accepted (implementada y validada; rama `feat/ft00006-boe-sumario-cliente`, claim `03b00b8`; ver `docs/validations/boe-sumario-cliente.md`)
- `source`: `feature_list.json`

## Goal

Añadir en `:backend` un **cliente de la API de datos abiertos del BOE** que, dada
una fecha, obtiene el **sumario diario** y devuelve las **entradas** de las
Secciones **I, II.A, II.B, III y V.B** (excluyendo IV y V.A). Es la base de
`docs/roadmap.md` 0.2-T01: el parser de publicaciones (FT00007), la persistencia
(FT00008) y el job diario (FT00009) consumirán estas entradas.

El cliente **no** persiste, **no** clasifica, **no** descarga el texto completo y
**no** se cablea en el arranque del servidor: es una librería de `:backend` con
sus tests, lista para ser invocada por features posteriores.

## Non-Goals

- **Parser de publicaciones** (`PublicacionDto`, metadatos completos, descarga de
  texto, URL oficial final) → FT00007.
- **Categorización / plazos** (`CategoriaDto`, `PlazoDto`) → FT00012.
- **Persistencia** (tablas, repositorios, Flyway) → FT00008; **ninguna BD** aquí.
- **Job programado**, reintentos, backoff, segunda pasada y backfill → FT00009/FT00011.
- **Endpoint HTTP** que exponga el sumario: no es una API pública → FT00026+.
- **Observabilidad/alertas de ingesta** → FT00010.
- **Secciones IV (Justicia) y V.A (licitaciones)**: excluidas (MUST en `CONSTRAINTS.md`).
- **Formato XML** del sumario y **caché** de respuestas: fuera de alcance (se usa JSON).

## Job Story

Cuando implemento la ingesta del BOE,
quiero obtener de una sola llamada las entradas del sumario de un día para las
secciones del corpus,
para construir las publicaciones con metadatos fiables sin reinterpretar la
respuesta cruda de la fuente en cada feature.

## Users And Permissions

- Desarrollador / job de ingesta (interno): invoca el cliente desde código de
  `:backend`. Sin cuentas, sin datos personales, sin autenticación (API pública
  de solo lectura; no requiere clave).

## Acceptance Scenarios

### Scenario 1: parseo de un fixture real (secciones objetivo)

Given un fixture real del sumario del BOE en JSON (`200`),
When el cliente lo procesa,
Then devuelve las entradas de las Secciones **I, II.A, II.B, III y V.B** con
identificador, título, control, fecha, organismo, epígrafe y URLs, y **no**
devuelve ninguna entrada de la Sección **V.A** (ni de la **IV**).

### Scenario 2: `item` como objeto o como array

Given dos fixtures reales, uno con `epigrafe.item` como **objeto** y otro con
`epigrafe.item` como **array**,
When el cliente los procesa,
Then ambos se parsean sin error y producen la misma forma de entradas (el
serializador tolera objeto único o lista).

### Scenario 3: día sin publicación

Given una fecha sin BOE (p. ej. domingo), en la que la API responde `404`,
When el cliente la consulta,
Then devuelve una **lista vacía** (sin excepción), documentándolo como "ese día
no hay sumario".

### Scenario 4: fecha y cabecera correctas

Given una fecha `LocalDate`,
When el cliente construye la petición,
Then llama a `GET {base}/boe/sumario/{YYYYMMDD}` con cabecera
`Accept: application/json`.

### Scenario 5: error de la fuente

Given un error de red o una respuesta HTTP distinta de `200`/`404`,
When el cliente procesa la respuesta,
Then lanza una excepción tipada con mensaje claro (fecha y estado/causa), sin
devolver datos parciales silenciosos.

### Scenario 6: llamada a la API real (opt-in, manual)

Given conectividad y `BOE_LIVE_TEST=1`,
When se ejecuta el test opt-in contra
`https://www.boe.es/datosabiertos/api/boe/sumario/<fecha-laborable>`,
Then la respuesta es `200` y devuelve **entradas no vacías** de las secciones
objetivo. **Fuera del gate y de la CI** (ver *Verification Plan*).

## Repository Research

### Files Inspected

- `.harness/feature_list.json` (FT00006), `PROGRESS.md`, `docs/feature-ids.md` —
  FT00002/FT00004 `accepted`; FT00006 `not_started`, rama ya reclamada.
- `.harness/docs/roadmap.md` §0.2.0 (`0.2-T01`) y
  `docs/technical-discovery.md` (BOE: sumario diario, secciones, fixtures reales).
- `.harness/docs/domain-model.md` (Sección/Epígrafe, Fuente oficial), `CONTEXT.md`,
  `ARCHITECTURE.md`, `CONSTRAINTS.md` (secciones excluidas, gate sin servicios
  externos, sin credenciales versionadas, fail-fast) y skill
  `ktor-backend-architecture` (layout `ingesta/`, regla de dependencia, wiring
  condicional, tests con fixtures reales).
- Producto `..`: `backend/build.gradle.kts` (Kotlin JVM, `kotlin.serialization`,
  `application`+`io.ktor.plugin`, `ktor-server-*`, logback; Flyway fuera de
  `build`/`check`), `Application.kt`, `infra/AppConfig.kt`, `plugins/*`,
  `backend/src/test/.../{SmokeTest,AppConfigTest,HealthTest}.kt`,
  `gradle/libs.versions.toml`, `shared/` (`SeccionBoeDto`, `DatoPublicoJson`).
- API real (comprobada con `fetch`): `GET /boe/sumario/{YYYYMMDD}` con
  `Accept: application/json` → `200` sobre JSON
  `{status{code,text},data{sumario{metadatos,diario[]}}}`; `404` → día sin
  publicación (cuerpo XML); `400` → fecha mal formada.

### Existing Patterns To Follow

- Feature-first en `:backend` (`ingesta/…`), sin framework de DI; colaboradores
  por constructor y cableado (si procede) en `Application.kt`.
- Clientes que encapsulan HTTP y traducen a modelos de dominio internos; el
  dominio no conoce Ktor ni HTTP.
- Tipos `@Serializable` **de transporte** llevan sufijo `Dto` (precedente
  `HealthDto` en `:backend`).
- Tests kotlin.test en espejo del paquete de producción; fixtures reales en
  `backend/src/test/resources/`; el gate (`./gradlew build`, `.harness/init.sh`)
  **no** depende de servicios externos.
- Reutilizar `DatoPublicoJson` de `:shared` como config JSON del cliente.

### Current Gaps

- No existe el paquete `ingesta/` ni ningún cliente HTTP de salida.
- El catálogo no tiene motor de cliente Ktor (`ktor-client-cio`) ni
  `ktor-client-mock`; `:backend` solo declara dependencias de servidor.
- No hay directorio de fixtures ni convención de tests de red.

## Technical Approach

1. **Catálogo y build** (`gradle/libs.versions.toml`, `backend/build.gradle.kts`):
   añadir aliases `ktor-client-cio` y `ktor-client-mock` (version.ref `ktor`); en
   `:backend`, `implementation` de `ktor-client-core`, `ktor-client-cio`,
   `ktor-client-content-negotiation` (`ktor-serialization-kotlinx-json` ya está)
   y `testImplementation` de `ktor-client-mock` y `kotlinx-coroutines-test`.
   **Sin** tocar Flyway, `:shared` ni la raíz.
2. **Modelo de wire** (`ingesta/sumario/SumarioWireDto.kt`, `@Serializable` con
   `@SerialName` para las claves del BOE: `fecha_publicacion`, `sumario_diario`,
   `url_html`, `url_xml`, `url_pdf`…): `BoeSumarioResponseDto`, `…DataDto`,
   `…Dto`, `…DiarioDto`, `…SeccionDto`, `…DepartamentoDto`, `…EpigrafeDto`,
   `…ItemDto`. Campos opcionales con defaults y tolerancia a claves desconocidas.
3. **Serializador «objeto o array»** (`ingesta/sumario/SingleOrArraySerializer.kt`):
   `item` puede ser objeto o lista (comprobado: `20261009` objeto, `20240102`
   array). Serializador de `List<BoeSumarioItemDto>` que acepta ambas formas; se
   aplica también a `epigrafe`/`departamento`/`seccion` si un fixture lo exige.
4. **Modelo interno** (`ingesta/sumario/EntradaSumario.kt`, data class **sin**
   serialización ni sufijo `Dto`): `identificador`, `control`, `titulo`,
   `fechaPublicacion` (ISO-8601 `String`, coherente con `PublicacionDto`),
   `seccion: SeccionBoeDto`, `organismo: String?`, `epigrafe: String?`,
   `urlOficial: String` (HTML `txt.php?id=…`), `urlXml: String?` (para FT00007).
5. **Cliente** (`ingesta/sumario/BoeSumarioClient.kt` +
   `BoeSumarioHttpClient.kt`): interfaz
   `BoeSumarioClient { suspend fun obtenerSumario(fecha: LocalDate): List<EntradaSumario> }`.
   Implementación con `HttpClient` **inyectado** y
   `baseUrl = "https://www.boe.es/datosabiertos/api"`; pide
   `GET {base}/boe/sumario/{BASIC_ISO_DATE}` con `Accept: application/json` y
   `expectSuccess = false`. **Filtro** por `codigo`: `1→I`, `2A→II_A`, `2B→II_B`,
   `3→III`, `5B→V_B`; `4` y `5A` se descartan. `404` → lista vacía; otro estado o
   fallo de red → `BoeSumarioException` (tipada). Factory
   `boeSumarioHttpClient(baseUrl: String): HttpClient` (CIO + `ContentNegotiation`
   con `DatoPublicoJson`).
6. **Sin wiring en el arranque:** `Application.kt` **no** crea ni invoca el
   cliente (no hay endpoint que lo use); el startup sigue sin llamadas externas.
   El cableado llegará con FT00007/FT00009.

**Riesgos clave:** (a) `item` objeto/array es la trampa principal — serializador
propio + dos fixtures; (b) estructura irregular de II.A/II.B/III/V.B (campos
ausentes) — nullable + `ignoreUnknownKeys`; (c) la API exige
`Accept: application/json` (sin ella devuelve `400`); (d) los festivos devuelven
`404` con cuerpo XML — no debe romper el parseo.

## Expected File Changes

Rutas en el repo de producto (`..`):

- `gradle/libs.versions.toml` — modify; aliases `ktor-client-cio`, `ktor-client-mock`.
- `backend/build.gradle.kts` — modify; dependencias de cliente Ktor y de test;
  Flyway/`application`/servidor intactos.
- `backend/src/main/kotlin/es/aviferdev/datopublico/backend/ingesta/sumario/{SumarioWireDto,SingleOrArraySerializer,EntradaSumario,BoeSumarioClient,BoeSumarioHttpClient}.kt` — create.
- `backend/src/test/kotlin/es/aviferdev/datopublico/backend/ingesta/sumario/{BoeSumarioClientTest,SumarioParsingTest,BoeSumarioLiveTest}.kt` — create.
- `backend/src/test/resources/boe/sumario-20261009.json` — create (fixture real, `item` objeto; incluye `5A`).
- `backend/src/test/resources/boe/sumario-20240102.json` — create (fixture real, `item` array).
- `docs/desarrollo-local.md` — update (opcional, ligero): endpoint del BOE y check opt-in.

No se toca la raíz del build, `:shared`, `:composeApp`, `.github/workflows/ci.yml`,
`Application.kt` ni las migraciones Flyway.

## Visual Design Impact

- UI involved: no. Sin pantallas, tokens ni textos de UI.

## Durable Documentation Impact

- `ARCHITECTURE.md` (harness): update — añadir la integración externa
  **Backend → BOE (API de datos abiertos, solo lectura)** en §Fronteras y anotar
  que `ingesta/` empieza a existir.
- `CONSTRAINTS.md`: update — MUST durable: los tests del gate no hacen **llamadas
  de red**; las pruebas contra servicios externos (BOE) son **opt-in** y quedan
  fuera de `./gradlew build`/`init.sh`/CI.
- `AGENTS.md` (harness): not needed — no cambia flujo, arranque ni reglas de repo.
- Otros: `docs/desarrollo-local.md` (producto) — update ligero; `README.md`/
  `ROADMAP.md` — not needed.

## Implementation Plan

1. Añadir al catálogo `ktor-client-cio`/`ktor-client-mock` y las dependencias de
   cliente en `:backend`.
2. Definir los wire DTOs `@Serializable` del sobre del BOE.
3. Implementar el serializador «objeto o array» para `item`.
4. Crear `EntradaSumario` y el cliente (interfaz + implementación Ktor + factory),
   con filtro de secciones y manejo de `404`/errores.
5. Capturar dos fixtures reales (objeto y array) y escribir los tests con
   `MockEngine`; añadir el test opt-in contra la API real.
6. Verificar `:backend:test` y el gate sin red; actualizar
   `ARCHITECTURE.md`/`CONSTRAINTS.md`/`docs/desarrollo-local.md`, `PROGRESS.md` y
   `feature_list.json`; commit/push/PR (CI) los gestiona el orquestador.

## Implementation Tasks

- [ ] Catálogo: aliases `ktor-client-cio` y `ktor-client-mock`.
- [ ] `:backend`: dependencias de cliente Ktor (core/cio/content-negotiation) y de
      test (mock, coroutines-test).
- [ ] Wire DTOs del sobre del sumario (`@SerialName`, campos opcionales).
- [ ] Serializador `item` objeto/array (y defensivo para contenedores).
- [ ] `EntradaSumario` (identificador, control, título, fecha, sección, organismo,
      epígrafe, `urlOficial`, `urlXml`).
- [ ] `BoeSumarioClient` + `BoeSumarioHttpClient` + factory; filtro `1/2A/2B/3/5B`,
      exclusión `4`/`5A`, `404`→vacío, error tipado.
- [ ] Fixtures reales `20261009` (objeto) y `20240102` (array).
- [ ] Tests con `MockEngine`: parseo, filtrado, `item` objeto/array, `404`, error.
- [ ] Test opt-in `BoeSumarioLiveTest` (env-gated) fuera del gate.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, `docs/desarrollo-local.md`,
      `PROGRESS.md` y `feature_list.json` actualizados.

## Verification Plan

Desde la raíz del producto (`..`, JDK 21 vía JBR/`JAVA_HOME`):

- **Fixtures (verificación 1, en el gate):**
  `./gradlew :backend:test --rerun-tasks` → BUILD SUCCESSFUL, XML sin
  failures/errors. `BoeSumarioClientTest`/`SumarioParsingTest` con `MockEngine`
  (sin red) comprueban: entradas de I/II.A/II.B/III/V.B, exclusión de V.A, parseo
  de `item` objeto y array, `404`→lista vacía y error no-2xx → excepción.
- **Llamada real (verificación 2, manual/opt-in, fuera del gate):**
  `BOE_LIVE_TEST=1 ./gradlew :backend:test --tests '*BoeSumarioLiveTest'` contra
  una fecha laborable conocida (p. ej. `20261009`) → 200 y entradas no vacías; o
  `curl -s -H 'Accept: application/json' 'https://www.boe.es/datosabiertos/api/boe/sumario/20261009' | head`.
  El test se salta por defecto, así que **no** hay red en CI/gate.
- **Gate estándar sin red ni BD:** `./gradlew build --no-daemon` →
  BUILD SUCCESSFUL; `./gradlew test` → 3 módulos verdes; `.harness/init.sh` →
  exit 0.
- **E2E:** no aplica — no hay flujo de usuario ni endpoint nuevo; los tests con
  `MockEngine` cubren el cliente de punta a punta sin red.
- `init.sh` (harness): **no** se modifica; sigue siendo el gate no bloqueante que
  ejecuta `./gradlew build` y **no** arranca servidores.

## Evidence To Capture

- Salida de `./gradlew :backend:test` con `BoeSumarioClientTest`,
  `SumarioParsingTest` y `BoeSumarioLiveTest` (opt-in), y recuento de entradas por
  sección + exclusión de V.A sobre los fixtures.
- Salida real de la llamada a la API (HTTP 200 y entradas no vacías) con la fecha
  usada.
- Prueba de `404` (día sin publicación) → lista vacía.
- Gate sin red: `./gradlew build`, `./gradlew test` e `init.sh` (exit 0).
- Ficheros del commit `FT00006`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (`evidence`).

## Validator Checklist

- [ ] Alcance acotado: solo el cliente del sumario + su modelo + tests; sin BD,
      sin endpoint, sin clasificación, sin texto completo, sin job, sin descargar
      el sumario en el arranque (`Application.kt` intacto).
- [ ] Escenarios 1–6 pasan (fixture real; `item` objeto/array; `404`→vacío; fecha
      `YYYYMMDD` + `Accept: application/json`; error tipado; llamada real opt-in).
- [ ] El cliente devuelve **solo** I, II.A, II.B, III y V.B (excluye IV y V.A).
- [ ] Los fixtures son respuestas **reales** del BOE y cubren ambas formas de `item`.
- [ ] El gate `./gradlew build`/`init.sh` sigue verde **sin red** ni servicios
      externos; los tests de red son opt-in.
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, `docs/desarrollo-local.md`,
      `PROGRESS.md` y `feature_list.json` actualizados correctamente.
- [ ] No unrelated product behavior or extra feature work was added.

