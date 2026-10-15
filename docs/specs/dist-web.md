# Feature Implementation Spec: Despliegue web (Wasm) y enlaces compartibles

## Source Feature

- `id`: dist-web
- `ft_id`: FT00039 (registrado en `docs/feature-ids.md`)
- `parts`: **recomendado dividir** en `FT00039-PT1` (build/despliegue Web + **URL de API
  parametrizable** + SEO básico del shell) y `FT00039-PT2` (**enlaces compartibles** /
  deep links Web). Ver *División recomendada*.
- `area`: distribucion
- `depends_on`: `ui-detalle` (FT00033, `accepted`) + `ui-navegacion-estado` (FT00034,
  `accepted`). **Prerrequisito de facto**: `web-full-viewport` (FT00051, `in_progress`).
- `status`: not_started (al planificar)
- `source`: `feature_list.json` (`notes`: `docs/roadmap.md` 0.7-T02 y 0.9-T03)
- `claim`: rama `feat/ft00039-dist-web` ya reclamada en `origin`
  (`7b98bfd chore(FT00039): claim dist-web`), base = `origin/main` (`446f508`); **sin PR
  abierto** (`gh pr list --state open` vacío). El planner no crea ramas ni edita
  `feature_list.json`.

> **Decisión de alcance (esta feature agrega dos tareas de roadmap de versiones
> distintas).** 0.7-T02 «Deploy Web (Wasm) y enlaces compartibles / SEO básico» y
> 0.9-T03 «Compartir norma con deep links». La parte de **despliegue** es el contrato que
> consume **FT00052-PT2** (release-actions, Web); la parte de **enlaces compartibles** no
> la da la librería de navegación (ver *Repository Research*) y exige puente JS propio.

> **Decisiones cerradas con el dueño (no reabrir).** (1) La Web se sirve desde el **Nginx
> del servidor propio**, no hosting externo; el `deploy/` de FT00041 y el pipeline de
> FT00052-PT1 ya están en `main`. (2) **FT00052-PT2 depende de esta feature**: necesita un
> build Wasm de producción con **URL de API parametrizable**; este spec **define ese
> mecanismo** y el contrato del artefacto. (3) **No** se duplica aquí el trabajo de CI/CD
> (rsync/SSH, servir estático en Nginx, fallback SPA conservando el proxy a `/v1/*`,
> `/health`, `/openapi.json`): eso es FT00052-PT2.

## Goal

Publicar la app Web (Wasm) como **estático de producción** que se abre por **URL** y
consume la **API real** (URL base parametrizable en build), y ofrecer **enlaces
compartibles** a una norma (una URL de detalle abre directamente su pantalla), con **SEO
básico** del shell (`index.html`).

El resultado son dos entregables encadenados:

- **PT1** — mecanismo de build `-PapiBaseUrl` (propiedad Gradle → constante generada,
  **solo** `wasmJsMain`, sin romper Android/iOS/JVM) + SEO del shell + cómo se sirve el
  estático. Es el **contrato** que FT00052-PT2 cablea (artefacto
  `composeApp/build/dist/wasmJs/productionExecutable/`).
- **PT2** — puente de URL Web (leer la ruta del navegador al arrancar, sincronizar el
  historial al navegar y responder a `popstate`) sobre las rutas ya existentes
  (`feed`, `detail/{publicationId}`), de modo que `/norma/<id>` sea compartible.

## Non-Goals

- **CI/CD de la Web** (workflow `release-web.yml`, `rsync`/SSH, `WEB_ROOT`, servir el
  estático en Nginx, `try_files`/fallback SPA, conservar el proxy de la API): es
  **FT00052-PT2**. Aquí solo se fija el **contrato** (propiedad de build + ruta del
  artefacto).
- **SSR/prerender y SEO real por norma**: el contenido lo pinta el cliente (Wasm); los
  *crawlers* y los previsualizadores de enlaces **no** ejecutan Wasm, así que el SEO de
  cada norma no es alcanzable sin render en servidor. **Fuera de alcance**; «SEO básico»
  = metadatos estáticos del shell.
- **`robots.txt`/`sitemap.xml` dinámicos** y datos estructurados (`schema.org`): valor
  marginal para una SPA sin SSR; se pueden añadir después.
- **Empaquetado Android/iOS** (FT00038/FT00040) y **backend** (`:backend` no se toca).
- **Notificaciones push, historial local, cuentas, analítica/cookies** (fuera de 1.0.0).
- **Cambiar `ci.yml`, `.harness/init.sh`, las reglas del gate o los módulos Gradle**
  (salvo `composeApp/build.gradle.kts`, que sí se toca en PT1 para el mecanismo de build).
- **Rediseño visual**: no cambia `DESIGN.md` ni los tokens.

## Job Story

