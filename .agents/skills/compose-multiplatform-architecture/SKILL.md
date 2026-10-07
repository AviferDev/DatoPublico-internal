---
name: compose-multiplatform-architecture
description: Guía de arquitectura del cliente Compose Multiplatform (módulo :composeApp) de Vuelantis. Úsala al añadir o modificar pantallas, ViewModel, estado (UDF/StateFlow), use cases, repositorios/data sources, capas, navegación, DI (Koin), identidad de plataforma, tema o tests del cliente Android/iOS, o al planificar targets nuevos. Distingue el estado actual verificado del patrón objetivo (arquitectura por capas estricta) y las reglas de migración; deriva del código real del repositorio, no de una arquitectura inventada.
---

# Arquitectura del cliente Compose Multiplatform

Guía práctica para trabajar en `:composeApp`. Antes de tocar el cliente, lee también `ARCHITECTURE.md` (sección Modules), `DESIGN.md`/`docs/design/` y, si la feature toca cuota/identidad, `docs/user-and-access-model.md`.

La guía distingue tres cosas: **estado actual verificado**, **arquitectura objetivo** y **reglas de migración**. No inventes el objetivo ni asumas que el estado actual ya lo cumple.

## Topología de build (verificada)

- Kotlin Multiplatform + `org.jetbrains.compose` (CMP 1.7.3, Kotlin 2.1.0), un único módulo `:composeApp`.
- Targets en `composeApp/build.gradle.kts`:
  - `androidTarget()` (JVM 11).
  - `iosArm64()` + `iosSimulatorArm64()` con `binaries.framework { baseName = "ComposeApp" }`.
  - `wasmJs { browser(); binaries.executable() }` (Kotlin/Wasm beta; entrypoint `wasmJsMain/main.kt` con `ComposeViewport`).
- La URL del backend Android sale de `BuildConfig.ACCESS_BASE_URL` (por flavor `pro`/`pre`/`dev`). En iOS se resuelve en runtime con `internal fun backendBaseUrl()` (`iosMain/MainViewController.kt`) desde la clave `BackendBaseUrl` del `Info.plist`, rellenada por el build setting `BACKEND_BASE_URL` (default `http://localhost:8080` en `iosApp/Configuration/Project.xcconfig`). En Wasm sale de `WasmBuildConfig` (generado en build time desde `-PappEnv`). El framework iOS lo genera y embebe Xcode con `:composeApp:embedAndSignAppleFrameworkForXcode`.

## Estado actual verificado (deuda conocida)

Es lo que **hoy** existe; no es el patrón objetivo. Al tocar estas zonas, migra hacia el objetivo en lugar de extender la deuda.

- No hay `ViewModel`, `StateFlow`, capa de dominio ni repositorios.
- El IO vive en composables (`CountrySearchProgress` llama a `searchApi.search`; `CountrySearchFormScreen` llama a `searchApi.quote`).
- Inyección manual por parámetros de `App(...)` desde cada entrypoint (no DI framework).
- Navegación manual por estado en `SearchFlow` (`when` sobre estado), sin rutas tipadas.
- Errores tipados como `*ApiException(status)` que llegan hasta la UI.
- Tests de vista con Robolectric en `androidUnitTest` → **deuda a retirar** (ver Tests).
- Deuda puntual: `search/CountrySearchForm.kt` importa `java.time.LocalDate` sin usarlo en `commonMain`; eso rompe iOS/Wasm y debe eliminarse.

## Arquitectura objetivo

### Modelo de capas y regla de dependencia

```
UI (Compose stateless + ViewModel)  ->  Dominio (use cases)  ->  Datos (repositorio -> data sources)
```

Arquitectura por capas estricta (base: guía oficial de Google UI/Dominio/Datos + UDF; **no** es Clean dogmática pero aplica su regla de dependencia).

- La UI conoce el Dominio; **no** conoce Ktor ni DTOs de red.
- El Dominio no conoce Compose, Ktor ni plataforma: solo modelos e interfaces de repositorio.
- Los Datos implementan las interfaces que declara el Dominio; conocen Ktor/SDKs.

Prohibido: un composable que llame a `*Api`; un repositorio que importe de `design/`; un use case que use tipos de Compose/Ktor.

### Estado, UDF y ViewModel

