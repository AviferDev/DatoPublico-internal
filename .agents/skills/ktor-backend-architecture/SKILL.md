---
name: ktor-backend-architecture
description: Guía de arquitectura del backend Kotlin + Ktor (módulo :backend) de Vuelantis. Úsala al añadir o modificar endpoints/plugs, servicios de aplicación, lógica de dominio, repositorios y migraciones (PostgreSQL/Flyway), caché (Redis), integraciones externas (Ignav), configuración por entorno, composición de dependencias, errores, observabilidad o tests. Define la dirección de dependencias, el layout de paquetes y las reglas para que el código sea limpio, ordenado y mantenible, y distingue el patrón objetivo del estado actual del repositorio.
---

# Arquitectura del backend Ktor

Guía práctica para trabajar en `:backend`. Antes de tocar el backend, lee también `docs/technical-discovery.md`, `docs/domain-model.md` y `docs/user-and-access-model.md` si la feature toca acceso o cuota. `CONTEXT.md` fija el lenguaje de dominio: usa esos términos.

**Estado actual:** en `main` el backend todavía no existe (fase pre-bootstrap; el servidor Ktor llega con `backend-bootstrap`). El patrón que se describe aquí es el **objetivo acordado**, derivado del stack decidido en `docs/technical-discovery.md` y de la implementación de referencia previa en la rama `feat/backend-bootstrap`. No inventes una arquitectura distinta: sigue estas reglas y, cuando el código exista, deriva los detalles reales del propio código.

## Stack y topología de build (decidido)

- Kotlin/JVM (toolchain **JDK 21**) + **Ktor 3.x con motor Netty**; `application` plugin de Gradle con `mainClass = es.aviferdev.vuelantis.backend.ApplicationKt`.
- `:backend` es un módulo Gradle dentro del multi-proyecto de la raíz; DSL de Kotlin. No usa version catalog salvo que ya exista.
- Serialización con `kotlinx.serialization` + `ktor-serialization-kotlinx-json`; corrutinas para I/O paralelo.
- Persistencia **PostgreSQL** (JDBC + HikariCP; migraciones **Flyway**); caché **Redis** (Lettuce).
- Infra local con **Docker Compose** (`postgres`, `redis`, `backend`) y `Dockerfile` multi-stage.
- Gate estándar: `./init.sh` (no arranca servidores). Compilación/tests: `./gradlew :backend:build` y `./gradlew :backend:test`.

## Regla de dependencia (invariante)

```
plugins/ (HTTP Ktor)  ->  <feature>/ servicios de aplicación  ->  <feature>/ dominio puro
                                     |                                      ^
                                     v                                      |
                         <feature>/ repositorios y clientes  -->  infra/ (config, pools, migraciones)
```

- La capa HTTP (`plugins/`) conoce Ktor y los DTOs de transporte; **no** contiene lógica de negocio.
- Los **servicios** orquestan (validación de estado, coordinación de I/O, transacciones lógicas). No conocen tipos de Ktor (`ApplicationCall`, `Route`, `HttpStatusCode`).
- La **lógica de dominio** es pura: sin E/S, sin Ktor, sin base de datos, sin Redis. Es lo más fácil de testear. Ejemplo de referencia: el cruce open-jaw (`combine/OpenJawCombiner`) es un `object` sin estado que recibe listas y devuelve combinaciones.
- Los **repositorios y clientes** implementan interfaces declaradas por el consumidor (servicio); encapsulan SQL o HTTP y traducen a modelos de dominio.
- Prohibido: una ruta que consulte la BD directamente; un servicio que importe `io.ktor.server.*`; dominio que dependa de JDBC, Redis o Ignav.

## Layout de paquetes (feature-first con roles)

```
backend/src/main/kotlin/es/vuelantis/backend/
  Application.kt          # composition root: config, wiring manual y arranque
  plugins/                # Ktor: configureSerialization/Routing, routes por área, auth, CORS, health, observability, docs
  <feature>/              # p. ej. access/, catalog/, search/, combine/, ignav/, cache/
  infra/                  # InfraConfig, DataSource/Hikari, RedisClient, Migrations, Readiness
backend/src/main/resources/
  db/migration/           # Flyway: V1__descripcion.sql, V2__..., nunca editar una ya aplicada
  openapi/openapi.json    # contrato OpenAPI servido por Swagger (bandera ENABLE_API_DOCS)
  logback.xml
backend/src/test/kotlin/es/vuelantis/backend/   # tests espejo del paquete de producción
```

