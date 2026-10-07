# Technical Discovery

## Product Surface

Cliente multiplataforma con **UI compartida**:

- Móvil: Android e iOS.
- Web (Wasm).
- Una sola base de UI en Compose Multiplatform.
- **Detalle de norma:** se muestra el **resumen ciudadano + enlace a la fuente**;
  no se integra el texto oficial completo.

## Candidate Stack

- **Lenguaje:** Kotlin end-to-end.
- **Backend:** Ktor (jobs programados, ingesta, RAG, API).
- **Cliente:** Compose Multiplatform (Android, iOS, Wasm).
- **Contratos:** `kotlinx.serialization` en módulo `shared`.
- **Persistencia:** PostgreSQL + `pgvector`.
- **Migraciones:** Flyway.
- **HTTP:** Ktor Client.
- **Concurrencia/estado:** coroutines, `StateFlow`, ViewModels compartidos.
- **Build:** Gradle Kotlin DSL con version catalog.
- **IA (proveedor):** interfaz de proveedor abstracta para poder cambiar sin
  tocar código.
  - Generación: **OpenCode Go**, endpoint OpenAI-compatible
    `https://opencode.ai/zen/go/v1/chat/completions`. Modelo candidato:
    `deepseek-v4.1-flash`.
  - Embeddings: **modelo local open-source** (`intfloat/multilingual-e5-small`
    por defecto, `-base` como alternativa) ejecutado con **ONNX Runtime en CPU**.

## Data and Storage

- PostgreSQL con la extensión `pgvector`.
- Entidades principales: `norma`, `fragmento` (con embedding), `resumen`,
  `cola_revision`.
- Migraciones con Flyway; backups periódicos.
- Índices vectoriales para búsqueda semántica y filtros SQL por metadatos
  (fecha, categoría, organismo).
- **Corpus:** normas nuevas de la **Sección I** del BOE, en **castellano**, más
  **backfill de los últimos 2 años**.

## Integrations

- **BOE:** API de datos abiertos (sumario diario) y textos oficiales.
- **OpenCode Go:** generación de resúmenes vía endpoint OpenAI-compatible.
- **Embeddings locales:** modelo multilingüe pequeño vía ONNX Runtime en el
  propio servidor.
- **Futuras (1.x):** BDNS, PLACSP/PRTR, INE, datos.gob.es, EUR-Lex/CELLAR, TED.

## Authentication and Authorization

- **Sin cuentas en ningún momento.** La API es pública de solo lectura y el
  servidor no almacena datos personales.
- **Watchlist local:** las leyes seguidas viven en el dispositivo; la app
  comprueba cambios al abrirse.
- **Push futuro (opcional):** si se añade, usará un **identificador anónimo de
  dispositivo** (token aleatorio), sin email ni nombre.
- La **clave de OpenCode Go** vive solo en el servidor (variable de entorno),
  nunca en el cliente.

## Deployment and Operations

- **Hosting propio:** servidor con **Intel N100 y 8 GB de RAM** (sin GPU).
- Orquestación con `docker-compose`.
- Job programado diario (cron) para la ingesta.
- Web desplegada como estático; backend como servicio.
- Ajustes de recursos: `shared_buffers` de PostgreSQL ~1 GB, heap JVM ~1 GB,
  swap activado.
- **Backfill por lotes** en horario de baja carga (el N100 lo vectoriza en
  horas, no en minutos).
- Secretos por entorno, HTTPS.

## Testing and Verification

- Tests unitarios del backend (ingesta, parsers, guardrails).
- Fixtures reales del BOE.
- **Golden set** para medir la calidad de los resúmenes.
- Pruebas de recuperación (precision/recall).
- Beta interna vía Play internal testing y TestFlight.

## Observability

- Logs estructurados.
- Alerta si falla la ingesta diaria.
- Métrica de resúmenes enviados a cola de revisión.
- **Sin analítica de uso** en la 1.0.0 (ni cookies ni telemetría de terceros).

## Constraints

- **Equipo:** una persona, a tiempo parcial, sin fecha fija.
- **Presupuesto:** cuota de OpenCode Go ($10/mes) + servidor propio (ya
  existente) + coste eléctrico.
- **Hardware:** N100 / 8 GB define el techo de CPU y RAM; la generación es
  remota para no cargar la CPU local.
- **Lenguas:** solo castellano en la 1.0.0.
- **Legal:** avisos de IA, disclaimer de no asesoramiento jurídico y
  trazabilidad a la fuente.
