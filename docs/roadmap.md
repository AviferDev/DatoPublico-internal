# Roadmap por versiones — DatoPublico

> Estado: **derivado del discovery cerrado**. Refleja las decisiones del brief
> (`docs/build-brief.md`) y puede ajustarse conforme avance la implementación.

## 1. Objetivo del documento

Dividir todo el trabajo del proyecto en versiones incrementales, con un objetivo
claro y un criterio de salida por versión, de forma que cada paso acerque a la
`1.0.0`. La **`1.0.0` es la versión que sale a producción**.

## 2. Supuestos y decisiones

- **Producto:** consulta, simplificación y seguimiento de legislación oficial
  (España) con IA sobre un RAG.
- **Usuario principal:** ciudadano general de España, sin perfil segmentado en la
  primera etapa.
- **Núcleo del MVP:** "qué cambia una ley y cómo me afecta".
- **Vía principal de entrada:** feed diario de novedades.
- **Stack:** Kotlin end-to-end.
  - Backend: **Ktor** (jobs programados, ingesta de APIs, RAG).
  - Cliente: **Compose Multiplatform**, con **UI compartida** en `commonMain`
    para Android, Web (Wasm) e iOS.
  - Módulo `shared`: DTOs y lógica compartida, serializada con
    `kotlinx.serialization`.
  - Persistencia: **PostgreSQL + `pgvector`** (metadatos + embeddings).
  - IA: generación con **OpenCode Go** (endpoint OpenAI-compatible,
    `deepseek-v4.1-flash` como candidato) y **embeddings locales**
    (`multilingual-e5-small` vía ONNX) en el servidor.
- **Plataformas del producto:** Android, Web e iOS. **iOS es obligatorio en la
  `1.0.0`.**
- **Alcance de la `1.0.0` (producción):** BOE estatal (Sección I), resúmenes IA
  con enlace a la fuente, feed diario, búsqueda básica, clientes Android + Web +
  iOS, **sin cuentas de usuario**.
- **Fuera de la `1.0.0`** (va a la serie `1.x`): CCAA, UE, cuentas/watchlist,
  oposiciones y plazos, subvenciones y licitaciones, contexto estadístico,
  fact-checker, simulador de impacto, chat RAG y dossiers PDF.
- **"Cambio" en 1.0.0:** solo normas nuevas publicadas cada día (Sección I del
  BOE); no se gestionan modificaciones de normas existentes.
- **Corpus de búsqueda:** backfill del histórico reciente (últimos 2 años).
- **Publicación:** automática con guardrails, aviso de IA y trazabilidad, más
  una cola de revisión interna para casos de baja confianza.
- **Sostenibilidad:** gratuito de interés público (subvenciones/donaciones).
- **Equipo:** una persona, a tiempo parcial y sin fecha fija.
- **Diseño:** dirección visual inicial definida en `DESIGN.md`.
- **Contenido del feed:** todas las normas nuevas de la Sección I. Detalle =
  resumen ciudadano + enlace a la fuente.
- **Lenguas:** solo castellano.
- **"A quién afecta":** colectivos amplios.
- **Analítica:** sin telemetría de uso en la 1.0.0.
- **Sin cuentas ni datos personales:** el servidor solo almacena datos públicos.
  El watchlist será local; un futuro push usaría un ID anónimo de dispositivo.
- **Hosting:** servidor propio (Intel N100, 8 GB RAM).

## 3. Convenciones

- **Versionado semántico.** `0.x` = pre-producción; `1.0.0` = primera versión en
  producción; `1.x` = evolución sin romper lo existente; `2.0.0` = salto de
  plataforma.
- **ID de tarea:** `X.Y-Tnn` (p. ej. `0.2-T03`).
- **Criterio de salida:** condición verificable que cierra la versión.
- **UI única:** al usar Compose Multiplatform con UI compartida, las versiones de
  cliente no duplican trabajo de UI; solo hay tareas de distribución/integración
  nativa por plataforma.