Un paquete por feature, no por capa técnica. Dentro del paquete conviven su servicio, su(s) repositorio(s), sus modelos y sus clientes; las piezas transversales (config, DB, HTTP) van en `infra/` y `plugins/`.

## Composition root y wiring (manual, sin framework de DI)

- Todo el cableado vive en `Application.kt`. No se usa Koin/Hilt/Spring en el backend.
- Cada subsistema se construye **condicionalmente** según sus dependencias (configuración de entorno, `dataSource`, cliente de Ignav, etc.) y puede quedar a `null` si falta.
- El arranque **solo registra las rutas cuyas dependencias existen**; el `configureRouting(...)` recibe colaboradores opcionales y decide qué montar. Así el servidor arranca en entornos parciales (p. ej. solo salud) sin `NullPointerException`.
- Los recursos con ciclo de vida (pool JDBC, Redis, cliente HTTP de Ignav) se cierran en un `finally` al parar el servidor.
- No inyectes dependencias por variables globales/mutable state: pásalas por constructor.
- `configureRouting`/`configureX` reciben colaboradores (no `Application` mutable); las routes se declaran como `fun Route.xRoutes(dep)`.

```kotlin
// Patrón del composition root
val infra = Infrastructure.fromEnv()
infra.dataSource?.let { Migrations.migrate(it) }          // idempotente
val repo = infra.dataSource?.let { JdbcXRepository(it) }
val service = repo?.let { XService(it, someClient) }
embeddedServer(Netty, port, host) {
    configureSerialization()
    configureRouting(xService = service)                  // la ruta se registra solo si no es null
}.start(wait = true)
```

## Configuración por entorno

- Un `data class` por grupo de configuración, con `companion object` que declara las constantes de variable de entorno y un `fromEnv(env: Map<String, String> = System.getenv())`.
- Dos variantes cuando tenga sentido:
  - `fromEnvOrNull()`: devuelve `null` si falta lo esencial → el subsistema queda deshabilitado.
  - `fromEnv()`: lanza `IllegalStateException` con mensaje claro si falta → obligatorio para una CLI/tarea.
- **Nunca** secretos con valor por defecto en el repo ni en el código. Valores no secretos con default sí (p. ej. TTL, puerto).
- Los tests deben poder inyectar `env` como `Map`, por eso el parámetro `env` es explícito y no lee `System.getenv()` directamente dentro de la lógica.

## Endpoints y Ktor

- Un archivo de routes por área en `plugins/` (p. ej. `Search.kt`, `Auth.kt`, `Health.kt`), siempre como `fun Route.xRoutes(...)`.
- `configureSerialization()` instala `ContentNegotiation` con `Json { ignoreUnknownKeys = true; encodeDefaults = true }`.
- Valida y parsea en la frontera: `call.receive<T>()` en `try/catch` → `400` con `ErrorResponse`; los errores de validación del modelo también → `400`. No dejes escapar la excepción cruda.
- Usa un `@Serializable data class ErrorResponse(@SerialName("error") val error: String)` común; responde siempre JSON.
- Todo tipo `@Serializable` (DTOs de transporte, *requests*, *responses* y los de `:shared`) anota **todas** sus propiedades con `@SerialName` explícito, **aunque el nombre JSON coincida** con el de la propiedad Kotlin: fija el contrato de cable y evita que un renombrado Kotlin lo cambie por accidente. `@Transient` es la única exclusión, deliberada.
- **Nunca** expongas mensajes internos de excepción, stacktraces ni datos sensibles. Traduce a un mensaje de dominio.
- Códigos consistentes: `400` validación/JSON, `401` sin autenticar, `403` sin permiso, `404` no encontrado, `409` conflicto (p. ej. email duplicado), `429` rate limit, `5xx` fallo inesperado.
- Rutas protegidas con `ktor-server-auth`: valida el token en el servidor (`JWT`), resuelve el usuario/plan en la BD, nunca confíes en datos que vengan del cliente.
- El contrato HTTP vive en `resources/openapi/openapi.json`; actualízalo al añadir/cambiar endpoints y mantenlo cubierto por un test.

## Servicios de aplicación

- Clase con colaboradores por constructor; métodos `suspend` cuando hacen I/O.
- Orquestan: resuelven entradas, coordinan repositorios/clientes, aplican reglas de estado y devuelven modelos de dominio o un resultado tipado.
- **No** conocen Ktor ni el transporte. Si necesitan abortar por una regla, lanzan una excepción de dominio tipada y es la capa HTTP quien la mapea a un código.
- Prefieren delegar la lógica pura en `object`/funciones de dominio sin E/S (testeables sin mocks).