When quiero enseñar una norma concreta a alguien (o volver a ella más tarde),
I want copiar su enlace y que al abrirlo se cargue esa norma en la Web,
so I can compartir el BOE por URL sin que nadie tenga que navegar a mano desde el feed.

## Users And Permissions

- **Ciudadanía (usuario final):** anónima, solo lectura; abre la Web por URL, navega y
  copia enlaces. Sin cuentas, sin datos personales, sin cookies ni analítica.
- **Dueño/operador:** construye el estático con la URL de API de producción, lo sirve
  (local para verificar; en el servidor, vía FT00052-PT2) y comprueba el feed/el detalle.
- **Desarrollador:** ejecuta los gates (`build -PskipClient`, `test`, `detekt`,
  `init.sh --with-client`, `wasmJsBrowserDistribution`) y captura evidencia.
- Sin autenticación ni autorización.

## Acceptance Scenarios

### Scenario 1: build Web de producción con URL de API parametrizable (PT1)

Given el repo con el mecanismo `-PapiBaseUrl`,
When ejecuto `./gradlew :composeApp:wasmJsBrowserDistribution -PapiBaseUrl=https://datopublico.example`,
Then el build produce `composeApp/build/dist/wasmJs/productionExecutable/` y la app usa esa
URL base; **sin** la propiedad, usa el valor de desarrollo `http://localhost:8080`
(comportamiento actual intacto); y Android/iOS/JVM **no** cambian su URL base.

### Scenario 2: la build Web se sirve estáticamente y carga el feed por URL (PT1)

Given la distribución de producción y el backend accesible (CORS permisivo por defecto),
When sirvo `productionExecutable/` con un servidor estático y abro `http://localhost:<puerto>/`,
Then `index.html` + `*.wasm` se sirven con los `Content-Type` correctos y la app **carga el
feed** desde la API (URL base inyectada), sin depender de rutas del servidor.

### Scenario 3: SEO básico del shell (PT1)

Given el `index.html` de la distribución,
When se inspecciona su `<head>`,
Then declara `<html lang="es">`, `<title>`, `<meta name="description">`, `<link
rel="canonical">` y metadatos Open Graph (`og:title`/`og:description`/`og:type`/`og:url`/
`og:image`), sin literales de UI de la app (son metadatos de página, no textos de UI) y sin
secretos.

### Scenario 4: una URL de detalle es compartible y muestra la norma (PT2)

Given el estático servido y la ruta cliente `/norma/BOE-A-2026-21001`,
When abro esa URL directamente en el navegador (o la pego en una pestaña nueva),
Then la app **abre la pantalla de detalle** de esa publicación (cargando su detalle desde
la API) en vez del feed; el `id` se toma de la ruta y se decodifica de forma segura (nunca
provoca *crash*).

### Scenario 5: la URL del navegador sigue a la navegación (PT2)

Given la app abierta en el feed (`/`),
When pulso una tarjeta y llego al detalle, y luego vuelvo atrás,
Then la barra de direcciones pasa a `/norma/<id>` al abrir el detalle y vuelve a `/` al
atrás; el atrás del navegador (`popstate`) navega en la app sin recargar y **sin** bucles
entre el historial y el `NavController`; la ruta del feed y la del detalle son las mismas
que usa la navegación interna.

### Scenario 6: ruta desconocida no rompe (PT2)

Given el estático servido,
When abro una ruta cliente que no corresponde a ningún destino (p. ej. `/loquesea`),
Then la app muestra el **feed** (destino por defecto) sin error; el **fallback SPA de
Nginx** (devolver `index.html` con `200`) es responsabilidad de **FT00052-PT2**, no de esta
feature.

### Scenario 7: el gate sigue offline (PT1/PT2)

Given un runner **sin** Android SDK, sin Docker, sin red, sin BD y sin secretos,
When ejecuto `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew detekt`
(+ `:cpdCheck`) y `.harness/init.sh`,
Then todo está en verde y sin cambios en el gate; el build Wasm se verifica con
`.harness/init.sh --with-client` (`:composeApp:wasmJsBrowserDistribution` +
`:composeApp:jvmTest`), y los tests nuevos son **puros** (sin navegador ni sockets).

### Scenario 8: capturas (PT2)

Given un cambio de comportamiento de interfaz (navegación por URL),
When se abre el PR de PT2,
Then incluye capturas en `docs/pr/ft00039-dist-web/` (antes: feed en `/`; después: detalle
abierto por URL) enlazadas con URL absoluta a la rama (`docs/pr/README.md`). PT1 **no**
cambia píxeles visibles: solo evidencia textual del build/servido.

## Repository Research

### Files Inspected

> Planificación sobre el checkout de producto en la rama `feat/ft00039-dist-web`
> (`7b98bfd`), base `origin/main` (`446f508`), que **ya contiene** FT00041 (`deploy/`) y
> FT00052-PT1. No se modificó nada.

