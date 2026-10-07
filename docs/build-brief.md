# Build Brief

> Documento de descubrimiento del producto. Refleja las decisiones cerradas del
> discovery. Ver también `CONTEXT.md`, `docs/domain-model.md`,
> `docs/technical-discovery.md` y `docs/roadmap.md`.

## Problem

El ciudadano no puede saber de forma **fiable y comprensible** cómo le afecta una
norma recién publicada. La información oficial está en lenguaje jurídico y
burocrático, y las vías alternativas (prensa y redes) no ofrecen una explicación
trazable a la fuente.

## Current Workaround / Existing System

El ciudadano se informa por titulares y redes sociales. No entiende la fuente
oficial y no se fía de la interpretación que consume. Alternativamente, depende
de un tercero (gestor, abogado o familiar), lo que no escala.

## Target Users

- **Primario:** ciudadano general de España, sin formación jurídica, que quiere
  saber qué ha cambiado una norma y si le afecta.
- **No prioritario en 1.0.0:** perfiles segmentados (autónomos, opositores,
  inquilinos, pymes), que se abordan en versiones posteriores.

## Goals

- Explicar en lenguaje claro **qué cambia** una norma nueva y **a quién afecta**.
- Mantener **trazabilidad** a la fuente oficial en cada resumen.
- Ofrecer un **feed diario** de las normas publicadas.
- Permitir **buscar** en el histórico reciente del BOE.
- Estar disponible en **Android, Web e iOS** con una única UI compartida.

## Non-Goals

Fuera de la 1.0.0 (van a la serie `1.x`):

- Detección y explicación de **modificaciones** de normas existentes.
- Cuentas de usuario y cualquier dato personal. El watchlist será **local** y,
  si hay push en el futuro, usará un **identificador anónimo de dispositivo**.
- Ámbito autonómico (CCAA) y europeo (UE).
- Oposiciones y plazos, subvenciones y licitaciones.
- Contexto estadístico (INE, datos.gob.es).
- Fact-checker, simulador de impacto, chat RAG y dossiers PDF.
- Personalización por perfil ciudadano.
- Lenguas cooficiales distintas del castellano.
- Analítica de uso (1.0.0 sin telemetría).

## MVP Slice

Un corte vertical completo y verificable:

1. Ingesta diaria del BOE (Sección I, **todas** las normas nuevas) + backfill de
   los últimos **2 años**.
2. Fragmentación y vectorización con **embeddings locales**; RAG sobre
   PostgreSQL + `pgvector`.
3. Generación de resumen ciudadano (**castellano**, **colectivos amplios**) con
   **OpenCode Go**, guardrails y trazabilidad.
4. Cola de revisión para casos de baja confianza.
5. API pública de solo lectura: feed, detalle y búsqueda.
6. UI compartida (Compose Multiplatform): feed, detalle (**resumen + enlace a la
   fuente**) y búsqueda.
7. Distribución en Android, Web e iOS.

## Validation Plan

- **Golden set** de normas con resumen de referencia para medir calidad.
- Medición de error en "¿Qué cambia?" y "¿A quién afecta?".
- Revisión de la cola de baja confianza.
- Beta cerrada con usuarios reales en las tres plataformas.
- Revisión de las guías de Google Play y App Store antes del lanzamiento.

## Success Criteria

- El resumen responde correctamente a "qué cambia" y "a quién afecta" en la
  mayoría del golden set.
- **Ningún** resumen publicado sin enlace a la fuente oficial.
- El feed diario se publica de forma puntual.
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