- **Tareas nativas:** las funcionalidades que dependen de capacidades del sistema
  (calendario, notificaciones/push) requieren pequeños `expect/actual` por
  plataforma, no UI duplicada.

## 4. Listado de versiones

| Versión | Nombre | Objetivo | Producción |
| --- | --- | --- | --- |
| `0.1.0` | Fundaciones | Monorepo, CI, entornos, DB, esqueletos | No |
| `0.2.0` | Ingesta BOE | Descargar y almacenar normas del BOE estatal | No |
| `0.3.0` | RAG base | Fragmentar, vectorizar y recuperar | No |
| `0.4.0` | Simplificación IA | Resúmenes claros y trazables | No |
| `0.5.0` | API pública | Feed, detalle y búsqueda en backend | No |
| `0.6.0` | Cliente CMP (UI compartida) | Feed y detalle una vez para las 3 plataformas | No |
| `0.7.0` | Distribución Android + Web | Empaquetar y desplegar Android y Web | No |
| `0.8.0` | Distribución iOS | Xcode, firma, TestFlight y App Store | No |
| `0.9.0` | Búsqueda y navegación | Filtros, deep links, compartir | No |
| `0.10.0` | Beta y operación | Calidad, legal, seguridad, beta cerrada | No |
| `1.0.0` | **Producción España** | Salida pública Android + Web + iOS | **Sí** |
| `1.1.0`–`1.10.0` | Expansión | CCAA, UE, cuentas, servicios, IA avanzada | Sí (1.1+) |
| `2.0.0` | Plataforma | Personalización, votaciones, escalado | Sí |

## 5. Detalle por versión

### `0.1.0` — Fundaciones
**Objetivo:** base técnica reproducible sobre la que construir.
**Criterio de salida:** el repo compila, hay tests mínimos y un entorno local
reproducible.

- `0.1-T01` Estructura del monorepo Gradle (Kotlin DSL): `shared/`, `backend/`,
  `composeApp/`, version catalog.
- `0.1-T02` Módulo `shared`: DTOs base (`DailySummary`, `SourceCategory`, etc.)
  con `kotlinx.serialization`.
- `0.1-T03` Esqueleto Ktor: healthcheck, configuración por entorno, logging.
- `0.1-T04` PostgreSQL + `pgvector` en `docker-compose`; migraciones con Flyway.
- `0.1-T05` Esqueleto Compose Multiplatform con targets Android, Web (Wasm) e iOS.
- `0.1-T06` CI (GitHub Actions): build + tests.
- `0.1-T07` `README`/guía de arranque y definición de entornos
  (dev/staging/prod).

### `0.2.0` — Ingesta BOE estatal (Sección I)
**Objetivo:** disponer de las disposiciones generales del BOE de forma diaria y
fiable.
**Criterio de salida:** cada día se descargan y guardan las normas con metadatos
fiables.

- `0.2-T01` Cliente de la API de datos abiertos del BOE (sumario diario).
- `0.2-T02` Parser de normas (identificador, título, fecha, organismo, categoría,
  texto, URL oficial).
- `0.2-T03` Modelo de datos y persistencia + versionado/consolidación.
- `0.2-T04` Job programado diario (cron) de descarga.
- `0.2-T05` Deduplicación y detección de cambios.
- `0.2-T06` Tests con fixtures reales y manejo de fallos de la fuente.
- `0.2-T07` Observabilidad del job (logs y alerta si no hay ingesta).
- `0.2-T08` Backfill del histórico reciente (últimos 2-3 años).

### `0.3.0` — RAG base (chunking + pgvector)
**Objetivo:** recuperar los fragmentos relevantes de una norma con calidad
medida.
**Criterio de salida:** dada una norma, se recuperan fragmentos relevantes con
precisión evaluada.

