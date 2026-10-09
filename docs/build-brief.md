# Build Brief

> Documento de descubrimiento del producto. Refleja las decisiones cerradas del
> discovery. Ver también `CONTEXT.md`, `docs/domain-model.md`,
> `docs/technical-discovery.md` y `docs/roadmap.md`.

## Problem

El ciudadano no puede saber de forma **fiable y comprensible** cómo le afecta lo
recién publicado en el BOE (normas, nombramientos, empleo público, becas y
subvenciones, premios, convenios, información pública…). La información oficial
está en lenguaje jurídico y burocrático, y las vías alternativas (prensa y redes)
no ofrecen una explicación trazable a la fuente.

## Current Workaround / Existing System

El ciudadano se informa por titulares y redes sociales. No entiende la fuente
oficial y no se fía de la interpretación que consume. Alternativamente, depende
de un tercero (gestor, abogado o familiar), lo que no escala.

## Target Users

- **Primario:** ciudadano general de España, sin formación jurídica, que quiere
  saber qué se ha publicado y si le afecta (normas, empleo, becas, premios,
  nombramientos…).
- **Secundario ligero en 1.0.0:** quien busca activamente empleo público, becas o
  subvenciones; se cubre con **filtros por categoría**, sin personalización.
- **No prioritario en 1.0.0:** perfiles segmentados por intereses (autónomos,
  inquilinos, pymes), que se abordan en versiones posteriores.

## Goals

- Explicar en lenguaje claro **qué cambia** una publicación nueva y **a quién
  afecta** (normas, nombramientos, empleo, becas y subvenciones, premios,
  convenios, información pública…), por **categoría**.
- Mantener **trazabilidad** a la fuente oficial en cada resumen.
- Ofrecer un **feed diario** de todo lo publicado (Secciones I, II.A, II.B, III y
  V.B).
- **Destacar** las publicaciones más relevantes del día con un ranking objetivo.
- Permitir **buscar y filtrar** por categoría y fecha en el histórico reciente.
- Permitir **preguntar o verificar** afirmaciones en lenguaje natural contra el
  corpus (**chat RAG**), con respuestas fundamentadas y citadas a la fuente.
- Estar disponible en **Android, Web e iOS** con una única UI compartida.

## Non-Goals

Fuera de la 1.0.0 (van a la serie `1.x`):

- Detección y explicación de **modificaciones** de publicaciones existentes.
- **Alertas, notificaciones y calendario de plazos** (empleo y becas). En 1.0.0
  los plazos se muestran, pero no se avisa.
- **Licitaciones y contratación pública** (Sección V.A del BOE, PLACSP/PRTR); los
  contratos adjudicados no se publican en el BOE.
- **Administración de Justicia (Sección IV)**: edictos, notificaciones y
  requisitorias con **datos personales**, contrarios al principio de «sin datos
  personales».
- Cuentas de usuario y cualquier dato personal. El watchlist será **local** y,
  si hay push en el futuro, usará un **identificador anónimo de dispositivo**.
- Ámbito autonómico (CCAA) y europeo (UE).
- Contexto estadístico (INE, datos.gob.es).
- **Fact-checking con fuentes externas** (prensa/redes), simulador de impacto y
  dossiers PDF.
- Personalización por perfil ciudadano.
- Lenguas cooficiales distintas del castellano.
- Analítica de uso (1.0.0 sin telemetría).

## MVP Slice

Un corte vertical completo y verificable:

1. Ingesta diaria del BOE (Secciones I, II.A, II.B, III y V.B) a las **9:30 con
   una segunda pasada**, más backfill del **último año**.
2. **Clasificación por categoría** (enum curado) usando la sección y el epígrafe
   del BOE como metadato, y extracción de **plazos** en convocatorias.
3. Fragmentación y vectorización con **`multilingual-e5-small`** (int8,
   ONNX/CPU) como único modelo local; RAG sobre PostgreSQL + `pgvector`.
4. Generación de resumen ciudadano (**castellano**, **colectivos amplios**) con
   **OpenCode** (Zen/Go), guardrails y trazabilidad, adaptada a cada categoría.
5. Selección automática de **destacados del día** (ranking por señales objetivas).
6. Cola de revisión para casos de baja confianza.
7. API pública de solo lectura: feed, detalle, búsqueda con filtros y **chat RAG**
   (verificación contra el BOE con citas a la fuente).
8. UI compartida (Compose Multiplatform): feed con destacados y categorías,
   detalle (**resumen + enlace a la fuente**), búsqueda/filtros y chat.
9. Distribución en Android, Web e iOS.

## Validation Plan

- **Golden set** de publicaciones con resumen de referencia para medir calidad.
- Medición de error en "¿Qué cambia?" y "¿A quién afecta?".
- Revisión de la cola de baja confianza.
- Verificación de que los **destacados** y los **filtros por categoría** devuelven
  resultados coherentes.
- Pruebas del **chat RAG**: respuestas fundamentadas en el corpus, con citas y
  sin invenciones (incluida la verificación de afirmaciones falsas).
- Beta cerrada con usuarios reales en las tres plataformas.
- Revisión de las guías de Google Play y App Store antes del lanzamiento.

## Success Criteria

- El resumen responde correctamente a "qué cambia" y "a quién afecta" en la
  mayoría del golden set.
- **Ningún** resumen publicado sin enlace a la fuente oficial.
- El **chat RAG** responde con citas a la fuente y sin afirmaciones fuera del
  corpus en la mayoría de las pruebas.
- El feed diario se actualiza (9:30 + segunda pasada) y cubre las Secciones I,
  II.A, II.B, III y V.B, con la categoría asignada correctamente.
- La beta cerrada es usable en Android, Web e iOS.
- Google Play y App Store aprueban la publicación.

## Notes

- Proyecto **gratuito de interés público** (sostenido con subvenciones o
  donaciones).
- Lo construye **una persona, a tiempo parcial, sin fecha fija**: se prioriza
  avanzar sin comprometer fechas.
- La confianza del usuario es el activo principal; la trazabilidad y los
  guardrails son la base de esa confianza.
- **Principio de transparencia:** sin cuentas, sin datos personales y sin
  analítica. El servidor solo almacena datos públicos.
- El **chat RAG** no guarda historial en el servidor (sin cuentas); el historial
  es efímero o vive en el dispositivo.
