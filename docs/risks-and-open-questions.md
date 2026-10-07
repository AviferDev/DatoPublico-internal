# Risks and Open Questions

## Blocking Next Phase

- **Nombre y marca** del producto.

## Implementation-Time Questions

- Umbral de confianza que envía un resumen a la cola de revisión.
- Modelo de embeddings definitivo (`multilingual-e5-small` vs `-base`).
- Modelo de Go por defecto (candidato: `deepseek-v4.1-flash`) y parámetros de
  generación.
- Estrategia de caché y paginación de la API.
- Estrategia de lotes y ventana horaria para el backfill en el N100.

## Later / Not MVP

- Modificación de normas existentes y texto consolidado.
- Cuentas, watchlist y alertas (push nativo).
- Ámbito autonómico (CCAA) y europeo (UE).
- Oposiciones y plazos, subvenciones y licitaciones.
- Contexto estadístico, fact-checker, simulador, chat RAG y dossiers PDF.
- Lenguas cooficiales distintas del castellano.

## Assumptions

- El BOE ofrece API de sumario y acceso a los textos de forma estable.
- El endpoint de OpenCode Go permite llamadas desde una aplicación backend.
- La calidad de `multilingual-e5-small` es suficiente para la búsqueda.
- El N100 con 8 GB sostiene backend, PostgreSQL y embeddings locales.
- El seguimiento de leyes (watchlist) puede resolverse **sin cuentas** ni datos
  personales (almacenamiento local + ID anónimo de dispositivo si hay push).
- El usuario valora la trazabilidad a la fuente por encima de la cantidad.

## Risks

- **Uso de OpenCode Go fuera de su uso previsto.** Está pensado para agentes de
  coding y monitoriza el tráfico por abuso; usarlo como backend de una app
  pública puede acarrear límites o bloqueo. Riesgo **asumido conscientemente**.
- **Límite mensual de Go** por modelo: si la app crece, se agota la cuota.
- **Clave personal en el backend.** Si se filtra, el problema es del titular.
- **Alucinaciones** del modelo que erosionen la confianza.
- **Cambios de formato o de disponibilidad** de la fuente oficial.
- **Rendimiento del N100.** El backfill de 2 años puede tardar horas; RAM
  justa si compiten todos los servicios.
- **Rechazo en la revisión de Apple** (contenido informativo y uso de IA).
- **Recurso único:** una persona a tiempo parcial frente a un alcance amplio.
- Una mala ficha publicada puede dañar la confianza de forma difícil de
  revertir.

## Research Tasks

- Probar la extracción real del sumario y de textos del BOE.
- Comparar `multilingual-e5-small` y `-base` sobre normas reales
  (calidad/coste de cómputo).
- Medir tiempos de embedding y de backfill en el N100.
- Revisar en detalle las políticas de App Store para apps informativas con IA.
- Definir el golden set y una métrica de calidad de resúmenes.
