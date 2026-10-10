# Domain Model

## Core Concepts

- **Publicación:** elemento unitario que aparece en el feed. Tiene una
  **Categoría**, metadatos de **Sección/Epígrafe** del BOE, organismo, fecha y
  enlace a la fuente oficial. Es el término paraguas.
- **Categoría:** familia estable de cara al ciudadano (usada para filtrar y
  etiquetar). Enum curado, derivado de la sección y el epígrafe del BOE:
  `Normas y legislación`, `Nombramientos y ceses`, `Oposiciones y empleo público`,
  `Becas, subvenciones y ayudas`, `Premios`, `Convenios y acuerdos`,
  `Educación y planes de estudio`, `Medio ambiente`, `Recursos y resoluciones`,
  `Información pública y concesiones`, `Otras disposiciones y anuncios`.
- **Sección / Epígrafe (BOE):** metadatos crudos del sumario. Sección ∈ {I, II.A,
  II.B, III, V.B}; epígrafe = etiqueta del BOE (p. ej. «Subvenciones»,
  «Recursos»). Se conservan para trazabilidad y filtros finos.
- **Norma:** publicación de la Sección I (leyes y reglamentos).
- **Convocatoria de empleo público:** publicación de la Sección II.B (oposiciones
  y concursos).
- **Beca / subvención:** publicación sobre becas, ayudas o subvenciones; puede
  venir de la Sección I, III o V.B. Puede tener **plazo**.
- **Plazo:** fecha límite de solicitud de una convocatoria. En la 1.0.0 se
  muestra; las alertas y el calendario quedan fuera.
- **Fragmento (chunk):** porción de una publicación (artículo o sección) usada
  para indexado y recuperación.
- **Resumen ciudadano:** explicación en lenguaje claro de una publicación.
- **Consulta (chat RAG):** pregunta en lenguaje natural o afirmación a verificar
  contra el corpus; se responde con fragmentos recuperados y citas.
- **Fuente oficial:** URL al texto oficial de la publicación en el BOE.
- **Confianza:** medida de calidad/riesgo del resumen generado automáticamente.
- **Destacado:** publicación del día marcada como relevante por el ranking
  automático (rango normativo, organismo y palabras clave temáticas).
- **Feed diario:** agrupación de publicaciones nuevas por fecha de publicación.
- **Usuario:** en 1.0.0, anónimo; no hay cuentas ni sesión persistente.
- **Colectivos afectados:** en 1.0.0, "¿A quién afecta?" describe colectivos
  amplios (ciudadanía, trabajadores, empresas, autónomos, arrendatarios…).

## Relationships

- Una **Publicación** tiene **1 Categoría** (enum curado) y **1 Sección/Epígrafe**
  del BOE.
- Una **Publicación** tiene **1..N Fragmentos**.
- Una **Publicación** tiene **1 Resumen ciudadano** (en 1.0.0, sin versionado).
- Un **Resumen** referencia **1 Fuente oficial** (obligatoria).
- Una **Publicación** puede ser **Destacado** según su relevancia del día.
- El **Feed diario** agrega **Publicaciones** nuevas por fecha.
- Un **Resumen** puede estar en la **Cola de revisión** según su Confianza.
- Una **Consulta** recupera **1..N Fragmentos** y cita **1..N Fuentes oficiales**.
- Una **Consulta** no se persiste en el servidor (sin cuentas); el historial, si
  existe, es local en el dispositivo.

## States and Lifecycles

**Publicación** (1.0.0): `publicada` → estado único gestionado. No se modelan
derogación ni modificación en esta versión.

**Resumen ciudadano:**

```text
pendiente
   → generado
      → validado_por_guardrails
         → publicado            (confianza suficiente)
         → en_cola_revision     (baja confianza)
            → revisado
               → publicado
               → descartado
      → descartado              (guardrail falla sin recuperación)
```

**Consulta (chat RAG):**

```text
recibida
   → respondida        (respuesta fundamentada con citas a la fuente)
   → refutada          (el corpus contradice la afirmación verificada)
   → sin_fundamento    (el corpus no permite confirmar ni refutar; se declara, no se inventa)
```

## Important Scenarios

- **Ingesta diaria:** descarga del sumario (**todo el BOE**: secciones I, II.A,
  II.B, III, IV, V.A, V.B y V.C), parseo y persistencia; a las 9:30 con una
  segunda pasada.
- **Clasificación:** asignar Categoría a partir de la Sección/Epígrafe del BOE, y
  extraer plazos.
- **Backfill:** carga del histórico del **último año**.
- **Destacados:** cálculo diario del ranking de relevancia por señales objetivas.
- **Generación:** chunking → embeddings → recuperación → resumen + fuente.
- **Guardrail fallido:** el resumen no se publica o entra en cola.
- **Publicación:** el feed del día queda disponible en la API.
- **Búsqueda:** consulta del usuario con filtros de categoría y fecha.
- **Chat:** el usuario pregunta o pega una afirmación; se recuperan fragmentos y
  se responde con citas a la fuente.

## Edge Cases

- **Categoría ambigua:** publicaciones del BOE sin epígrafe claro o con varios
  epígrafes → asignar la categoría más representativa y conservar el epígrafe.
- **Duplicidad entre secciones:** una convocatoria puede aparecer como base
  reguladora (III) y como extracto (V.B) → deduplicar por referencia/identificador.
- **Subvenciones en varias secciones** (I, III, V.B) → misma categoría, distinta
  sección.
- Convocatoria (empleo o beca) sin plazo explícito en la fuente.
- Afirmación de chat que el corpus no cubre → se declara `sin_fundamento`.
- Pregunta de chat que busca asesoramiento jurídico → disclaimer de no
  asesoramiento.
- Publicación sin texto completo disponible en la fuente.
- Publicación muy extensa (necesita chunking/recuperación cuidadosos).
- Duplicados o publicaciones corregidas por el BOE.
- Publicaciones en lenguas cooficiales distintas del castellano (excluidas en la
  1.0.0).
- Fallo o cambio de formato de la fuente oficial durante la ingesta.
