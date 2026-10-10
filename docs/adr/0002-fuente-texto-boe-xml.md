# ADR 0002: El texto y los metadatos del BOE se toman del XML estructurado (`xml.php`)

## Estado

Aceptado (2026-10-10). Decisión del dueño del repositorio, fijada al planificar e
implementar el parser de publicaciones (FT00007). Condiciona la persistencia
(FT00008), el chunking (FT00014) y todo el pipeline RAG.

## Contexto

Cada entrada del sumario diario del BOE (FT00006) expone hasta tres fuentes del
mismo contenido:

- `url_html`: `https://www.boe.es/diario_boe/txt.php?id=<id>` (HTML para lectura).
- `url_xml`: `https://www.boe.es/diario_boe/xml.php?id=<id>` (XML estructurado).
- `url_pdf`: el PDF oficial paginado.

El pipeline necesita **texto completo** y **metadatos fiables** (rango,
departamento, fecha de disposición, número oficial) para clasificar (FT00012),
fragmentar (FT00014) y resumir con trazabilidad. Las tres fuentes no son
equivalentes: el HTML está pensado para presentación, el PDF exige extracción por
maquetación (frágil, pesada, sensible a OCR) y el XML separa explícitamente
`<metadatos>` de `<texto>` con bloques semánticos (`p`, `table`, `dl`…).

Además, el corpus incluye publicaciones extensas (leyes de decenas–cientos de KB)
y secciones con estructura irregular (IV, V.A, V.B, V.C). La fuente elegida debe
representar todos los bloques sin heurísticas de presentación.

Restricción de seguridad: el XML es contenido **remoto no confiable**; debe
parsearse sin DTD ni entidades externas (ver MUST en `CONSTRAINTS.md`).

## Decisión

1. La **fuente de verdad** del texto y los metadatos de una publicación es el
   **XML estructurado** de `xml.php` (`Accept: application/xml`, UTF-8).
2. El parser (`BoeXmlParser`, FT00007) usa el **parser XML del JDK** en modo
   *secure processing*, sin DTD/entidades externas, y compone el texto por
   bloques (`p`, `li`, `dt`, `dd`) con separación de párrafos y normalización de
   espacios.
3. **No se parsea** el HTML (`txt.php`) ni el **PDF** en la 1.0.0. El PDF queda
   solo como enlace de la fuente oficial; una publicación sin `<texto>` XML se
   acepta con `texto = null` (sin inventarlo). Un fallback a `txt.php`/OCR se
   valoraría en `1.x` si la ausencia de texto resultase frecuente.

## Alternativas consideradas

- **HTML (`txt.php`)**: legible pero pensado para presentación; exigiría
  scraping heurístico y no aporta metadatos estructurados. Descartada.
- **PDF (`url_pdf`)**: requiere extraer texto por maquetación (frágil, pesado y
  con riesgo de OCR); no da metadatos limpios. Descartada.
- **Combinar XML + HTML + PDF**: más superficie y coste sin mejorar la cobertura
  (todos los `item` reales exponen `url_xml`). Descartada en la 1.0.0.

## Consecuencias

- Habilita un modelo único (`DocumentoBoe` → `Publicacion`) con texto por párrafos
  y metadatos ricos, base de clasificación, chunking y RAG.
- Obliga a **seguridad**: cualquier XML remoto se parsea con *secure processing*;
  es un MUST durable en `CONSTRAINTS.md`.
- Las publicaciones sin `<texto>` XML quedan con `texto = null`; no se cubren con
  HTML/OCR en la 1.0.0.
- La descarga es una **llamada de red** sujeta a la regla de tests opt-in; los
  fixtures XML reales por sección viven en `backend/src/test/resources/boe/` y el
  gate no hace red.
- Futuras features (FT00008, FT00014) consumen el texto y los metadatos de esta
  vía; cambiarla exigiría un ADR que ajuste/superseda este.
