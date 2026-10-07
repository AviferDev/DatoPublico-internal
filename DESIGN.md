---
name: DatoPublico
description: Consulta de legislación simplificada, clara y trazable para el ciudadano.
designAssets:
  sourceOfTruth: []
  generatedConcepts: []
colors:
  primary: "#1A4D8F"
  secondary: "#0F766E"
  accent: "#F59E0B"
  background: "#F7F9FC"
  surface: "#FFFFFF"
  text: "#1F2937"
typography:
  h1:
    fontFamily: "Inter, system-ui, sans-serif"
    fontSize: "32px"
    fontWeight: "700"
  body:
    fontFamily: "Inter, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: "400"
rounded:
  sm: "6px"
  md: "12px"
spacing:
  sm: "8px"
  md: "16px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "#FFFFFF"
    rounded: "{rounded.md}"
---

# Design Direction

> Dirección visual inicial para agentes de código. Los tokens del frontmatter son
> la fuente de verdad cuando una descripción entre en conflicto. No es una
> especificación pixel-perfect.

## Overview

DatoPublico debe sentirse **cívico, claro y fiable**. La confianza es el activo
principal, así que la UI debe transmitir sobriedad institucional sin resultar
burocrática ni fría. La legibilidad del contenido manda sobre el adorno.

## Existing Design Assets

Ninguno. No hay marca, logo, guía de estilo ni diseños previos. Esta es una
dirección inicial creada durante el discovery.

## Generated Concept Images

Ninguna. No se han generado imágenes de concepto; si más adelante se decide
hacerlo, se guardarán en `docs/design/concepts/` y se referenciarán aquí.

## Product Feel

- Confianza: nada de estética alarmista ni sensacionalista.
- Claridad: jerarquía fuerte, mucho aire, texto cómodo de leer.
- Neutralidad: sin sesgo visual que sugiera opinión política.
- Cercanía: lenguaje llano, pero interfaz seria.

## Colors

- **primary `#1A4D8F`:** acciones principales, encabezados y enlaces.
- **secondary `#0F766E`:** acentos informativos (contexto, datos).
- **accent `#F59E0B`:** avisos y plazos que requieren atención.
- **background `#F7F9FC`:** fondo general, descansado.
- **surface `#FFFFFF`:** tarjetas y superficies de contenido.
- **text `#1F2937`:** texto principal con buen contraste.

## Typography

- Familia base sans-serif (Inter o la fuente del sistema).
- Títulos con peso 700; cuerpo con peso 400.
- Tamaño de cuerpo >= 16px para lectura móvil.
- Longitud de línea limitada en web para mantener legibilidad.

## Layout

- Enfoque **content-first**: una idea por tarjeta en el feed.
- Móvil: una columna, espaciado generoso.
- Web: columna de lectura centrada con ancho máximo; navegación secundaria.
- Detalle de norma: bloques "¿Qué cambia?", "¿A quién afecta?", "Cifras clave"
  y enlace destacado a la fuente oficial.

## Shapes

- Radios suaves (`sm` 6px, `md` 12px); sin esquinas marcadas.
- Tarjetas con borde sutil o sombra mínima.

## Components

- `button-primary`: fondo `primary`, texto blanco, radio `md`.
- Tarjeta de norma: título, fecha, categoría y resumen corto.
- Bloque de sección: etiqueta + contenido del resumen.
- Aviso de IA: banda sobria y visible, no un banner agresivo.
- Enlace de fuente oficial: siempre visible y claro.

## Core Screens

1. **Feed diario:** lista de normas del día.
2. **Detalle de norma:** resumen estructurado + fuente oficial + aviso de IA.
3. **Búsqueda:** campo + filtros (categoría, fecha) + resultados.
4. **Estados:** vacío, carga, error y "sin resultados".

## Responsive Baseline

- Móvil primero; funciona en vertical y horizontal.
- Web responsive con la misma UI compartida (Compose Multiplatform).
- Objetivos táctiles >= 44px.

## Accessibility Baseline

- Contraste AA como mínimo.
- Textos alternativos y etiquetas semánticas.
- Tamaño de texto escalable por el sistema.
- No depender solo del color para transmitir estado.

## Do's and Don'ts

- **Sí:** dar prioridad a la legibilidad y a la fuente oficial.
- **Sí:** usar el color de acento con moderación y solo para atención.
- **No:** estética sensacionalista o colores partidistas.
- **No:** ocultar el aviso de IA ni el enlace a la fuente.

## Open Design Questions

- Marca y nombre definitivos (pendiente).
- Elección final de tipografía e idioma de las lenguas cooficiales.
- Uso de iconografía propia.
