# Context

> Glosario y lenguaje compartido del proyecto. No contiene planes, tareas ni
> decisiones de implementación.

## Glossary

### Ciudadano general
Usuario objetivo del MVP: persona sin formación jurídica y sin perfil
segmentado, que se informa por prensa y redes sociales.

### Norma (disposición general)
Cualquier texto publicado en la Sección I del BOE: leyes orgánicas, leyes
ordinarias, reales decretos-leyes y reglamentos. Se usa "norma" en lugar de
"ley" para no excluir los reglamentos.

### BOE
Boletín Oficial del Estado, fuente oficial de publicación de normas en España.

### Sección I
Sección "Disposiciones generales" del BOE. Es el ámbito de ingesta de la
versión 1.0.0.

### Cambio (en 1.0.0)
Aparición de una **norma nueva** en el BOE. En la 1.0.0 no se consideran cambios
las modificaciones de normas ya existentes.

### Feed diario
Lista de las normas nuevas publicadas cada día, cada una con su resumen
ciudadano, ordenada por fecha.

### Resumen ciudadano
Explicación de una norma en lenguaje claro, estructurada en "¿Qué cambia?",
"¿A quién afecta?" y "Cifras clave". Distinto del sumario oficial del BOE.

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

### Embedding
Representación vectorial de un fragmento de texto, usada para la búsqueda
semántica.

### pgvector
Extensión de PostgreSQL para almacenar y consultar vectores.

### Chunking
Fragmentación del texto oficial por artículo o sección para su indexado.

### Backfill
Carga inicial del histórico reciente del BOE (últimos 2-3 años) para poblar la
búsqueda desde el primer día.

### Watchlist (futuro)
Seguimiento personalizado de normas para alertar de cambios posteriores. Se
resolverá **sin cuenta** (almacenamiento local en el dispositivo). No forma
parte de la 1.0.0.

### ID anónimo de dispositivo
Token aleatorio, sin datos personales, que permitiría recibir alertas en segundo
plano sin crear cuenta. No forma parte de la 1.0.0.

### Colectivos afectados
Grupos amplios a los que afecta una norma (ciudadanía, trabajadores, empresas,
autónomos, arrendatarios…). Es el nivel de detalle de "¿A quién afecta?" en la
1.0.0.

## Rejected / Ambiguous Terms

### Ley
Usar `Norma` cuando el ámbito incluya reglamentos. Razón: no todo lo publicado
en la Sección I es una ley.

### Transparencia
Demasiado amplio para este producto. Razón: el seguimiento de gasto,
licitaciones y subvenciones pertenece a versiones 1.x; el núcleo de la 1.0.0 es
la simplificación de normas.

### Resumen
Usar `Resumen ciudadano` para diferenciarlo del sumario oficial del BOE. Razón:
"resumen" a secas puede confundirse con el sumario de la fuente.

### Actualización de ley
No se usa en la 1.0.0. Razón: la modificación de normas existentes queda fuera
de alcance; en 1.0.0 `Cambio` significa solo norma nueva.