- `composeApp/build.gradle.kts` — targets `androidTarget`/`jvm`/`iosArm64`/
  `iosSimulatorArm64`/`wasmJs { browser(); binaries.executable() }`; `wasmJsMain.dependencies`
  con el motor JS de Ktor; `wasmJsBrowserTest` **deshabilitado**; `compose.resources`
  con `packageOfResClass`. Punto donde vive el mecanismo `-PapiBaseUrl` y el `srcDir`
  generado.
- `composeApp/src/wasmJsMain/kotlin/…/core/network/Platform.wasmJs.kt` — `actual
  platformApiBaseUrl()` devuelve `private const val WASM_BASE_URL = "http://localhost:8080"`
  (**hardcodeado**); también `currentIsoDate()` con `js(...)`. Es lo que hay que hacer
  parametrizable.
- `composeApp/src/{androidMain,iosMain,jvmMain}/kotlin/…/core/network/Platform.*.kt` —
  los otros `actual` (`10.0.2.2` en Android, `localhost` en iOS/JVM). **No** deben cambiar.
- `composeApp/src/commonMain/kotlin/…/core/network/ApiConfig.kt` — `data class ApiConfig`
  (inyectable) con `baseUrl = platformApiBaseUrl()`; consumidor de la URL base. Sin cambios.
- `composeApp/src/wasmJsMain/kotlin/…/app/main.kt` — `main()` con `ComposeViewport(document.body!!)`
  → `App()`. Punto de entrada Web.
- `composeApp/src/wasmJsMain/resources/index.html` — shell actual: `<html lang="es">`,
  `<meta viewport>`, `<title>DatoPublico</title>`, `<body>` con `<div id="root">` y
  `<script src="composeApp.js">`. Se amplía con metadatos SEO (PT1). **FT00051 también toca
  este fichero** (ver *Risks*).
- `composeApp/src/commonMain/kotlin/…/app/AppRoutes.kt` — `object AppRoutes` con `FEED`
  (`"feed"`), `DETAIL` (`"detail/{publicationId}"`), `ARG_PUBLICATION_ID`, `CHAT`,
  `SEARCH` y `fun detail(id)` (codificación percent de segmento, pura). Base del mapeo
  ruta↔path (PT2).
- `composeApp/src/commonMain/kotlin/…/app/AppNavHost.kt` — `NavHost(startDestination =
  AppRoutes.FEED)` con `rememberNavController()`; **no** lee la URL del navegador ni
  escribe el historial. Es donde se engancha el puente de URL (PT2).
- `composeApp/src/commonMain/kotlin/…/app/App.kt` — *composition root* manual (cliente
  HTTP Ktor único, repositorios y *factories*); `DatoPublicoTheme { Surface { AppNavHost(…) } }`.
- `composeApp/src/commonTest/kotlin/…/app/AppRoutesTest.kt` — tests puros de las rutas y
  la codificación del `id` (8 tests); precedente para los tests del mapeo URL↔ruta (PT2).
- `gradle/libs.versions.toml` — `composeMultiplatform = "1.7.3"`,
  `androidxNavigation = "2.8.0-alpha11"` (`org.jetbrains.androidx.navigation`),
  `androidxLifecycle = "2.8.4"`, `ktor = "3.0.3"`. **No** hay soporte de deep links Web en
  esa versión (ver *Current Gaps*).
- `docs/desarrollo-local.md` (producto) — §Web: `wasmJsBrowserDistribution` →
  `composeApp/build/dist/wasmJs/productionExecutable/`; §«Backend y URL base (FT00035)»
  (URL por plataforma). Punto donde documentar `-PapiBaseUrl` y el servido estático.
- `docs/release.md` (producto) — runbook de release (PT1 backend); su §Web la añadirá
  **FT00052-PT2**. Se enlaza, no se duplica.
- `deploy/docker-compose.prod.yml` + `deploy/nginx/templates/datopublico.conf.template`
  (FT00041, en `main`) — Nginx hoy **solo** hace proxy a `backend:8080`; **no** sirve
  estático (lo ampliará FT00052-PT2).
- `backend/src/main/kotlin/…/plugins/Cors.kt` + `infra/HttpHardeningConfig.kt` — CORS
  **permisivo por defecto** (`anyHost()` con `CORS_ALLOWED_ORIGINS` vacía); permite servir
  la Web desde otro puerto local sin tocar el backend.
- Harness: `feature_list.json` (FT00039/FT00051/FT00052), `docs/feature-ids.md`,
  `docs/roadmap.md` §0.7 (0.7-T02) y §0.9 (0.9-T03), `docs/technical-discovery.md`
  §«Deployment and Operations», `docs/specs/release-actions.md` (PT2),
  `docs/specs/deploy-backend.md`, `docs/specs/ui-navegacion-estado.md`, ADR 0030/0031/0034.

### Existing Patterns To Follow

