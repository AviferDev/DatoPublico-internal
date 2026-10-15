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
| FT00009 | ingesta-job-diario | Job diario de ingesta idempotente | ingesta-boe | accepted |
| FT00010 | ingesta-observabilidad | Observabilidad de la ingesta diaria | ingesta-boe | accepted |
| FT00011 | backfill-historico | Backfill del histórico reciente | ingesta-boe | accepted |
| FT00012 | categorizacion-publicaciones | Clasificación por categoría y extracción de plazos | ingesta-boe | accepted |
| FT00013 | destacados-diarios | Destacados del día por ranking objetivo | relevancia | accepted |
| FT00014 | chunking-articulos | Fragmentación por artículo o sección | rag | accepted |
| FT00015 | embeddings-locales-onnx | Servicio de embeddings locales (ONNX) | rag | accepted |
| FT00016 | pgvector-indexado | Almacenamiento vectorial en pgvector | rag | accepted |
| FT00017 | recuperacion-hibrida | Recuperación híbrida de fragmentos | rag | accepted |
| FT00018 | evaluacion-recuperacion | Evaluación de recuperación (precision/recall) | rag | accepted |
| FT00019 | contrato-resumen-ciudadano | Contrato del resumen ciudadano | simplificacion-ia | accepted |
| FT00020 | generacion-resumen-go | Generación de resumen con OpenCode | simplificacion-ia | accepted |
| FT00021 | cacheo-resumenes | Cacheo de resúmenes y control de coste | simplificacion-ia | accepted |
| FT00022 | guardrails-anti-alucinacion | Guardrails anti-alucinación y trazabilidad | simplificacion-ia | accepted |
| FT00023 | cola-revision-confianza | Cola de revisión por baja confianza | simplificacion-ia | accepted |
| FT00024 | evaluacion-golden-set | Evaluación de calidad con golden set | simplificacion-ia | accepted |
| FT00025 | chat-generacion | Generación del chat RAG con OpenCode | simplificacion-ia | accepted |
| FT00026 | api-feed-diario | Endpoint del feed diario | api-publica | accepted |
| FT00027 | api-detalle-norma | Endpoint de detalle de publicación | api-publica | accepted |
| FT00028 | api-busqueda | Endpoint de búsqueda | api-publica | accepted |
| FT00029 | api-contratos-openapi | Contratos OpenAPI y versionado | api-publica | accepted |
| FT00030 | api-cors-ratelimit-errores | Endurecimiento HTTP de la API | api-publica | accepted |
| FT00031 | api-chat | Endpoint de chat RAG | api-publica | accepted |
| FT00032 | ui-feed | UI del feed con estados y dirección visual | cliente-cmp | accepted |
| FT00033 | ui-detalle | Pantalla de detalle con resumen y fuente | cliente-cmp | accepted |
| FT00034 | ui-navegacion-estado | Navegación y estado compartido | cliente-cmp | accepted |
| FT00034-PT1 | integracion-detalle-navegacion | Integrar el detalle real (FT00033) en la navegación | cliente-cmp | accepted |
| FT00035 | ui-cliente-http-cache | Cliente HTTP común y cache offline | cliente-cmp | accepted |
| FT00036 | ui-busqueda-filtros | UI de búsqueda con filtros | cliente-cmp | accepted |
| FT00037 | ui-chat | UI de chat RAG | cliente-cmp | accepted |
| FT00038 | dist-android | Empaquetado Android y preparación para Google Play | distribucion | not_started |
| FT00039 | dist-web | Despliegue web (Wasm) y enlaces compartibles | distribucion | in_progress |
| FT00040 | dist-ios | App iOS distribuible vía TestFlight | distribucion | not_started |
| FT00041 | deploy-backend | Despliegue del backend en servidor propio | operacion | accepted |
| FT00042 | observabilidad-y-backups | Observabilidad y backups de producción | operacion | not_started |
| FT00043 | accesibilidad-i18n | Accesibilidad y textos en español | operacion | not_started |
| FT00044 | legal-avisos | Avisos legales y disclaimer | operacion | not_started |
| FT00045 | beta-cerrada | Beta cerrada y corrección de bugs | operacion | not_started |
| FT00046 | publicacion-1.0.0 | Publicación pública 1.0.0 | operacion | not_started |
| FT00047 | english-identifiers-rename | Renombrado de identificadores a inglés | calidad | in_progress |
| FT00048 | cliente-http-detalle | Cliente HTTP del detalle de publicación | cliente-cmp | in_progress |
| FT00049 | operacion-generacion-resumenes | Generación one-shot de resúmenes ciudadanos y sesión de OpenCode | operacion | in_progress |
| FT00050 | dev-up-local | Script de arranque del entorno local (dev-up) | operacion | in_progress |
| FT00051 | web-full-viewport | Viewport completo en la Web (Wasm) | cliente-cmp | in_progress |
| FT00052 | release-actions | CI/CD de publicación con GitHub Actions (backend y apps) | operacion | in_progress |

## Siguiente FT libre

**FT00053**

## Partes

| PT | Feature | Alcance | Estado |
| --- | --- | --- | --- |
| FT00039-PT1 | dist-web | Build Wasm de producción con URL de API parametrizable (`-PapiBaseUrl`) + SEO del shell + servido estático | not_started |
| FT00039-PT2 | dist-web | Puente de URL Web (History API) para enlaces compartibles de detalle (ADR) | not_started |
| FT00052-PT1 | release-actions | Backend: imagen a GHCR + despliegue por SSH | accepted |
| FT00052-PT2 | release-actions | Web: build Wasm de producción + publicación en el Nginx del servidor | not_started |
| FT00052-PT3 | release-actions | Android: firma release + AAB a Google Play (internal) | not_started |
| FT00052-PT4 | release-actions | iOS: firma + archivo a TestFlight | not_started |