- Cada pantalla tiene un `XViewModel` (androidx.lifecycle multiplataforma) que expone `val uiState: StateFlow<XUiState>` con `stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), initial)`.
- `XUiState` es un `sealed interface` (Loading/Content/Empty/Error) o una `data class` inmutable anotada `@Immutable`.
- Los composables son **stateless**: reciben `uiState` + lambdas de eventos. Cero IO en composables.
- La UI recolecta con `collectAsStateWithLifecycle()` (no `collectAsState()` en código con ciclo de vida).
- Los eventos del usuario son métodos del ViewModel (`onSubmit()`, `onEditSearch()`), nunca estado mutable expuesto.

### Dominio (obligatorio: use cases)

- **Toda** acción relevante pasa por un use case (`operator fun invoke`). Aunque hoy parezca de un solo uso, se crea igual: no se asume que no se reutilizará.
- El ViewModel llama **siempre** a use cases; **nunca** a repositorios directamente.
- Un use case = una responsabilidad (`SearchUseCase`, `QuoteSearchUseCase`, `LoginUseCase`, `RegisterUseCase`, `ResolveDeviceTokenUseCase`...).
- El `AuthSessionManager` actual es de facto un use case: se descompone en `LoginUseCase`/`RegisterUseCase`.
- Testeable sin UI ni red (fakes de repositorio).

### Datos (repositorio + data sources)

- Los `*Api`/storage actuales pasan a ser **data sources**; se envuelven en un repositorio.
- El repositorio es la **única puerta a los datos**: expone `suspend`/`Flow` de modelos de dominio, nunca DTOs de red.
- El repositorio es una clase concreta (como el template oficial); usa `interface` solo si hay 2 implementaciones o lo exige el test.
- El mapeo DTO (red) -> Model (dominio) -> UiState (UI) se hace en la frontera de cada capa.
- Todo DTO `@Serializable` (también los de `:shared`, *requests* y *responses*) anota **todas** sus propiedades con `@SerialName` explícito, **aunque el nombre coincida**: el contrato de cable no depende del nombre del símbolo Kotlin.

### DI con Koin (siempre)

- **Koin obligatorio desde el primer momento**: `koin-core` + `koin-compose-viewmodel`.
- `initKoin()` en cada entrypoint; las pantallas obtienen su ViewModel con `koinViewModel()`.
- Módulos: `dataModule` (HttpClient, data sources, repositorios), `useCaseModule`, `viewModelModule`.
- No hay composition root manual ni DI por parámetros de `App(...)` como objetivo final (se conserva solo mientras dure la migración).
- No usar Hilt (no es KMP).

### Navegación tipada

- Rutas `@Serializable` (`object`/`data class`) + `navigation-compose` multiplataforma: `NavHost`, `composable<T>()`, `toRoute<T>()`.
- Sustituye el `when` manual de `SearchFlow`.
- El estado de navegación vive en el orquestador, no en el ViewModel de pantalla.
- **Cada destino es una ruta que posee su ViewModel**: la ruta lo resuelve con `koinViewModel()` (scopeado al `NavBackStackEntry`, se libera al salir del destino) y delega en un contenido stateless previsualizable. `App` monta el `NavHost` y **no** conoce ViewModels (p. ej. `OnboardingRoute`).

### Errores, concurrencia e inmutabilidad

- Ningún `*ApiException` cruza a la UI: el repositorio traduce a un `sealed interface AppError` (Network/Unauthorized/QuotaExceeded/Timeout/Unknown) o `Result<T, AppError>`.
- Re-lanza siempre `CancellationException` antes de capturar `Exception` (invariante).
- El ViewModel lanza en `viewModelScope`; los repositorios usan `withContext(AppDispatchers.io)` con `expect/actual` por plataforma.
- Nunca `GlobalScope`. Modelos de estado anotados `@Immutable`.

## Stack y dependencias objetivo

Dependencias a añadir en `commonMain` (con `gradle/libs.versions.toml`), mismo stack que el `KMP-App-Template` oficial:

- `androidx.lifecycle:lifecycle-viewmodel-compose` y `lifecycle-runtime-compose`.
- `androidx.navigation:navigation-compose` (multiplataforma).
- `io.insert-koin:koin-core` y `koin-compose-viewmodel` (**obligatorio**).
- `kotlinx-datetime` (para no depender de `java.time` en `commonMain`).

## Layout de paquetes (feature-first con capas)

```
commonMain/kotlin/es/vuelantis/
  core/                 # HttpClient, AppDispatchers (expect/actual), AppError/Result
  design/               # design system, sin lógica
  di/                   # módulos Koin (dataModule, useCaseModule, viewModelModule) e initKoin
  navigation/           # destinos tipados (@Serializable) y el grafo NavHost
  feature/<nombre>/
    ui/                 # XRoute.kt (posee el ViewModel) + XScreen.kt + XViewModel.kt + XUiState.kt
    domain/             # <Accion>UseCase.kt, models/, <X>Repository.kt (interface)
    data/               # Ktor<X>Api.kt (data source), <X>RepositoryImpl.kt, dto/
```