- **`expect/actual` por plataforma** para lo específico (precedente `platformApiBaseUrl`,
  `currentIsoDate`); los `actual` que no aplican son **no-op** (no rompen otras plataformas).
- **UI única en `commonMain`**; la navegación es `navigation-compose` con rutas **string**;
  el `id` de ruta se codifica en `AppRoutes.detail`.
- **Version catalog + Kotlin DSL**; dependencias nuevas solo si son imprescindibles (aquí
  **no** hace falta ninguna nueva).
- **Tests puros en `commonTest`** (corren en `:composeApp:jvmTest` sin red ni navegador).
- **Config por propiedad de build** (nuevo): el proyecto ya usa `-PskipClient`; el patrón
  `providers.gradleProperty(...)` + generación de fuente encaja sin plugins externos.
- **Estilo MUST**: identificadores en inglés, KDoc en castellano, un solo `return`, sin
  `else if`, funciones ≤40 líneas, `@Preview` en toda función `@Composable`, sin crashes.
- **Evidencia visual** en `docs/pr/<slug>/` solo si cambian píxeles.

### Current Gaps

- La URL de API Web está **hardcodeada** (`WASM_BASE_URL`); no hay mecanismo de build para
  producción. **Bloquea FT00052-PT2.**
- El `index.html` no tiene metadatos SEO (ni `description`, ni canonical, ni Open Graph).
- **No hay soporte de URL del navegador en la navegación.** `navigation-compose`
  `2.8.0-alpha11` (la que fija CMP `1.7.3`) **no** sincroniza rutas con la URL ni resuelve
  deep links Web; el soporte de deep links multiplataforma llegó con
  `navigation 2.10.0-alpha02`/CMP `1.12.0` (documentación oficial de Kotlin y confirmación
  de la comunidad). Subir de versión sería un cambio de base grande y **fuera de alcance**:
  se implementa un **puente JS mínimo** en `wasmJsMain`.
- El repo **no** tiene comando E2E persistente (`wasmJsBrowserTest` fuera del gate); la
  cobertura es tests puros + verificación manual en navegador.

## Technical Approach

### División recomendada (decisión de tamaño)

**Dividir en `FT00039-PT1` y `FT00039-PT2`.** Motivos:

1. La feature agrega **dos tareas de roadmap de versiones distintas** (0.7-T02 y 0.9-T03):
   el despliegue/bundle (PT1) y los enlaces compartibles (PT2) son entregables separables.
2. **PT1 es camino crítico de FT00052-PT2** (release-actions Web) y debe poder aterrizar
   **solo** para desbloquear el pipeline; no tiene por qué esperar al deep link.
3. **PT2 es la parte con riesgo técnico real** (puente JS/historial, interacción con el
   atrás de `navigation-compose`) y merece su **ADR** propio; aislarlo reduce el riesgo del
   PR.
4. **PT1 y PT2 tocan ficheros distintos** salvo `docs/desarrollo-local.md`; PT2 no necesita
   tocar `build.gradle.kts` ni `Platform.wasmJs.kt`. Cada parte queda muy por debajo de 30
   ficheros.
5. **PT1 toca `index.html`, que FT00051 también toca** (bug en curso): secuenciar PT1 tras
   FT00051 y dejar PT2 para después reduce la superficie de conflicto.

Un PR combinado cabría en el límite (≈15–17 ficheros), pero **no se recomienda**: mezcla el
contrato de build (que el pipeline necesita ya) con una decisión durable y arriesgada.
Si el orquestador prefiere una sola PR, el spec sirve igual: PT1 y PT2 están especificadas
por separado y el ADR de PT2 se adelanta.

### PT1 — Mecanismo de URL de API parametrizable (contrato para FT00052-PT2)

**Decisión: propiedad Gradle `apiBaseUrl` → constante Kotlin generada, solo para `wasmJsMain`.**

- Propiedad: `-PapiBaseUrl=<url>` sobre `:composeApp`. **Sin** la propiedad, valor por
  defecto `http://localhost:8080` (comportamiento actual intacto). Se **recorta** la barra
  final y se hace *fail-fast* si el valor es en blanco.
- Generación: una tarea Gradle en `composeApp/build.gradle.kts` escribe
  `composeApp/build/generated/apiConfig/wasmJsMain/es/aviferdev/datopublico/core/network/ApiBaseUrlBuildConfig.kt`:
  ```kotlin
  package es.aviferdev.datopublico.core.network
  internal const val API_BASE_URL: String = "<valor>"
  ```
  El directorio se añade con `kotlin.sourceSets.getByName("wasmJsMain").kotlin.srcDir(...)`
  (un `Provider<Directory>`, que **enlaza la dependencia de tarea** automáticamente), de modo
  que `wasmJsBrowserDistribution` (y cualquier compilación de Wasm) regenera la constante.