## Persistencia (PostgreSQL + JDBC + Flyway)

- Declara una **interface** (`UserRepository`) y una implementación `JdbcXRepository(dataSource)`.
- Todo acceso a JDBC va dentro de `withContext(Dispatchers.IO)`.
- Usa `dataSource.connection.use { }`, `prepareStatement(...)` con parámetros (`?`, nunca concatenar SQL) y `executeQuery/executeUpdate`.
- Mapea `ResultSet` → modelo de dominio en funciones privadas; no filtres filas de BD a la capa HTTP.
- SQL en `private companion object` como constantes; nada de SQL suelto disperso.
- Traduce errores de BD a excepciones tipadas (p. ej. violación de unicidad `SQLState 23505` → `EmailAlreadyExistsException`); no propagues `SQLException` a la API.
- Migraciones **Flyway** en `resources/db/migration` con nombre `V<n>__descripcion.sql`. Se aplican idempotentemente al arrancar y con `./gradlew :backend:migrate`. **Nunca** edites una migración ya aplicada: añade una nueva.
- Los tests de integración que tocan BD real se **saltan** si falta `DATABASE_URL` (`assumeTrue`) y limpian sus filas en `finally`.

## Integraciones externas (Ignav y similares)

- Modela el proveedor como **interface** (`IgnavClient`) + implementación Ktor (`KtorIgnavClient(httpClient, config)`). El consumidor depende de la interface.
- Inyecta el `HttpClient` para poder usar `MockEngine` en tests; no crees el cliente dentro de la función de negocio.
- Cabeceras/secretos del proveedor (`X-Api-Key`) se añaden en el cliente del backend y **nunca** salen al cliente móvil.
- Mapea el DTO del proveedor a un modelo de dominio propio en la frontera del cliente.
- Envuelve fallos en una excepción tipada (`IgnavException`) con contexto útil, pero:
  - **re-lanza siempre `CancellationException`** antes de capturar `Exception` (invariante de corrutinas);
  - no incluyas la API key ni cuerpos sensibles en el mensaje ni en logs.
- Tolera fallos parciales: un tramo que falla no debe tumbar toda la búsqueda cuando el negocio admita resultados parciales.

## Caché (Redis) y decoradores

- La caché se implementa como **decorador** sobre el cliente (`CachingIgnavClient(base, cache, ttl)`), no dentro del cliente base.
- Clave explícita y estable por (origen, destino, fecha, mercado, clase); TTL configurable por entorno.
- **Single-flight**: ante consultas concurrentes idénticas, una sola llamada al proveedor (p. ej. `Mutex` + `Deferred`).
- La caché **degrada** de forma controlada: si Redis falla, se sigue funcionando contra el proveedor (o se reporta `cacheUnavailable`), nunca se rompe la petición.
- Expón una operación de lectura sin red (p. ej. `lookup`) para cotizaciones/estimaciones que no deben gastar cuota del proveedor.

## Concurrencia

- Usa corrutinas y `coroutineScope`/`async` para I/O paralelo con **concurrencia acotada** (semáforo/límite configurable). El volumen del proveedor se controla en el backend.
- I/O bloqueante (JDBC, Lettuce sync) siempre sobre `Dispatchers.IO`.
- Re-lanza `CancellationException`; nunca la tragues. Nada de `GlobalScope`.
- Trabajos largos (p. ej. una búsqueda asíncrona sobre muchos aeropuertos) se ejecutan fuera de la petición, con estado/progreso consultable y soporte de cancelación (ver `docs/technical-discovery.md`, sección Search Execution).

## Observabilidad

- `CallId` (cabecera `X-Request-Id` o UUID), `CallLogging` y métricas Micrometer/Prometheus.
- Logs estructurados (logback) con correlación por petición/trabajo; **nunca** loguees contraseñas, hashes, tokens ni la API key.
- Expón `GET /metrics` cuando la observabilidad esté configurada.

## Seguridad (invariantes del proyecto)

- La API key de Ignav y los secretos (`JWT_SECRET`, etc.) viven **solo** en el backend, leídos del entorno; nunca en el repo ni en el cliente.
- Contraseñas siempre con hash fuerte; nunca en claro, nunca devueltas, nunca logueadas.
- Valida el JWT en toda ruta protegida; resuelve identidad/permisos en el servidor.
- No añadas una ruta nueva sin su test de rechazo (sin credenciales / credenciales inválidas).

