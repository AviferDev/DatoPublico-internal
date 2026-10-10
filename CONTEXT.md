# Context

> Glosario y lenguaje compartido del proyecto. No contiene planes, tareas ni
> decisiones de implementación.

## Glossary

### Ciudadano general
Usuario objetivo del MVP: persona sin formación jurídica y sin perfil
segmentado, que se informa por prensa y redes sociales.

### Publicación
Elemento unitario que aparece en el feed: cualquier contenido ingerido del BOE
que DatoPublico resume y muestra. Tiene una **Categoría**, metadatos de **Sección
y Epígrafe** del BOE, organismo, fecha y enlace a la fuente oficial. Es el término
paraguas; "norma" se reserva a la Sección I.

### Categoría
Familia estable de cara al ciudadano, usada para filtrar y etiquetar en la UI. Se
deriva de la sección y el epígrafe del BOE. En la 1.0.0: **Normas y legislación**,
**Nombramientos y ceses**, **Oposiciones y empleo público**, **Becas, subvenciones
y ayudas**, **Premios**, **Convenios y acuerdos**, **Educación y planes de
estudio**, **Medio ambiente**, **Recursos y resoluciones**, **Información pública
y concesiones** y **Otras disposiciones y anuncios**.

### Sección / Epígrafe (BOE)
Metadatos crudos del sumario: la sección (I, II.A, II.B, III, IV, V.A, V.B, V.C)
y el epígrafe
del BOE (p. ej. «Subvenciones», «Recursos»). Se conservan junto a la Categoría
curada para trazabilidad y filtros finos.

### Norma
Publicación de la **Sección I** del BOE: leyes orgánicas, leyes ordinarias,
reales decretos-leyes y reglamentos. Se usa "norma" en lugar de "ley" para no
excluir los reglamentos.

### Empleo público
Publicación de la **Sección II.B** del BOE ("Oposiciones y concursos"): ofertas
de empleo público, convocatorias y procesos selectivos.

### Becas y subvenciones
Publicación relativa a becas, ayudas y subvenciones. Puede aparecer en la Sección
I (p. ej. concesión por Real Decreto), la III (bases reguladoras) o la V.B
(extractos). Puede incluir plazo de solicitud.

### BOE
Boletín Oficial del Estado, fuente oficial de publicación en España. Es
información **pública**: la 1.0.0 ingiere **todo su sumario** (secciones I, II.A,
II.B, III, IV, V.A, V.B y V.C) y **todos los campos** que ofrece la API. El
principio «sin datos personales» aplica a los **datos de quien usa la app**
(nada de cuentas ni perfiles), no al contenido del BOE, que **nunca se
restringe**.

### Sección I
"Disposiciones generales" del BOE (leyes y reglamentos). Parte del ámbito de
ingesta de la 1.0.0.

### Sección II.A
"Autoridades y personal — Nombramientos, situaciones e incidencias" del BOE.
Fuente de nombramientos y ceses.

### Sección II.B
"Autoridades y personal — Oposiciones y concursos" del BOE. Fuente del empleo
público.

### Sección III
"Otras disposiciones" del BOE: becas, subvenciones, premios, recursos, convenios,
planes de estudio, impacto ambiental, etc.

### Sección V.B
"Anuncios — Otros anuncios oficiales" del BOE: extractos de convocatorias de
ayudas, información pública y concesiones administrativas.

### Sección IV
"Administración de Justicia" del BOE: edictos, notificaciones y requisitorias de
Juzgados y Tribunales. **Incluida en la 1.0.0**: es información pública del BOE.

### Sección V.A
"Anuncios — A. Contratación del Sector Público" del BOE: licitaciones y
contratación pública publicadas en el BOE. **Incluida en la 1.0.0** (los
contratos adjudicados y el detalle de gasto viven en PLACSP, fuente externa que
sigue en 1.x).

### Sección V.C
"Anuncios — C. Anuncios particulares" del BOE. **Incluida en la 1.0.0**.

### Cambio (en 1.0.0)
Aparición de una **publicación nueva** (norma, empleo o beca) en el BOE. En la
1.0.0 no se consideran cambios las modificaciones de publicaciones ya existentes.

### Feed diario
Lista de las **publicaciones** nuevas de cada día (todas las secciones del BOE:
I, II.A, II.B, III, IV, V.A, V.B y V.C), cada una con su resumen ciudadano,
ordenada por fecha. Incluye una selección de **destacados**.

### Destacados (del día)
Subconjunto de publicaciones del día consideradas más relevantes mediante una
puntuación **automática y explicable** por señales objetivas (rango normativo,
organismo y palabras clave temáticas). No usa datos personales ni analítica.

