---
name: rag-datapublico
description: Guía del pipeline RAG de DatoPublico sobre el BOE (todo el sumario: Secciones I, II.A, II.B, III, IV, V.A, V.B y V.C). Úsala al ingerir o fragmentar publicaciones, generar o almacenar embeddings, indexar en pgvector, montar recuperación híbrida, generar resúmenes o respuestas de chat con citas, aplicar guardrails o evaluar calidad (golden set, precision/recall). Fija las convenciones del proyecto (chunking, multilingual-e5-small int8, protección anti-alucinación, trazabilidad a la fuente) y describe el patrón objetivo y sus riesgos conocidos.
---

# RAG de DatoPublico (BOE)

El valor del producto está en recuperar bien y **no inventar**. Toda afirmación
mostrada al usuario debe apoyarse en fragmentos del BOE y llevar **enlace a la
fuente oficial**. Lee también `docs/domain-model.md`,
`docs/technical-discovery.md` y `CONTEXT.md`.

> Antecedente: una PoC temporal (`poc/boe-rag`) validó el pipeline de punta a
> punta (ingesta → chunking → embeddings ONNX → pgvector → recuperación →
> generación con cita; recall/MRR 1.0 sobre un set mínimo). Se **eliminó** a
> propósito: era una prueba temporal. Sus lecciones están destiladas en esta
> skill; no la busques en el repo.

## Pipeline

```
ingesta BOE → chunking → embeddings (ONNX) → pgvector → recuperación híbrida
   → generación (OpenCode) → guardrails → publicación | cola_revision
```

## 1. Ingesta y chunking

- Corpus: **todo el sumario del BOE** — **I** (disposiciones generales), **II.A**
  (nombramientos), **II.B** (empleo), **III** (otras disposiciones), **IV**
  (Administración de Justicia), **V.A** (contratación pública), **V.B** (otros
  anuncios) y **V.C** (anuncios particulares). Cada sección tiene estructura y
  vocabulario distintos: el chunking necesita **variantes por sección**, no una
  regla única.
- Fragmenta por **artículo/disposición** conservando su referencia. No generes
  solapamientos inválidos; los fragmentos deben cubrir el texto.
- Normaliza: el BOE usa **espacio duro (`\u00a0`)** tras etiquetas como
  «Artículo»; inserta saltos por párrafo y ancla los encabezados a **inicio de
  línea**. Omitir esto produce referencias erróneas.
- Cada fragmento guarda metadatos de metadatos de filtrado: publicación,
  categoría, fecha, organismo y referencia de artículo/sección.

## 2. Embeddings (locales)

- Modelo por defecto: **`intfloat/multilingual-e5-small` cuantizado int8** vía
  **ONNX Runtime en CPU**; **384 dimensiones**, contexto **512 tokens**.
- Prefijos obligatorios: `query: ` para la consulta y `passage: ` para los
  fragmentos. Sin prefijo la calidad cae.
- Normaliza los vectores. No superes 512 tokens por fragmento.
- El modelo vive tras una **interfaz de proveedor** para poder cambiar a `-base`
  (768 dims) sin tocar el resto del código. Cambiar de modelo implica **rediseñar
  la columna y reindexar**.
- Herramienta configurable por entorno; clave de OpenCode solo en el servidor.

## 3. Almacenamiento vectorial

- PostgreSQL + **pgvector**; columna de dimensión **384**; índice **HNSW**.
- Filtros SQL por metadatos (fecha, categoría, organismo) combinados con la
  similitud. Verifica que el índice **se usa** en la consulta.

## 4. Recuperación híbrida

- Combina filtros SQL con similitud vectorial; devuelve top-k fragmentos con su
  referencia y score.
- Ordena por relevancia; deja la puerta a un **reranking** si la calidad lo pide.

## 5. Generación (resumen y chat)

- Proveedor: **OpenCode** (OpenAI-compatible, candidato `deepseek-v4.1-flash`)
  tras una interfaz intercambiable.
- **Resumen ciudadano:** salida estructurada "¿Qué cambia?", "¿A quién afecta?",
  "Cifras clave", con **cita obligatoria** a la fuente. Variante para empleo/beca
  (incluye **plazo**).
- **Chat/consulta:** acepta una pregunta o una **afirmación a verificar**;
  responde con las citas y distingue **respondida**, **refutada** y
  **sin_fundamento**.
- El prompt trabaja **solo** con el contexto recuperado; prohibido el
  conocimiento libre del modelo.

## 6. Guardrails (anti-alucinación y trazabilidad)

- Ningún resumen se publica sin **enlace válido** a la fuente oficial.
- Ninguna afirmación fuera del contexto recuperado. Si el corpus no sustenta la
  respuesta, se declara **sin_fundamento** (no se inventa).
- Resúmenes de **baja confianza** van a `cola_revision`, sin bloquear el feed.
- Cachea resúmenes por publicación para no regenerar ni gastar tokens de más.

## 7. Evaluación

- **Recuperación:** precision/recall (y recall@k / MRR) sobre un set de prueba.
- **Resúmenes:** **golden set** de publicaciones con referencia; mide acierto en
  "¿Qué cambia?" y "¿A quién afecta?".
- **Chat:** respuestas con citas correctas, refutación de afirmaciones falsas y
  comportamiento ante preguntas sin fundamento.

## Riesgos conocidos

- Chunking por expresiones regulares es **heurístico**; la vía de producto debería
  aprovechar la estructura/XML del BOE cuando sea posible.
- `int8` degrada ligeramente la calidad; **no** se ha comparado aún contra fp32 ni
  `-base` sobre corpus real.
- Corpus de prueba pequeño; validar con volúmenes reales antes de confiar en las
  métricas.
- Las Secciones II.A, II.B, III, IV, V.A, V.B y V.C son más irregulares que la I:
  parser, chunking y clasificación requieren validación con datos reales; puede
  haber duplicidad III ↔ V.B (base reguladora y extracto).
- Coste del chat por tokens: aplicar rate limiting y control de contexto.