- `Platform.wasmJs.kt` deja de usar su `WASM_BASE_URL` privado y devuelve `API_BASE_URL`.
- **Los demás targets no cambian**: la constante se genera **solo** en `wasmJsMain`; Android,
  iOS y JVM conservan sus `actual` hardcodeados de desarrollo. `ApiConfig.kt` y `:shared` no
  se tocan.
- **Mecanismo descartado**: reemplazar un *placeholder* en `index.html` en build y leer un
  global JS desde Kotlin (más piezas móviles, menos testeable, procesa recursos);
  plugin de `buildConfig` de terceros (dependencia externa innecesaria).

**Contrato que consume FT00052-PT2** (no se implementa aquí): el workflow ejecuta
`./gradlew :composeApp:wasmJsBrowserDistribution -PapiBaseUrl="$PROD_API_BASE_URL"` y publica
el artefacto `composeApp/build/dist/wasmJs/productionExecutable/` (index.html + `*.js` +
`*.wasm` + recursos) por `rsync`/SSH a `WEB_ROOT`; el Nginx servirá ese directorio con
`try_files … /index.html` conservando el proxy de `/v1/*`, `/health` y `/openapi.json`.

### PT1 — SEO básico del shell (`index.html`)

- Mantener `<html lang="es">`; añadir `<meta name="description">` (castellano, sin literales
  de UI de la app), `<link rel="canonical">` (placeholder del dominio de producción),
  `<meta name="robots" content="index,follow">` y Open Graph
  (`og:title`/`og:description`/`og:type=website`/`og:url`/`og:image`), además de
  `theme-color` y un `favicon`.
- Los valores son **metadatos de página** (no i18n de UI) y **no** contienen secretos. El
  dominio definitivo puede quedar como *placeholder* hasta que FT00052-PT2 fije el hosting.
- **Sin** SSR: los metadatos son los mismos para todas las rutas; el SEO por norma es un
  Non-Goal documentado.

### PT2 — Puente de URL Web (deep links) sin tocar la librería

**Decisión: puente `expect/actual` mínimo sobre la History API, con mapeo puro ruta↔path.**

- **Mapeo puro (`commonMain`, testeable)**: `object AppUrlMapper` (o extender `AppRoutes`):
  - `FEED_PATH = "/"` y `DETAIL_PATH_PREFIX = "/norma/"`.
  - `fun pathForRoute(route: String): String` — `"feed"` → `/`, `"detail/<id>"` →
    `/norma/<id>` (reutiliza la codificación de segmento de `AppRoutes`); `chat`/`search` →
    `/chat`/`/buscar` (opcional).
  - `fun routeForPath(path: String): String?` — `/` → `feed`; `/norma/<id>` →
    `detail/<id>` decodificado; desconocido → `null`.
- **Puente `expect/actual`** (`core/web/WebUrl.kt` en `commonMain` + un `actual` por target,
  siguiendo el patrón de `core/network/Platform.*.kt`):
  - `expect fun currentWebPath(): String`
  - `expect fun replaceWebPath(path: String)`
  - `expect fun onWebPathChanged(listener: (String) -> Unit)`
  - `actual` **wasmJs**: `window.location.pathname`;
    `window.history.replaceState(null, "", path)`; `window.addEventListener("popstate", …)`
    con `kotlinx.browser.window` (ya disponible en Wasm; **sin** dependencias nuevas).
  - `actual` **Android/iOS/JVM**: no-op (`""`, sin efecto) — no rompen el gate ni otras
    plataformas.
- **Integración en `AppNavHost`**:
  - `startDestination` = `AppUrlMapper.routeForPath(remember { currentWebPath() }) ?:
    AppRoutes.FEED` (una ruta desconocida o vacía cae al feed; nunca *crash*).
  - `LaunchedEffect` sobre la entrada actual del *back stack* → `replaceWebPath(pathForRoute(…))`
    (la URL sigue a la navegación; `replaceState` para no llenar el historial).
  - `DisposableEffect` que registra `onWebPathChanged` → si el path mapea a una ruta
    distinta de la actual, `navController.navigate(route)`; si no mapea, se ignora. Se
    compara con la ruta actual para **evitar bucles** historial↔NavController.
  - El `id` de ruta se decodifica con el helper existente (`.orEmpty()`); nunca `!!`.
- **`index.html`**: opcional, actualizar `document.title` por ruta desde el puente (mejora
  menor de SEO/UX). Si se hace, mantener el título base del shell como valor por defecto.
- **ADR obligatorio** (decisión durable): «navegación Web por URL con puente `expect/actual`
  sobre la History API, dado que `navigation-compose` de CMP 1.7.3 no soporta deep links
  Web; esquema de rutas `/` y `/norma/<id>`; sin SSR». Registrar en `docs/adr/` e índice.

### Restricciones de estilo a vigilar