### Resumen ciudadano
Explicación en lenguaje claro de una **publicación** (norma, empleo o beca),
estructurada en "¿Qué cambia?", "¿A quién afecta?" y "Cifras clave". Para empleo
y becas, "¿Qué cambia?" se adapta al plazo y requisitos. Distinto del sumario
oficial del BOE.

### Simplificación
Proceso de generar un resumen ciudadano a partir del texto oficial mediante IA.

### Trazabilidad
Enlace directo y visible a la fuente oficial de cada resumen. Requisito, no
elemento opcional.

### Guardrails
Comprobaciones automáticas que impiden publicar un resumen sin fuente o con
afirmaciones no sustentadas por el texto recuperado.

### Cola de revisión
Conjunto de resúmenes automáticos de baja confianza que quedan pendientes de
revisión interna. No bloquea el resto del feed.

### RAG
Generación aumentada por recuperación: el resumen se apoya en fragmentos
recuperados del texto oficial, no en conocimiento libre del modelo.

### Consulta / chat RAG
Pregunta en lenguaje natural del ciudadano, o **afirmación a verificar**
(desmentir bulos), sobre el corpus de publicaciones. Se responde con fragmentos
recuperados y **citas a la fuente oficial**, no con conocimiento libre del modelo
ni con fuentes externas (prensa/redes). Sin historial en el servidor (no hay
cuentas). Forma parte de la 1.0.0.

### Embedding
Representación vectorial de un fragmento de texto, usada para la búsqueda
semántica.

### pgvector
Extensión de PostgreSQL para almacenar y consultar vectores.

### Chunking
Fragmentación del texto oficial por artículo o sección para su indexado.

### Backfill
Carga inicial del histórico reciente del BOE para poblar la búsqueda desde el
primer día. En la 1.0.0: **último año**, de **todo el sumario del BOE**
(secciones I, II.A, II.B, III, IV, V.A, V.B y V.C).

### Watchlist (futuro)
Seguimiento personalizado de normas para alertar de cambios posteriores. Se
resolverá **sin cuenta** (almacenamiento local en el dispositivo). No forma
parte de la 1.0.0.

### ID anónimo de dispositivo
Token aleatorio, sin datos personales, que permitiría recibir alertas en segundo
plano sin crear cuenta. No forma parte de la 1.0.0.

### Colectivos afectados
Grupos amplios a los que afecta una publicación (ciudadanía, trabajadores,
empresas, autónomos, arrendatarios…). Es el nivel de detalle de "¿A quién
afecta?" en la 1.0.0.

## Rejected / Ambiguous Terms

### Ley
Usar `Norma` cuando el ámbito incluya reglamentos. Razón: no todo lo publicado
en la Sección I es una ley.

### Transparencia
Demasiado amplio para este producto. Razón: la 1.0.0 cubre **todo el sumario del
BOE** (incluidas las licitaciones de la Sección V.A), pero el seguimiento de gasto
y las fuentes externas (PLACSP, PRTR) siguen en 1.x.

### Resumen
Usar `Resumen ciudadano` para diferenciarlo del sumario oficial del BOE. Razón:
"resumen" a secas puede confundirse con el sumario de la fuente.

### Actualización de ley
No se usa en la 1.0.0. Razón: la modificación de normas existentes queda fuera
de alcance; en 1.0.0 `Cambio` significa solo norma nueva.

### Traducción
No se usa para la simplificación a lenguaje claro: ese proceso se llama
**Simplificación** y produce un **Resumen ciudadano**. "Traducción" se reserva
para pasar a idiomas distintos del castellano, que quedan fuera de la 1.0.0.

### Contrato público (adjudicado)
El detalle de contratos adjudicados queda fuera de la 1.0.0 (su fuente es la
Plataforma de Contratación del Sector Público, PLACSP; entra en 1.x). Lo que el
BOE publique de contratación (Sección V.A) **sí** está en la 1.0.0.

### Verificación con fuentes externas
El chat de la 1.0.0 verifica afirmaciones **solo contra el corpus del BOE**. El
fact-checking que rastrea prensa o redes no forma parte de la 1.0.0 (1.x).

### Sección IV (Administración de Justicia)
Redacción anterior **superada**: se excluía por «datos personales», pero ese
principio es sobre los **usuarios de la app**, no sobre el BOE. **Incluida en la
1.0.0**.

### Sección V.A (Subastas y licitaciones)
Redacción anterior **superada**: se aparcaba a 1.x por PLACSP. El sumario de la
Sección V.A del BOE (contratación del sector público) **entra en la 1.0.0**; lo
que sigue en 1.x es el detalle de adjudicaciones de PLACSP.