El template oficial no separa `ui/domain/data` por feature (usa `data/`, `di/`, `screens/<feature>`); este layout es ese patrón, escalado a capas estrictas.

## Topología de módulos

- El `KMP-App-Template` oficial usa apps finas (`androidApp`/`iosApp`/`desktopApp`/`webApp`) + un módulo `shared`.
- Vuelantis usa hoy un único `:composeApp`. **No fuerces el split** (coste alto); documéntalo como evolución opcional si el cliente crece o se añaden targets.

## Reglas multiplataforma

- **Prohibido `java.*`/`android.*` en `commonMain`** (usa `kotlinx-datetime`, stdlib o `expect/actual`).
- La UI de plataforma y los entrypoints viven solo en `androidMain`/`iosMain`/`wasmJsMain`.
- `DeviceIdentityProvider` es una `interface` en `commonMain`; cada plataforma la implementa (`ANDROID_ID`; UUID en Keychain; UUID en `localStorage`). No metas APIs de plataforma en `commonMain`.
- Sin secretos en el cliente: la API key de Ignav y los secretos del backend nunca salen del backend.

## Migración incremental (Strangler)

No reescribas el cliente de golpe. Al tocar una feature:

1. Extrae el `ViewModel` y mueve el estado a `StateFlow<XUiState>`.
2. Mueve el IO a un repositorio + data source.
3. Introduce el use case correspondiente (**siempre**, no es opcional).
4. Conecta/amplía los módulos Koin y la navegación tipada.

Mantén `App(...)` y los entrypoints estables durante la migración (el composition root migra a Koin). Documenta en `ARCHITECTURE.md` el wiring que cambie.

## Patrones que se conservan del estado actual

Mientras se migra, estos patrones siguen vigentes y deben respetarse:

1. **Abstracción + implementación Ktor.** Cada API es una `interface` con implementación `Ktor*Api(baseUrl, httpClient)`. No añadas una segunda implementación por plataforma: se reutiliza la misma.
2. **`HttpClient` una vez por proceso.** Se crea en el entrypoint/composition root, no dentro de una lambda composable que se recomponga.
3. **Identidad por plataforma** vía `DeviceIdentityProvider`. El UUID de iOS se guarda con `KeychainSettings`; el target iOS debe firmarse ad-hoc con `iosApp/iosApp.entitlements` (sin firma, `SecItemAdd` falla con `-34018`).
4. **Cabecera de identidad vía `AuthContext`.** `Anonymous(deviceToken)` -> `X-Device-Token`; `Registered(jwt)` -> `Authorization: Bearer`. La sesión vive en memoria en el MVP.
5. **Tema, componentes de marca e iconos.** Todo el árbol va dentro de `VuelantisTheme { ... }`. Usa `BrandCard` y `PrimaryButton`. Los **iconos semánticos** usan **Material Icons** (`compose.materialIconsExtended`; `Icon(Icons.Outlined.*)` con `contentDescription`, o `null` si son decorativos): vectores consistentes, tintables y accesibles. Reserva los glifos Unicode/ASCII para lo **tipográfico dentro de un texto** (p. ej. la flecha de `MAD → HND`, separadores `·`, trazos `┊`). Las **flechas de acción/afordancia** (la de un CTA, un botón de continuar) son **iconos** (`Icons.AutoMirrored.Outlined.ArrowForward`), no glifos. Las tipografías se inyectan desde `androidMain` vía `CompositionLocal`.
6. **Sin dependencias de runtime sin justificar.** CMP ya trae runtime/foundation/material3/ui.

## Tests (sin tests de vista)

- **Dominio:** unit tests puros por use case, con fakes de repositorio.
- **Datos:** repositorios y data sources con `MockEngine`; sin red real.
- **ViewModel:** `runTest` + Turbine sobre `uiState` (Loading -> Content -> Error).
- **NO se escriben tests de vistas/composables** (Robolectric/UI test). Los existentes en `androidUnitTest` son deuda: no añadir nuevos ni ampliarlos; retíralos al migrar sus pantallas.
- La lógica nueva se prueba en dominio/ViewModel; la UI se valida solo con E2E manual.
- Gate: `./init.sh --with-client` (tests + `assembleDevDebug`; con flavors `dev`/`pro` las tareas son por variante). Para iOS: `linkDebugFrameworkIosSimulatorArm64` + `xcodebuild` + `simctl`.