- **Sin crash**: `routeForPath` devuelve `null` para desconocido y el llamante usa `?: FEED`;
  el `id` con `.orEmpty()`; sin `!!`/`throw`/`error` como control.
- **≤40 líneas/función** y **un solo `return`**: extraer el registro de *listeners* y el
  mapeo a funciones privadas si `AppNavHost` crece.
- **detekt/CPD**: la lógica nueva va en `commonMain`/`commonTest`; evitar bloques repetidos
  >100 tokens.
- **`@Preview`**: si se añade algún `@Composable` nuevo, lleva su `@Preview` dentro del tema.

## Expected File Changes

Rutas en el repo de producto (`..`); `es/aviferdev/datopublico` se abrevia `…`.

**PT1 — Despliegue Web + URL de API parametrizable + SEO (≈5 ficheros):**
- `composeApp/build.gradle.kts` — modify; tarea de generación + `srcDir` en `wasmJsMain` +
  propiedad `apiBaseUrl`.
- `composeApp/src/wasmJsMain/kotlin/…/core/network/Platform.wasmJs.kt` — modify; usar la
  constante generada `API_BASE_URL`.
- `composeApp/src/wasmJsMain/resources/index.html` — modify; metadatos SEO del shell.
- `docs/desarrollo-local.md` (producto) — modify; `-PapiBaseUrl` y servido estático.
- *(generado, no versionado)* `composeApp/build/generated/apiConfig/wasmJsMain/…/ApiBaseUrlBuildConfig.kt`.

**PT2 — Enlaces compartibles (deep links Web) (≈9–11 ficheros):**
- `composeApp/src/commonMain/kotlin/…/app/AppUrlMapper.kt` — create; mapeo puro ruta↔path.
- `composeApp/src/commonMain/kotlin/…/core/web/WebUrl.kt` — create; `expect` functions.
- `composeApp/src/wasmJsMain/kotlin/…/core/web/WebUrl.wasmJs.kt` — create; History API.
- `composeApp/src/androidMain/kotlin/…/core/web/WebUrl.android.kt` — create; no-op.
- `composeApp/src/iosMain/kotlin/…/core/web/WebUrl.ios.kt` — create; no-op.
- `composeApp/src/jvmMain/kotlin/…/core/web/WebUrl.jvm.kt` — create; no-op.
- `composeApp/src/commonMain/kotlin/…/app/AppNavHost.kt` — modify; ruta inicial + sincronía.
- `composeApp/src/commonTest/kotlin/…/app/AppUrlMapperTest.kt` — create; mapeo puro.
- `composeApp/src/wasmJsMain/resources/index.html` — modify *(opcional)*; `document.title`
  por ruta (si se hace; si no, no se toca en PT2).
- `docs/desarrollo-local.md` (producto) — modify; nota de deep links.
- `docs/pr/ft00039-dist-web/antes-feed.png` + `despues-detalle-url.png` — create; capturas.

Harness (privado, repo aparte): `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR de PT2 + índice,
`PROGRESS.md` y `feature_list.json` (los cierra el orquestador; **el planner no los edita**).

Totales: **PT1 ≈ 4–5 ficheros** y **PT2 ≈ 9–11 ficheros** → cada parte muy por debajo de 30.

## Visual Design Impact

- UI involved: **PT1 no** (solo metadatos del shell; sin cambio de píxeles). **PT2 sí**
  (cambio de comportamiento de navegación: abrir por URL).
- Design source: `DESIGN.md` (tokens = fuente de verdad; **no** cambia).
- Screens or states affected: **Feed** y **Detalle** (PT2, vía URL); estados de
  carga/vacío/error sin cambios visuales.
- New design artifact required: **no**.

## Durable Documentation Impact

- `ARCHITECTURE.md`: **update** — nueva superficie de **build/despliegue Web** (propiedad
  `apiBaseUrl` → constante generada, artefacto `productionExecutable/`) y, en PT2, el
  **puente de URL** Web (`expect/actual` sobre la History API) y el mapeo ruta↔path.
- `CONSTRAINTS.md`: **update** (pequeño) — MUST nuevos: la URL de API de la Web se inyecta
  **solo** por build (`-PapiBaseUrl`), nunca hardcodeada para producción; los enlaces
  compartibles Web usan el **esquema de rutas** (`/`, `/norma/<id>`) con el puente de URL;
  el gate sigue offline y sin secretos.
- `AGENTS.md`: **not needed** — el flujo, el arranque y las reglas no cambian.
- Other docs: `docs/adr/<nnnn>-enlaces-web-history-api.md` — **create** (PT2; decisión
  durable) + índice `docs/adr/README.md`; `docs/desarrollo-local.md` — **update** (PT1 y
  PT2). `docs/release.md` §Web — **not needed aquí** (lo añade FT00052-PT2).

## Implementation Plan

Orden: **PT1 → PT2** (PT1 es el contrato de FT00052-PT2 y debe aterrizar antes).

1. **PT1** — verificar que FT00051 está resuelta (o coordinar `index.html`). Añadir el
   mecanismo `-PapiBaseUrl` (tarea de generación + `srcDir` + `Platform.wasmJs.kt`); probar
   `wasmJsBrowserDistribution` con y sin la propiedad; añadir metadatos SEO al `index.html`;
   documentar en `docs/desarrollo-local.md`; servir el estático en local y comprobar el feed.
2. **PT2** — `AppUrlMapper` (+ test puro); `expect/actual` de `WebUrl`; integrar en
   `AppNavHost` (ruta inicial, sincronía, `popstate`); verificar en navegador (abrir
   `/norma/<id>`, navegar y volver); ADR + capturas; actualizar docs durables.
3. **Cierre** — `PROGRESS.md`/`feature_list.json` los cierra el orquestador.

## Implementation Tasks

**PT1**
- [ ] `composeApp/build.gradle.kts`: propiedad `apiBaseUrl` (default `http://localhost:8080`,
  recorte de `/` final, *fail-fast* si vacía) + tarea que genera
  `ApiBaseUrlBuildConfig.kt` + `srcDir` en `wasmJsMain`.
