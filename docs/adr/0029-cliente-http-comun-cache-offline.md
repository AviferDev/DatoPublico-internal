# ADR 0029: Cliente HTTP común del cliente CMP, DTOs anti-corrupción y cache offline en memoria

## Estado

Aceptado (2026-10-14). Decisión del dueño del proyecto al ejecutar
`ui-cliente-http-cache` (FT00035). Continúa el ADR 0027 (base del cliente CMP) y no
supersede ninguno.

## Contexto

El cliente Compose Multiplatform (FT00032/FT00033) usaba **datos de ejemplo** en
memoria y estaba deliberadamente **desacoplado de `:shared`** para no romper el
gate SDK-free (ADR 0027). FT00035 debía traer el **feed real** desde la API
(`/v1/feed`) y una **cache offline** básica.

Restricciones:

- `:shared` solo declara `jvm()`; consumirlo desde Android/iOS/Wasm exigiría
  añadirle targets KMP (y AGP), rompiendo el gate SDK-free.
- La **URL base** y la fecha del día son específicas de plataforma (emulador Android
  usa `10.0.2.2`; iOS/JVM/Wasm, `localhost`); `commonMain` no puede fijar `http://…`.
- Sin datos personales; sin persistencia entre arranques.

## Decisión

1. **Cliente HTTP común** en `core/network/` sobre **`ktor-client`** (3.0.3): motores
   por *source set* (okhttp/cio/darwin/js), `ContentNegotiation` con JSON,
   **`HttpTimeout`** explícito y `expectSuccess = false`.
2. **URL base y fecha por plataforma** con `expect/actual` (`Platform`), nunca en
   `commonMain`; `ApiConfig` inyectable. En Android, el manifest permite tráfico
   claro **solo** a `10.0.2.2`/`localhost` (`network_security_config.xml`).
3. **Capa anti-corrupción**: el cliente define sus **propios DTOs de wire**
   (`feature/feed/data/remote/`, sufijo `Dto`, `@SerialName` explícito) espejo de los
   de `:shared`, y un **mapeo puro** a los modelos de dominio del cliente. `:composeApp`
   **no** depende de `:shared` (se mantiene el gate SDK-free).
4. **Errores tipados** como valores (`ApiResult`/`ApiFailure`: `Network`/`Server(status,
   code)`/`InvalidBody`), con `CancellationException` relanzada; sin excepciones como
   camino de control.
5. **Cache offline en memoria**: puerto `FeedCache` + `InMemoryFeedCache`; éxito →
   cachea; fallo de red → sirve el último feed cacheado o `Failure`. Sin persistencia
   entre arranques y **sin datos personales**.
6. **Wiring mínimo**: `App()` construye el `HttpClient`/`FeedApi`/cache/repositorio; no
   se reestructuran la UI ni el estado (eso es FT00034).

## Alternativas consideradas

- **Cablear `:shared`** (añadir targets iOS/Wasm/Android): descartado; rompe el gate
  SDK-free.
- **Módulo KMP `:api-contract`** o `expect/actual` del contrato: descartado por
  duplicar/mover DTOs y generar churn en `:backend`.
- **Cache persistente (SQLDelight/fichero)**: descartado en esta feature (non-goal);
  la persistencia entre arranques es deuda futura.
- **Indicador de «sin conexión»**: descartado; toca `FeedUiState` (frontera con FT00034).

## Consecuencias

- Habilita el feed real y la resiliencia offline básica; deja el cliente listo para
  que FT00036/FT00037 reutilicen `core/network`.
- Coste asumido: **duplicación del contrato** de wire (mitigada por el mapeo puro y
  los tests con `MockEngine`); la cache no persiste; el feed real puede salir vacío
  hasta que se cablee el pipeline de resumen.
- Dependencias nuevas en `:composeApp`: `ktor-client-core/-content-negotiation`,
  `ktor-serialization-kotlinx-json`, plugin `kotlin.serialization`, motores por
  source set y `ktor-client-mock` en test (todas oficiales; **ninguna** de red en el
  gate SDK-free).
- Documentación afectada: `ARCHITECTURE.md` (§`:composeApp`), `CONSTRAINTS.md`
  (§«Cliente»), skill `compose-multiplatform-architecture`, `docs/desarrollo-local.md`.