- `0.3-T01` Pipeline de fragmentación por artículo/sección.
- `0.3-T02` Generación de embeddings con la API elegida.
- `0.3-T03` Almacenamiento vectorial en `pgvector` con índices.
- `0.3-T04` Recuperación híbrida (filtro SQL por metadatos + similitud
  vectorial).
- `0.3-T05` Evaluación de recuperación (precision/recall) sobre un set de prueba.
- `0.3-T06` Servicio de embeddings locales (ONNX, modelo multilingüe pequeño).

### `0.4.0` — Simplificación con IA + trazabilidad
**Objetivo:** resúmenes en lenguaje claro y confiables.
**Criterio de salida:** resúmenes estructurados, en español claro y con enlace
verificable a la norma.

- `0.4-T01` Contrato de salida: "¿Qué cambia?", "¿A quién afecta?", "Cifras
  clave".
- `0.4-T02` Prompts y generación con cita obligatoria a la fuente oficial.
- `0.4-T03` Guardrails anti-alucinación (solo contexto RAG, validación de
  enlaces).
- `0.4-T04` Cacheo de resúmenes y control de coste de tokens.
- `0.4-T05` Evaluación de calidad con *golden set* de normas.
- `0.4-T06` Cola de revisión de resúmenes de baja confianza y aviso de contenido
  generado por IA.

### `0.5.0` — API pública backend
**Objetivo:** exponer el contenido a los clientes de forma estable.
**Criterio de salida:** los clientes pueden consumir feed, detalle y búsqueda.

- `0.5-T01` Endpoint feed diario con paginación.
- `0.5-T02` Endpoint detalle de norma (resumen + fuente).
- `0.5-T03` Endpoint de búsqueda (query + filtros categoría/fecha).
- `0.5-T04` Contratos OpenAPI y versionado de API.
- `0.5-T05` Rate limiting, CORS y manejo de errores.

### `0.6.0` — Cliente CMP (UI compartida)
**Objetivo:** una sola UI para las tres plataformas.
**Criterio de salida:** la app funciona con feed y detalle en Android, Web e iOS
desde el mismo código de UI.

- `0.6-T01` UI del feed en `commonMain` (lista + estados vacío/carga/error).
- `0.6-T02` Pantalla detalle con resumen estructurado y enlace oficial.
- `0.6-T03` Navegación, theming y estado compartido con `StateFlow`/ViewModels.
- `0.6-T04` Cliente HTTP `ktor-client` común y cache offline básica.
- `0.6-T05` Capa `expect/actual` para lo específico de plataforma (base).
- `0.6-T06` Targets de ejecución: Android, Wasm (Web) e iOS en desarrollo.
- `0.6-T07` Aplicar la dirección visual de `DESIGN.md` (tokens, componentes y
  pantallas).

### `0.7.0` — Distribución Android + Web
**Objetivo:** builds instalables/publicables de Android y Web.
**Criterio de salida:** artefactos publicables en Google Play y web desplegada.

- `0.7-T01` Empaquetado Android, firma y preparación para Google Play.
- `0.7-T02` Deploy Web (Wasm) y enlaces compartibles / SEO básico.
- `0.7-T03` Ajustes de layout responsive/adaptativo por plataforma.
- `0.7-T04` Despliegue del backend en el servidor propio (Docker + Nginx + cron).

### `0.8.0` — Distribución iOS
**Objetivo:** app iOS distribuible.
**Criterio de salida:** app iOS distribuible vía TestFlight.

- `0.8-T01` Proyecto Xcode e integración del framework (SPM/CocoaPods).
- `0.8-T02` Firma, certificados y provisioning.
- `0.8-T03` Ajustes de UI/UX y rendimiento específicos de iOS.
- `0.8-T04` App Store Connect, metadatos y TestFlight.

### `0.9.0` — Búsqueda y navegación
**Objetivo:** encontrar una norma por tema, no solo por el feed.
**Criterio de salida:** el usuario encuentra normas con filtros y comparte
enlaces.