- [ ] `Platform.wasmJs.kt`: `platformApiBaseUrl()` devuelve `API_BASE_URL`; eliminar la
  constante privada.
- [ ] `index.html`: metadatos SEO (description, canonical, robots, Open Graph, theme-color,
  favicon).
- [ ] `docs/desarrollo-local.md`: `-PapiBaseUrl` + servido estático del artefacto.
- [ ] Verificar: `wasmJsBrowserDistribution` con/sin propiedad; Android/iOS/JVM sin cambios.

**PT2**
- [ ] `AppUrlMapper.kt` (puro) + `AppUrlMapperTest`.
- [ ] `WebUrl.kt` (`expect`) + `actual` wasmJs (History API) + no-op Android/iOS/JVM.
- [ ] `AppNavHost.kt`: `startDestination` desde la URL, `replaceWebPath` al navegar,
  `popstate` → navegar, sin bucles.
- [ ] `docs/desarrollo-local.md`: nota de deep links.
- [ ] ADR de PT2 + índice; capturas antes/después; `ARCHITECTURE.md`/`CONSTRAINTS.md`.

## Verification Plan

### A. Gate estándar (obligatorio; sin red, BD ni Android SDK)

- `./gradlew build -PskipClient`, `./gradlew test`, `./gradlew detekt` (+ `:cpdCheck`) y
  `.harness/init.sh` → exit 0. `ci.yml` e `init.sh` **sin cambios**.
- **PT2**: `AppUrlMapperTest` corre en `:composeApp:jvmTest` (puro, sin navegador).

### B. Gate con cliente (offline; requiere Android SDK)

- `.harness/init.sh --with-client` (o `./gradlew :composeApp:wasmJsBrowserDistribution` +
  `:composeApp:jvmTest`) → verde. **PT1**: probar `-PapiBaseUrl=https://example.test` y sin
  la propiedad.

### C. Verificación local en navegador (opt-in)

- **PT1**: `./gradlew :composeApp:wasmJsBrowserDistribution -PapiBaseUrl=http://localhost:8080`;
  servir `composeApp/build/dist/wasmJs/productionExecutable/` (p. ej.
  `python3 -m http.server` en `composeApp/build/dist/wasmJs/productionExecutable/`) y abrir
  `http://localhost:<puerto>/` con el backend en `:8080` (CORS permisivo) → **carga el feed**.
- **PT2**: abrir `http://localhost:<puerto>/norma/BOE-A-2026-21001` → abre el detalle;
  navegar feed↔detalle y comprobar que la URL sigue a la navegación y que el atrás del
  navegador funciona sin bucles; una ruta desconocida cae al feed.
- **Servidor real / Nginx estático + fallback SPA**: **no** se verifica aquí; es FT00052-PT2.

### D. `init.sh` y E2E

- `./init.sh` **no** se modifica y **no** arranca servidores.
- E2E: no aplica — no hay comando E2E persistente (`wasmJsBrowserTest` fuera del gate); la
  cobertura es tests puros (PT2) + verificación manual en navegador (C).

## Evidence To Capture

- Salida de `wasmJsBrowserDistribution` con `-PapiBaseUrl` de producción y sin ella; ruta
  del artefacto `productionExecutable/`.
- Confirmación de que Android/iOS/JVM conservan su URL base (sin cambios).
- Confirmación de que `index.html` de la distribución lleva los metadatos SEO.
- (PT2) `AppUrlMapperTest` en verde; apertura de `/norma/<id>` por URL; sincronía del
  historial y `popstate`; ruta desconocida → feed.
