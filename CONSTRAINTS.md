# Constraints — DatoPublico

> Reglas operativas **MUST / MUST NOT** que toda feature debe respetar. Añade
> aquí solo restricciones durables que futuras features deban cumplir.

## Producto y datos

- **MUST**: cada resumen publicado lleva enlace visible a la **fuente oficial**.
- **MUST NOT**: cuentas de usuario ni almacenamiento de datos personales **de
  quien usa la app** (nada de perfiles); el contenido del BOE es información
  pública y **nunca se restringe**.
- **MUST NOT**: analítica o telemetría de uso.
- **MUST**: el chat verifica **solo** contra el corpus del BOE (sin fuentes
  externas) y **no** persiste historial en el servidor.
- **MUST**: el aviso de contenido generado por IA es visible.
- **MUST**: el corpus de la 1.0.0 es **todo el sumario del BOE** (secciones I,
  II.A, II.B, III, IV, V.A, V.B y V.C) y se usan **todos los campos** que ofrece
  la API. Ninguna sección ni campo del BOE se excluye por «datos personales» ese
  principio aplica solo a los datos de los usuarios de la app.

## IA y coste

- **MUST**: embeddings **locales** (`multilingual-e5-small` int8, ONNX), tras una
  interfaz de proveedor.
- **MUST**: generación y chat por **OpenCode**, tras una interfaz intercambiable;
  la clave vive **solo** en el servidor.
- **MUST**: cachear resúmenes por publicación y aplicar **rate limiting** al chat.
- **MUST NOT**: publicar afirmaciones fuera del contexto recuperado (si el corpus
  no lo sustenta, se declara `sin_fundamento`/`refutada`).

## Nombres y contratos

- **MUST**: **todo tipo `@Serializable`/de transporte** lleva sufijo `Dto`: el
  contrato de `:shared` — las `data class` (`PublicacionDto`, `ResumenDto`,
  `PlazoDto`, `ResumenDiarioDto`) y los **enums de wire** (`CategoriaDto`,
  `SeccionBoeDto`) — y también los DTOs de transporte de `:backend`
  (`HealthDto`, `BoeSumarioResponseDto`, `BoeSeccionDto`…). La configuración de
  serialización no es un tipo de contrato y va sin `Dto` (`DatoPublicoJson`).
- **MUST**: en las capas internas, entidades de persistencia `...Entity`, filas
  `...Row` y modelos de UI `...Ui`. Un **modelo de dominio/valor interno** que no
  sea serializable ni `Entity`/`Row`/`Ui` va **sin sufijo** (p. ej.
  `EntradaSumario`). Sin prefijos en ningún caso.

## Serialización (kotlinx.serialization)

- **MUST**: en todo tipo `@Serializable`, **cada propiedad** lleva `@SerialName`
  explícito, **aunque el nombre Kotlin coincida** con la clave JSON; no se confía
  en el nombre por defecto. Aplica al contrato de `:shared` y a los DTOs de
  transporte de `:backend`. Los valores de los enums de wire también llevan su
  `@SerialName`.

## Estilo de código

- **MUST**: cada función/método tiene **una sola salida** (`return` único);
  prohibido el *early return* (retornos intermedios). Se resuelve con expresiones
  (`when`, operador Elvis, `if`/`else` como expresión, `buildList`, etc.). Aplica
  **también a los tests**. Los códigos de salida temprana de lambdas etiquetadas
  (`return@…`, p. ej. `return@runTest`) se evitan igualmente: usa guardas `if` y
  deja el cuerpo sin salidas etiquetadas.

## Cliente (Compose Multiplatform)

- **MUST**: la **UI compartida** de `:composeApp` vive en `commonMain`; cada
  plataforma aporta **solo su entrypoint** (Android `MainActivity`, Wasm `main()`,
  iOS `MainViewController`). No duplicar pantallas por plataforma.
- **MUST**: el gate estándar (`./gradlew build`, `.harness/init.sh`) **no** exige
  Xcode ni un navegador. Los targets iOS se ignoran en hosts no-Apple y los tests
  de Wasm en navegador (Karma/Chrome) quedan fuera del gate.

## Build y repositorios

- **MUST**: las distribuciones de herramientas de Kotlin/JS-Wasm (Binaryen, Node,
  Yarn) se declaran como repositorios Ivy en `settings.gradle.kts`, que usa
  `RepositoriesMode.PREFER_SETTINGS`. El plugin de Kotlin/Wasm las registra a
  nivel de proyecto, así que `FAIL_ON_PROJECT_REPOS` rompería el build. Mantén el
  settings como **fuente única de verdad** de repositorios.

## Operación

- **MUST**: ingesta diaria a las **9:30** más una **segunda pasada**; alerta si no
  se ejecuta.
- **MUST**: migraciones Flyway versionadas; **nunca** editar una ya aplicada.
- **MUST**: el gate de build/tests (`./gradlew build`, `.harness/init.sh`) **no**
  depende de servicios externos (base de datos). Las migraciones se ejecutan con
  una tarea explícita (`./gradlew :backend:flywayMigrate`) y las tareas Flyway
  **nunca** se enganchan a `build`/`check` (la CI corre sin PostgreSQL).
- **MUST**: los tests del gate (`./gradlew build`, `./gradlew test`,
  `.harness/init.sh`) **no** hacen **llamadas de red**. Cualquier prueba contra un
  servicio externo (p. ej. la API de datos abiertos del BOE) es **opt-in** por
  variable de entorno y queda **fuera** de `build`/`test`/`init.sh` y de la CI;
  sin la variable, el test se omite sin abrir sockets (`BOE_LIVE_TEST=1`).
- **MUST NOT**: incluir credenciales en ficheros versionados, **ni siquiera de
  desarrollo** (sin contraseñas literales ni como *fallback* en código, compose,
  CI o plantillas). La única fuente es el entorno/`.env` (ignorado por git); la
  plantilla `.env.example` solo admite *placeholders* explícitos no secretos.
- **MUST**: un secreto ausente debe **fallar con mensaje claro** (fail-fast), no
  caer en un valor por defecto silencioso. `POSTGRES_PASSWORD` es obligatorio en
  `docker-compose` (`:?`) y la contraseña de Flyway no tiene default en el build
  (usa `FLYWAY_PASSWORD` o `POSTGRES_PASSWORD`).
- **MUST NOT**: duplicar la configuración de conexión entre herramientas. Las
  piezas de conexión tienen una **única fuente de verdad** (`POSTGRES_*`, la
  misma que consume `docker-compose`) y las variables propias de cada herramienta
  (`FLYWAY_*`) son solo *overrides* opcionales: cambiar `POSTGRES_PORT` (o
  host/db/usuario) debe bastar para que Flyway apunte al mismo sitio.
- **MUST**: el PostgreSQL local de desarrollo se publica **solo en loopback**
  (`127.0.0.1`), nunca en `0.0.0.0`.
- **MUST**: el arranque del backend **no** depende de la base de datos ni de
  servicios externos: se registran solo los subsistemas/rutas cuyas dependencias
  existen (el healthcheck `GET /health` queda operativo sin PostgreSQL). La
  configuración es **por entorno**, con valores por defecto no sensibles y
  **fail-fast** (arranque abortado con mensaje claro) si un valor es inválido.
- **N100 / 8 GB**: backfill por lotes en baja carga; `shared_buffers` ~1 GB,
  heap JVM ~1 GB, swap activado.