- `0.9-T01` UI de búsqueda con filtros (categoría, fecha, ámbito).
- `0.9-T02` Historial local sin cuenta.
- `0.9-T03` Compartir norma con deep links.

### `0.10.0` — Beta y operación
**Objetivo:** beta cerrada estable y operación lista.
**Criterio de salida:** beta cerrada estable, legal cubierto y operación
preparada.

- `0.10-T01` Accesibilidad, i18n (es) y rendimiento.
- `0.10-T02` Observabilidad (métricas, logs, alertas) y backups.
- `0.10-T03` Legal: aviso de IA, privacidad, términos, accesibilidad.
- `0.10-T04` Hardening de seguridad (secretos, HTTPS, límites).
- `0.10-T05` Beta cerrada y corrección de bugs.

### `1.0.0` — Producción pública España
**Objetivo:** salida pública estable.
**Criterio de salida:** release público estable en Android, Web e iOS.

- `1.0-T01` Publicación en Google Play, App Store y despliegue web definitivo.
- `1.0-T02` Monitorización de producción, runbook y soporte.
- `1.0-T03` Congelación de alcance y checklist de lanzamiento.

## 6. Post-producción

| Versión | Objetivo | Tareas principales |
| --- | --- | --- |
| `1.1.0` | CCAA | Filtrado geográfico de leyes autonómicas (Sección I del BOE + boletines), `?ccaa=`. |
| `1.2.0` | UE | Ingesta DOUE/EUR-Lex (Serie L) vía CELLAR; TED para licitaciones. |
| `1.3.0` | Watchlist y alertas | Seguimiento de leyes **local** (sin cuenta) y alertas. Si hay push en segundo plano, ID anónimo de dispositivo (requiere tarea nativa). |
| `1.4.0` | Oposiciones y plazos | Sección II.B, requisitos y fechas; calendario y alertas (Google/Apple, requiere tarea nativa). |
| `1.5.0` | Subvenciones y licitaciones | BDNS + PLACSP/PRTR. |
| `1.6.0` | Contexto estadístico | INE, datos.gob.es y ejecución presupuestaria. |
| `1.7.0` | Fact-checker | Verificador de bulos legislativos. |
| `1.8.0` | Simulador de impacto | Cálculo en euros (fiscal/SMI/deducciones). |
| `1.9.0` | Chat RAG | Asistente conversacional sobre el corpus. |
| `1.10.0` | Dossiers PDF | Exportación de informes. |
| `2.0.0` | Plataforma | Personalización por perfil (autónomo, inquilino…), votaciones del Congreso y escalado. |

## 7. Notas y riesgos

- **Revisión de Apple:** las guías de App Store sobre contenido informativo y uso
  de IA son un gate real. Por eso `0.8.0` ya incluye TestFlight y `1.0.0`
  reserva tiempo para la aprobación.
- **Dependencia de fuentes oficiales:** la ingesta depende de APIs públicas; hay
  que prever fallos, cambios de formato y límites de uso.
- **Coste de LLM por tokens:** el cacheo (`0.4-T04`) y el control de tamaño de
  contexto son clave para la sostenibilidad.
- **Veracidad:** la confianza del usuario es el centro del producto; la
  trazabilidad a la fuente oficial (`0.4-T03`) es requisito, no extra.
- **Pendiente antes de producción:** nombre/marca del producto y umbral de
  confianza de la cola de revisión.
- **OpenCode Go:** pensado para agentes de coding; usarlo como backend de la app
  es un riesgo asumido (límites/abuso) y la cuota mensual puede agotarse.
- **N100 / 8 GB:** suficiente para la 1.0.0, pero el backfill se ejecuta por
  lotes y la RAM es ajustada.
- **Recurso único:** una persona a tiempo parcial; tres plataformas más RAG y
  backfill es un alcance ambicioso. No se comprometen fechas y Web podría
  posponerse a `1.x` si aprieta.
