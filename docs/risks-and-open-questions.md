# Risks and Open Questions

## Blocking Next Phase

- **Nombre y marca** del producto.

## Implementation-Time Questions

- Umbral de confianza que envía un resumen a la cola de revisión.
- Comparación final del modelo de embeddings sobre el corpus real: **por defecto
  `multilingual-e5-small` int8**; `-base` (768 dims) solo si la calidad no
  basta. La elección vive tras la interfaz de proveedor, no cableada.
- Modelo por defecto de **OpenCode (Zen/Go)** para generación y chat
  (candidato: `deepseek-v4.1-flash`) y parámetros de generación.
- Guardrails y umbral del **chat RAG** (respuestas sin fundamento, intentos de
  asesoramiento jurídico).
- Límites de uso y coste del chat: rate limiting, longitud de contexto y
  presupuesto de tokens por consulta.
- Historial del chat: local en el dispositivo o efímero (sin persistencia en el
  servidor, sin cuentas).
- **Mapeo sección/epígrafe → categoría**: reglas de clasificación y casos
  ambiguos (publicaciones sin epígrafe claro o con varios epígrafes).
- **Criterio y pesos del ranking de destacados** (rango normativo, organismo,
  palabras clave) y su transparencia ante el usuario.
- Modelado de **plazos** de convocatorias (empleo/becas): extracción y presentación.
- Ventana horaria de la **segunda pasada** de ingesta.
- Estrategia de caché y paginación de la API.
- Estrategia de lotes y ventana horaria para el backfill en el N100.

## Later / Not MVP

- Modificación de publicaciones existentes y texto consolidado.
- **Sección IV (Administración de Justicia)**: fuera de alcance por incluir datos
  personales.
- Cuentas, watchlist y alertas (push nativo).
- **Alertas y calendario de plazos** (notificaciones de empleo/becas).
- **Contratación pública (PLACSP) y licitaciones** (Sección V.A).
- Ámbito autonómico (CCAA) y europeo (UE).
- Contexto estadístico, **fact-checking con fuentes externas**, simulador y
  dossiers PDF.
- Lenguas cooficiales distintas del castellano.

## Assumptions

- El BOE ofrece API de sumario y acceso a los textos de las Secciones I, II.A,
  II.B, III y V.B de forma estable.
- El endpoint de OpenCode (Zen/Go) permite llamadas desde una aplicación backend.
- La calidad de `multilingual-e5-small` **int8** es suficiente para la búsqueda;
  si no, se sube a `-base` sin cambiar código.
- El N100 con 8 GB sostiene backend, PostgreSQL y el modelo de embeddings local
  (`e5-small` int8, ~120 MB).
- Las publicaciones de las cinco secciones se pueden clasificar de forma fiable en
  las categorías curadas a partir de la sección y el epígrafe del BOE.
- El seguimiento de publicaciones (watchlist) puede resolverse **sin cuentas** ni
  datos personales (almacenamiento local + ID anónimo de dispositivo si hay push).
- El usuario valora la trazabilidad a la fuente por encima de la cantidad.
- El **chat RAG** puede sostener su carga con la misma cuota de OpenCode, con
  rate limiting y control de contexto.

## Risks

- **Uso de OpenCode (Zen/Go) fuera de su uso previsto.** Está pensado para
  agentes de coding y monitoriza el tráfico por abuso; usarlo como backend de una
  app pública puede acarrear límites o bloqueo. Riesgo **asumido
  conscientemente**.
- **Límite mensual de OpenCode** por modelo: si la app crece, se agota la cuota.
- **Clave personal en el backend.** Si se filtra, el problema es del titular.
- **Alucinaciones** del modelo que erosionen la confianza.
- **Abuso del chat RAG:** el chat es más caro por consulta que el feed; sin
  rate limiting puede agotar la cuota o degradar el servicio.
- **Cambios de formato o de disponibilidad** de la fuente oficial.
- **Estructura irregular de las Secciones II.A, II.B, III y V.B**: sus formatos
  difieren de la Sección I; el parser y el chunking son más frágiles ahí.
- **Mapeo de categoría imperfecto**: epígrafes ausentes o solapados pueden asignar
  una categoría poco precisa.
- **Duplicidad III ↔ V.B**: una convocatoria puede aparecer como base reguladora y
  como extracto; hay que deduplicar.
- **Volumen**: III y V.B añaden muchas publicaciones cortas; más disco, indexado y
  coste de resumen. Vigilar el N100.
- **Relevancia subjetiva**: el ranking de destacados puede percibirse como sesgo
  editorial; debe ser explicable y transparente.
- **Rendimiento del N100.** El backfill del último año en cinco secciones puede
  tardar horas; RAM justa si compiten todos los servicios.
- **Rechazo en la revisión de Apple** (contenido informativo y uso de IA).
- **Recurso único:** una persona a tiempo parcial frente a un alcance amplio.
- Una mala ficha publicada puede dañar la confianza de forma difícil de
  revertir.

## Research Tasks

- Probar la extracción real del sumario y de textos de las Secciones I, II.A,
  II.B, III y V.B, y el mapeo a categorías.
- Comparar `multilingual-e5-small` **int8** y `-base` sobre publicaciones reales
  (calidad/coste de cómputo), incluyendo int8 vs fp32 de `small`.
- Medir tiempos de embedding y de backfill en el N100.
- Definir y validar el **ranking de destacados** (señales y pesos).
- Revisar en detalle las políticas de App Store para apps informativas con IA.
- Definir el golden set y una métrica de calidad de resúmenes.
- Probar el **chat RAG** de punta a punta: calidad de recuperación, citas
  correctas y comportamiento ante preguntas sin fundamento y afirmaciones falsas.
