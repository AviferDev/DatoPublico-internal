# Architecture — DatoPublico

> Mapa durable de módulos y fronteras. **No** es un inventario de ficheros. El
> detalle por módulo vive en las skills `ktor-backend-architecture`,
> `compose-multiplatform-architecture` y `rag-datapublico`.

## Módulos (monorepo Gradle)

- **`:shared`** — DTOs y lógica compartida con `kotlinx.serialization`.
  Namespace `es.aviferdev.datopublico`.
- **`:backend`** — Ktor: ingesta del BOE, RAG, resúmenes, destacados y API.
  Namespace `es.aviferdev.datopublico.backend`.
- **`:composeApp`** — cliente Compose Multiplatform (Android, iOS, Web).
  Namespace `es.aviferdev.datopublico`.

## Fronteras

- **Cliente → API HTTP** (público, solo lectura). El cliente no conoce los
  internals del backend.
- **Backend:** `plugins/` (HTTP) → servicios → dominio puro → repositorios y
  clientes → `infra/`.
- **IA:** embeddings **locales** (ONNX) y generación/chat **remoto** (OpenCode),
  cada uno tras una interfaz intercambiable.
- **Datos:** PostgreSQL + pgvector; migraciones Flyway. Sin cuentas ni datos
  personales.

## Reglas transversales

- El dominio es puro (sin Ktor, JDBC, ONNX ni HTTP).
- **Trazabilidad** obligatoria: todo resumen apunta a la fuente oficial.
- Secretos y claves **solo** por entorno, en el servidor.
- El texto de UI vive en recursos y en castellano.

## Convenciones de nombres

- En **`:shared`**, los **contenedores de datos** del contrato de transporte
  llevan sufijo **`Dto`** (p. ej. `PublicacionDto`, `ResumenDto`, `PlazoDto`,
  `ResumenDiarioDto`).
- Los **enums de vocabulario/tokens de wire** van **sin sufijo** (`Categoria`,
  `SeccionBoe`): su token es contrato y no debe disfrazarse de DTO.
- La **configuración de serialización** (`DatoPublicoJson`) va sin `Dto`.
- En las capas internas: entidades `...Entity`, filas `...Row`, modelos de UI
  `...Ui`.
- **Sin prefijos** (nada de notación húngara).
