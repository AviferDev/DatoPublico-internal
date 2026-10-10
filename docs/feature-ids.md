# Feature IDs — DatoPublico

> Registro de identificadores de tarea. Las reglas están en la skill
> `feature-task-ids`; este documento mantiene la tabla y el siguiente libre.

## Convención

- **Feature:** `FT` + 5 dígitos (`FT00001`). Se asigna una vez; **nunca** se
  reutiliza ni se renumera.
- **Parte:** `<FT>-PT<n>` (`FT00001-PT1`) cuando una feature se divide en varios
  PR (varias capas o más de 30 ficheros).
- El `ft_id` vive en `feature_list.json` (campo `ft_id`, tras `id`) y en la
  cabecera de su spec (`docs/specs/<feature-id>.md`).

## Asignaciones

| FT | Feature id | Título | Área | Estado |
| --- | --- | --- | --- | --- |
| FT00001 | bootstrap-monorepo-gradle | Estructura del monorepo Gradle | fundaciones | accepted |
| FT00002 | bootstrap-shared-dtos | DTOs compartidos con kotlinx.serialization | fundaciones | accepted |
| FT00003 | bootstrap-postgres-pgvector | PostgreSQL + pgvector en docker-compose | fundaciones | accepted |
| FT00004 | bootstrap-ktor-healthcheck | Esqueleto Ktor con healthcheck | fundaciones | accepted |
| FT00005 | bootstrap-cmp-targets | Esqueleto Compose Multiplatform (Android, Web, iOS) | fundaciones | accepted |
| FT00006 | boe-sumario-cliente | Cliente del sumario diario del BOE | ingesta-boe | accepted |
| FT00007 | boe-parser-publicacion | Parser de publicaciones (metadatos y texto) | ingesta-boe | accepted |
| FT00008 | publicacion-persistencia | Persistencia de publicaciones, fragmentos y resúmenes | ingesta-boe | accepted |
| FT00009 | ingesta-job-diario | Job diario de ingesta idempotente | ingesta-boe | not_started |
| FT00010 | ingesta-observabilidad | Observabilidad de la ingesta diaria | ingesta-boe | not_started |
| FT00011 | backfill-historico | Backfill del histórico reciente | ingesta-boe | not_started |
| FT00012 | categorizacion-publicaciones | Clasificación por categoría y extracción de plazos | ingesta-boe | not_started |
| FT00013 | destacados-diarios | Destacados del día por ranking objetivo | relevancia | not_started |
| FT00014 | chunking-articulos | Fragmentación por artículo o sección | rag | not_started |
| FT00015 | embeddings-locales-onnx | Servicio de embeddings locales (ONNX) | rag | not_started |
| FT00016 | pgvector-indexado | Almacenamiento vectorial en pgvector | rag | not_started |
| FT00017 | recuperacion-hibrida | Recuperación híbrida de fragmentos | rag | not_started |
| FT00018 | evaluacion-recuperacion | Evaluación de recuperación (precision/recall) | rag | not_started |
| FT00019 | contrato-resumen-ciudadano | Contrato del resumen ciudadano | simplificacion-ia | not_started |
| FT00020 | generacion-resumen-go | Generación de resumen con OpenCode | simplificacion-ia | not_started |
| FT00021 | cacheo-resumenes | Cacheo de resúmenes y control de coste | simplificacion-ia | not_started |
| FT00022 | guardrails-anti-alucinacion | Guardrails anti-alucinación y trazabilidad | simplificacion-ia | not_started |
| FT00023 | cola-revision-confianza | Cola de revisión por baja confianza | simplificacion-ia | not_started |
| FT00024 | evaluacion-golden-set | Evaluación de calidad con golden set | simplificacion-ia | not_started |
| FT00025 | chat-generacion | Generación del chat RAG con OpenCode | simplificacion-ia | not_started |
| FT00026 | api-feed-diario | Endpoint del feed diario | api-publica | not_started |
| FT00027 | api-detalle-norma | Endpoint de detalle de publicación | api-publica | not_started |
| FT00028 | api-busqueda | Endpoint de búsqueda | api-publica | not_started |
| FT00029 | api-contratos-openapi | Contratos OpenAPI y versionado | api-publica | not_started |
| FT00030 | api-cors-ratelimit-errores | Endurecimiento HTTP de la API | api-publica | not_started |
| FT00031 | api-chat | Endpoint de chat RAG | api-publica | not_started |
| FT00032 | ui-feed | UI del feed con estados y dirección visual | cliente-cmp | not_started |
| FT00033 | ui-detalle | Pantalla de detalle con resumen y fuente | cliente-cmp | not_started |
| FT00034 | ui-navegacion-estado | Navegación y estado compartido | cliente-cmp | not_started |
| FT00035 | ui-cliente-http-cache | Cliente HTTP común y cache offline | cliente-cmp | not_started |
| FT00036 | ui-busqueda-filtros | UI de búsqueda con filtros | cliente-cmp | not_started |
| FT00037 | ui-chat | UI de chat RAG | cliente-cmp | not_started |
| FT00038 | dist-android | Empaquetado Android y preparación para Google Play | distribucion | not_started |
| FT00039 | dist-web | Despliegue web (Wasm) y enlaces compartibles | distribucion | not_started |
| FT00040 | dist-ios | App iOS distribuible vía TestFlight | distribucion | not_started |
| FT00041 | deploy-backend | Despliegue del backend en servidor propio | operacion | not_started |
| FT00042 | observabilidad-y-backups | Observabilidad y backups de producción | operacion | not_started |
| FT00043 | accesibilidad-i18n | Accesibilidad y textos en español | operacion | not_started |
| FT00044 | legal-avisos | Avisos legales y disclaimer | operacion | not_started |
| FT00045 | beta-cerrada | Beta cerrada y corrección de bugs | operacion | not_started |
| FT00046 | publicacion-1.0.0 | Publicación pública 1.0.0 | operacion | not_started |

## Siguiente FT libre

**FT00047**
