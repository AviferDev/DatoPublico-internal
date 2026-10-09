# Constraints — DatoPublico

> Reglas operativas **MUST / MUST NOT** que toda feature debe respetar. Añade
> aquí solo restricciones durables que futuras features deban cumplir.

## Producto y datos

- **MUST**: cada resumen publicado lleva enlace visible a la **fuente oficial**.
- **MUST NOT**: cuentas de usuario ni almacenamiento de datos personales.
- **MUST NOT**: analítica o telemetría de uso.
- **MUST**: el chat verifica **solo** contra el corpus del BOE (sin fuentes
  externas) y **no** persiste historial en el servidor.
- **MUST**: el aviso de contenido generado por IA es visible.
- **MUST NOT**: ingerir la **Sección IV (Administración de Justicia)** por incluir
  datos personales, ni la **Sección V.A (licitaciones)** (va a 1.x / PLACSP).

## IA y coste

- **MUST**: embeddings **locales** (`multilingual-e5-small` int8, ONNX), tras una
  interfaz de proveedor.
- **MUST**: generación y chat por **OpenCode**, tras una interfaz intercambiable;
  la clave vive **solo** en el servidor.
- **MUST**: cachear resúmenes por publicación y aplicar **rate limiting** al chat.
- **MUST NOT**: publicar afirmaciones fuera del contexto recuperado (si el corpus
  no lo sustenta, se declara `sin_fundamento`/`refutada`).

## Nombres y contratos

- **MUST**: en `:shared`, **todos los tipos serializables del contrato** llevan
  sufijo `Dto`: las `data class` (`PublicacionDto`, `ResumenDto`, `PlazoDto`,
  `ResumenDiarioDto`) y los **enums de wire** (`CategoriaDto`, `SeccionBoeDto`);
  la configuración de serialización no es un tipo de contrato y va sin `Dto`
  (`DatoPublicoJson`) y, en capas internas, entidades `...Entity`, filas `...Row`
  y modelos de UI `...Ui`, sin prefijos.

## Operación

- **MUST**: ingesta diaria a las **9:30** más una **segunda pasada**; alerta si no
  se ejecuta.
- **MUST**: migraciones Flyway versionadas; **nunca** editar una ya aplicada.
- **MUST**: el gate de build/tests (`./gradlew build`, `.harness/init.sh`) **no**
  depende de servicios externos (base de datos). Las migraciones se ejecutan con
  una tarea explícita (`./gradlew :backend:flywayMigrate`) y las tareas Flyway
  **nunca** se enganchan a `build`/`check` (la CI corre sin PostgreSQL).
- **MUST**: secretos por entorno (`.env` ignorado; nunca en el repositorio).
- **N100 / 8 GB**: backfill por lotes en baja carga; `shared_buffers` ~1 GB,
  heap JVM ~1 GB, swap activado.
