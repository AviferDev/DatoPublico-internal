# Capturas para Pull Requests

> Evidencia **visual** para los PR que cambian la interfaz. Una rama = un
> subdirectorio `docs/pr/<slug-de-rama>/` con las capturas **antes** y **después**.

## Cuándo

Cuando el PR modifica **píxeles visibles**: pantallas, componentes, tema, iconos
o textos de UI de `:composeApp` (y `DESIGN.md` cuando cambie el diseño). **No**
aplica a cambios solo de dominio/datos, backend, tests o documentación sin
impacto visual.

## Cómo

- **Antes**: captura el estado base **antes** de tocar el código (la rama tal como
  sale de `origin/main`), no después de aplicar el cambio.
- **Después**: captura al **final**, con el cambio aplicado y la app reconstruida.
- Una captura **por pantalla** afectada. La UI es **común** (`commonMain`), así que
  una sola plataforma representativa basta; usa la que puedas ejecutar en la máquina
  (Android en el emulador o Web en el navegador).
- Nombres: `antes-<pantalla>.png` y `despues-<pantalla>.png`.
- Commitéalas en la rama (no en `main`).

## Cómo enlazarlas en el PR

Enlaza con **URL absoluta a la rama** (no rutas relativas, que GitHub resuelve contra
`main` y no cargan hasta el merge):

```md
![antes](https://github.com/<owner>/<repo>/blob/<rama>/docs/pr/<slug>/antes-<pantalla>.png?raw=true)
![después](https://github.com/<owner>/<repo>/blob/<rama>/docs/pr/<slug>/despues-<pantalla>.png?raw=true)
```

- **No** uses `.../raw/<rama>/...`: redirige a `raw.githubusercontent.com`, que sin la
  cookie de sesión da `404` en un repo privado.
- La URL apunta a la **rama**; si la borras tras el merge o reescribes el historial,
  actualiza los enlaces.

## Si no se puede capturar

Si falta el entorno (sin emulador Android ni navegador, o la pantalla exige un estado
no reproducible), **indícalo y justifícalo** en el PR; el dueño lo aprueba o lo rechaza.
No se mergea un cambio visual sin capturas ni justificación.