## Reglas al cambiar el cliente

- **Crea la capa que falte.** Si el código que añades pertenece a `ui/`, `domain/` o `data/` y esa carpeta aún no existe en la feature, **créala** y coloca ahí el código con sus componentes mínimos (`Screen`/`ViewModel`/`UiState`, use case + `XRepository` (interfaz), `XRepositoryImpl` + data source). No lo dejes en un paquete plano ni en la capa equivocada "porque la carpeta no existe"; tampoco inventes capas o nombres nuevos fuera de este layout.
- **Toda `@Composable` de UI lleva una `@Preview`** (`org.jetbrains.compose.ui.tooling.preview.Preview`) en `commonMain`, envuelta en `VuelantisTheme`; los sub-composables privados se previsualizan con una `@Preview` en el mismo fichero. Separa el contenido **stateless** de la raíz con DI (`App`/`NavHost`) y de las rutas/destinos con ViewModel para poder previsualizarlos. Habilita `compose.components.uiToolingPreview` (commonMain) y `compose.uiTooling` (debugImplementation). Una preview **no** es un test de vista y no relaja la regla "sin tests de vistas/composables".
- **Reutiliza y mantén los composables pequeños.** Antes de escribir UI, reutiliza o extrae un componente. Límite duro de **40 líneas** por función (objetivo 30; sin KDoc, comentarios ni blancos); si lo superas, extrae sub-composables. Un componente **reutilizable/público** va en su propio fichero (`design/components/<Componente>.kt`, una API pública por fichero, con su `@Preview`); los **privados de una sola pantalla** se quedan en el fichero de la pantalla. Extrae un helper a su propio fichero (o a `feature/<x>/ui/components/`) cuando se reutilice o el fichero supere ~**300 líneas**. Buenas prácticas de Compose: stateless, `Modifier` como primer parámetro opcional, sin IO, estado en el ViewModel.
- **Un solo `return` por función.** Cada función tiene un único punto de salida: usa el cuerpo de expresión (`=`) o un `when`/`if` como expresión; no cortes el flujo con `return` tempranos (los casos de guarda se resuelven devolviendo el valor). Aplica igual en UI, dominio y datos.
- **Sin `else if`.** Las cadenas de guardas se escriben con un `when` (como expresión o sentencia), nunca con `if / else if / else`; un `if` simple de dos ramas sigue permitido. Aplica igual en UI, dominio y datos.
- **Cero texto hardcodeado en la UI.** Todo texto visible al usuario va a recursos de Compose Multiplatform (`composeResources/values*/strings.xml`) y se consume con `stringResource(Res.string.*)`; cada clave existe en **todos** los locales. Solo se permiten literales para símbolos tipográficos (`→`, `·`, `┊`) y en previews. Añadir un idioma es crear `values-<locale>/strings.xml`.
- **Iconos semánticos con Material Icons.** Usa `Icon(Icons.Outlined.*)` (`compose.materialIconsExtended`) con `contentDescription` (o `null` si es decorativo) para iconos con significado. Los glifos Unicode/ASCII se reservan a lo tipográfico **dentro de un texto** (la flecha de `MAD → HND`, separadores `·`, trazos `┊`); las **flechas de acción/afordancia** (la de un CTA) son **iconos** (`Icons.AutoMirrored.Outlined.ArrowForward`).
- Mantén la UI fuera de `androidMain`/`iosMain`: solo entrypoints, providers de identidad y recursos de plataforma viven ahí.
- No implementes features nuevas sobre los patrones del "estado actual" (IO en composables, sin ViewModel, sin use case): migra la zona que toques.
- Si añades un target nuevo, replica el patrón: engine Ktor correspondiente, provider de identidad propio y entrypoint que monte el composition root.
- Actualiza `ARCHITECTURE.md` (Modules/Runtime Surfaces) y `AGENTS.md` si cambia el wiring, la build o la superficie de ejecución.

## Cómo verificar antes de dar por hecho un cambio

1. `./gradlew :composeApp:testDevDebugUnitTest` (unit tests de dominio/datos/ViewModel, sin regresión; `testProDebugUnitTest` para el flavor `pro`).
2. `./gradlew :composeApp:assembleDevDebug` (Android compila; con flavors las tareas son por variante).
3. `./gradlew :composeApp:linkDebugFrameworkIosSimulatorArm64` (iOS compila).
4. E2E manual: Android con emulador + `docker compose`; iOS con `xcodebuild` + `xcrun simctl install/launch` + screenshot.