## Tests (JUnit 5 + kotlin.test)

- Tests espejo en `src/test/kotlin`; ejecuta con `./gradlew :backend:test` (tarea con `useJUnitPlatform()`).
- **Rutas/HTTP**: `testApplication { application { configureSerialization(); configureRouting(...) } }` con dependencias simuladas; comprueba código y cuerpo. Es el patrón para validación, auth y contratos.
- **Dominio/servicios**: unit tests puros con dobles (fakes) de repositorio/cliente; sin red ni contenedores.
- **Integración con proveedor**: `MockEngine` de Ktor; **nunca** Ignav real ni cuota real.
- **Integración con BD/Redis**: `assumeTrue(env presente)` + limpieza; no fallan en local sin infraestructura.
- Añade tests de regresión al arreglar un bug. Un endpoint nuevo sin test de camino feliz y de error no está terminado.

## Reglas al cambiar el backend

- **Crea el paquete/rol que falte.** Si el código pertenece a un paquete feature-first o a un rol (`plugins/`, `infra/`, `<feature>/`) que aún no existe, créalo y coloca ahí el código; no lo dejes suelto en otro paquete ni inventes una estructura nueva.
- **Reutiliza y mantén las funciones pequeñas.** Extrae servicios/funciones reutilizables en vez de duplicar. Límite duro de **40 líneas** por función (objetivo 30; sin KDoc, comentarios ni blancos); una función con varias responsabilidades se divide.
- **Un solo `return` por función.** Cada función tiene un único punto de salida: usa el cuerpo de expresión (`=`) o un `when`/`if` como expresión; sin `return` tempranos. Aplica al dominio, aplicación, infra y routes.
- **Sin `else if`.** Las cadenas de guardas se escriben con un `when` (como expresión o sentencia), nunca con `if / else if / else`; un `if` simple de dos ramas sigue permitido.
- Respeta la dirección de dependencias; no metas Ktor en dominio ni SQL en las routes.
- Monta rutas y subsistemas **condicionalmente** según configuración; no asumas que PostgreSQL/Redis/Ignav están siempre presentes.
- Toda configuración nueva se lee por `fromEnv`/`fromEnvOrNull`; documenta la variable en `.env.example` (sin valor secreto).
- Esquema de BD: siempre una migración nueva, nunca editar una aplicada.
- Mantén `openapi.json` alineado con los endpoints y con su test.
- No introduzcas un framework de DI, ni estado global mutable, ni dependencias sin justificar.
- No expongas secretos ni ignores `CancellationException`.
- Si estableces o cambias módulos, capas, superficies de ejecución o la dirección de dependencias, actualiza `ARCHITECTURE.md`; si aparece una regla MUST/MUST NOT durable, añádela a `CONSTRAINTS.md`.

## Cómo verificar antes de dar por hecho un cambio

1. `./gradlew :backend:test` — tests unitarios, de routes e integración simulada.
2. `./gradlew :backend:build` — compila todo el módulo (mismo gate que `./init.sh`).
3. `./gradlew :backend:migrate` (con `DATABASE_URL`) — la migración aplica y reaplica sin errores.
4. `docker compose up` + `curl -i localhost:8080/health` — el servidor arranca y responde (y `GET /health/ready` si hay infraestructura).
5. Comprueba que no se ha consumido cuota real de Ignav durante los tests.

## Errores comunes

1. **Lógica de negocio en la route**: `post("/api/...")` con SQL o reglas dentro. Corrección: extrae a un servicio y deja la route como validación + mapeo.
2. **Dominio acoplado a infraestructura**: el combinador importa Ktor/JDBC. Corrección: mantenlo puro y pasa modelos por parámetro.
3. **Dependencia obligatoria de un subsistema**: la ruta se registra siempre y revienta si no hay BD/proveedor. Corrección: wiring condicional + colaboradores opcionales.
4. **Editar una migración ya aplicada**: rompe entornos existentes. Corrección: añade `V<n+1>__...sql`.
5. **Tragarse `CancellationException`** al capturar `Exception` en un cliente. Corrección: re-lanzarla primero.
6. **Loguear o devolver secretos**: API key, tokens, hashes o contraseñas en logs/respuestas. Corrección: nunca loguear; mensajes genéricos.
7. **Consumir Ignav real en tests**: coste y flakiness. Corrección: `MockEngine` y `assumeTrue` para integraciones.
8. **Añadir un framework de DI** "porque Clean Architecture lo pide": aquí el wiring es manual y explícito. Corrección: respeta el composition root.