- Capturas antes/después (PT2) en `docs/pr/ft00039-dist-web/`.
- Gate (`build -PskipClient`, `test`, `detekt`, `init.sh` exit 0; `--with-client` verde) y
  ausencia de cambios en `ci.yml`/`init.sh`/`:backend`.
- Ficheros de cada commit `FT00039-PTn`, PR y run de CI; entradas en `PROGRESS.md` y
  `feature_list.json` (las cierra el orquestador).

## Validator Checklist

- [ ] Alcance por parte: PT1 = build/despliegue Web + URL de API parametrizable + SEO;
      PT2 = enlaces compartibles (deep links). **Sin** CI/CD (FT00052-PT2), **sin** SSR,
      **sin** `:backend`, **sin** Android/iOS, **sin** cambios en `ci.yml`/`init.sh`.
- [ ] Escenarios 1–8 pasan (1–3 y 7 en PT1; 4–6 y 8 en PT2).
- [ ] `-PapiBaseUrl` parametriza **solo** la Web; sin la propiedad, comportamiento de
      desarrollo intacto; Android/iOS/JVM **sin** cambios.
- [ ] El artefacto es `composeApp/build/dist/wasmJs/productionExecutable/` y el **contrato**
      para FT00052-PT2 está documentado (propiedad + ruta).
- [ ] (PT2) `/norma/<id>` abre el detalle; la URL sigue a la navegación; `popstate` no crea
      bucles; ruta desconocida → feed; el `id` se decodifica sin *crash*.
- [ ] El puente es `expect/actual` con `actual` no-op en Android/iOS/JVM; **sin**
      dependencias nuevas; ADR registrado.
- [ ] SEO = metadatos estáticos del shell (sin SSR); sin secretos ni literales de UI de la
      app en el `<head>`.
- [ ] Estilo MUST (un `return`, sin `else if`, ≤40 líneas/función, KDoc en castellano,
      identificadores en inglés); `@Preview` si hay `@Composable` nuevo.
- [ ] El gate sigue offline y verde; ≤30 ficheros por PR; capturas de PT2 en
      `docs/pr/ft00039-dist-web/` (o justificación).
- [ ] `ARCHITECTURE.md`, `CONSTRAINTS.md`, ADR + índice y `docs/desarrollo-local.md`
      actualizados; `PROGRESS.md`/`feature_list.json` corregidos por el orquestador.

## Risks / Open Questions

- **Dependencia de FT00051 (`web-full-viewport`, `in_progress`).** La verificación «carga el
  feed por URL» **depende** de que FT00051 esté resuelta (hoy en la Web solo se pinta el
  primer destacado). **PT1 debe hacerse tras FT00051** o coordinarse: ambas tocan
  `index.html`. Si FT00051 no está en `main`, anotar el bloqueo y no marcar PT1 como
  terminada.
- **`navigation-compose` sin deep links Web (decisión clave).** La versión fijada
  (`2.8.0-alpha11`, CMP `1.7.3`) **no** soporta URL/deep links; el soporte oficial llegó con
  nav `2.10.0-alpha02`/CMP `1.12.0`. Subir la base es un cambio grande y arriesgado
  (alineación `lifecycle`/`savedstate`, `IrLinkageError` en iOS): **fuera de alcance**. Se
  implementa un puente JS mínimo; si el dueño prefiere esperar a la librería, PT2 se
  **difiere** (PT1 sigue siendo válido y desbloquea FT00052-PT2).
- **Interacción atrás navegador ↔ `NavController`.** Riesgo de bucles o doble navegación
  entre `popstate` y el atrás de la librería. Mitigación: comparar la ruta mapeada con la
  actual antes de navegar y usar `replaceState` (no `pushState`) al sincronizar.
- **SEO real por norma no es alcanzable sin SSR.** «Enlaces compartibles con SEO básico» se
  entrega como **shell estático + deep links funcionales**; la previsualización enriquecida
  por norma (Open Graph dinámico) requeriría render en servidor → Non-Goal documentado.
- **`index.html` con `lang="es"` y metadatos estáticos**: el dominio definitivo (canonical/
  `og:url`) puede quedar como *placeholder* hasta FT00052-PT2.
- **Conflicto de fichero con FT00052-PT2.** PT2 de release-actions tocará
  `deploy/docker-compose.prod.yml`, `deploy/nginx/...` y `docs/release.md`; esta feature
  **no** los toca (solo el contrato), así que no hay solape más allá de la propiedad
  `apiBaseUrl`/`PROD_API_BASE_URL`, que debe quedar **idéntica** en ambos specs.
- **Verificación del servido real** (Nginx estático + fallback SPA + proxy `/v1/*`): **no**
  verificable en esta feature; es FT00052-PT2 y requiere el servidor.
- **División**: recomendada en `FT00039-PT1`/`FT00039-PT2` (ver *Technical Approach*). El
  orquestador debe registrar las partes en `feature_list.json`/`docs/feature-ids.md`; el
  planner **no** los edita.
