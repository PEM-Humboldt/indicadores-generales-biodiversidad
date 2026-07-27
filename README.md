# Indicadores generales de biodiversidad

Este repositorio contiene las herramientas computacionales para caracterizar y comparar la diversidad usando diferentes índices como la serie de Hill, curvas de esfuerzo de muestreo y patrones de actividad de las especies. El código permite transformar datos brutos de campo en indicadores de representatividad de muestreo y caracterización de nichos de actividad.

El siguiente flujo de trabajo integra los siguientes indicadores:
- Diversidad de especies (Números de Hill: q0 riqueza de especies, q1 exponencial de Shannon ponderado por abundancia, q2 recíproco de Simpson que enfatiza especies dominantes): riqueza observada y estimada en sus tres órdenes de diversidad.
- Representatividad acumulada del muestreo: fracción de la diversidad esperada que fue efectivamente detectada.
- Frecuencia de detección y abundancia relativa de aves: RAI calculado a partir de registros de aves en puntos de conteo o cámaras trampa.
- Abundancia relativa de mamíferos: RAI calculado a partir de eventos de detección independientes de mamíferos en cámaras trampa.
- Solapamiento de mamíferos (conjunto completo): coeficiente Δ entre pares de especies de mamíferos detectadas por cámaras trampa.
- Solapamiento de especies focales: coeficiente Δ entre pares de especies de interés de conservación definidas por el proyecto (pueden incluir aves, mamíferos u otros taxones).

---

## Fundamento metodológico

Esta sección explica el *qué* y el *por qué* de los cálculos. El detalle de calidad e incertidumbre de cada indicador vive en las fichas del catálogo de indicadores; aquí solo va lo necesario para entender y reproducir el código.

### Diversidad de especies (Números de Hill) y representatividad del muestreo

- **Qué calcula:** los tres órdenes de diversidad de Hill — q=0 (riqueza de especies), q=1 (exponencial de Shannon, ponderado por abundancia) y q=2 (recíproco de Simpson, énfasis en especies dominantes) — junto con la representatividad acumulada del muestreo (razón entre riqueza observada y estimada) y la curva de acumulación de especies por monitor.
- **Enfoque:** enfoque unificado de números de Hill de Chao et al. (2014), que permite comparar diversidad entre sitios y períodos corrigiendo el efecto del esfuerzo de muestreo.
- **Implementación:** paquete `iNEXT` de R (Hsieh et al., 2016), con interpolación/extrapolación (100 knots) e intervalos de confianza por bootstrap (999 réplicas).
- **Cómo se calcula, paso a paso:**
  1. Curaduría: validación de nombres de especies y registros de detección.
  2. Cálculo del esfuerzo: días-trampa activos por estación (tabla Deployment).
  3. Construcción de la matriz de abundancias por especie.
  4. Ejecución de `iNEXT`: curvas de rarefacción/extrapolación y números de Hill.
  5. Extracción de resultados: (a) valores q0, q1, q2; (b) razón de completitud (riqueza observada/estimada); (c) curva acumulada por monitor.

### Solapamiento de patrones de actividad (mamíferos y especies focales)

- **Qué calcula:** el coeficiente Delta (Δ) de solapamiento entre las distribuciones de actividad temporal (diel) de pares de especies — para el conjunto completo de mamíferos y, por separado, para pares de especies focales de interés de conservación.
- **Enfoque:** el nicho temporal permite inferir interacciones ecológicas (competencia, co-ocurrencia, evitación depredador-presa) sin necesidad de observación directa (Kronfeld-Schor & Dayan, 2003).
- **Implementación:** paquete `overlap` de R (Ridout & Linkie, 2009), metodología según Negret et al. (2023). Se usa el estimador Dhat1 (kernel von Mises) para muestras pequeñas (n < 50 detecciones) y Dhat4 (trigonométrico) para muestras grandes (n ≥ 50). Solo se incluyen especies con n ≥ 5 detecciones; los intervalos de confianza se calculan por bootstrap (999 réplicas).
- **Cómo se calcula, paso a paso:**
  1. Extracción de timestamps de detección por especie (tabla Media).
  2. Ajuste de zona horaria (UTC-5, Colombia) y conversión a tiempo solar local.
  3. Transformación a radianes.
  4. Selección del estimador según n por especie (Dhat1 o Dhat4).
  5. Cálculo del coeficiente Delta por par de especies.
  6. Bootstrap para los intervalos de confianza.
  7. Diferenciación de resultados: grupo completo de mamíferos vs. especies focales.

---


## Estructura del repositorio

```
.
── Codes
│   ├── Diversitu_Punteos_ conteo.R
│   └── Diversity.R
├── Data
│   ├── Bioacustica
│   │   └── Plantilla monitoreo acústico - FPV Amazonía.xlsx
│   ├── Fototrampeo
│   │   └── I2D_FPVA_Fototrampeo_20260219.xlsx
│   └── Puntos_conteo
│       └── I2D-BIO_2025_023.xlsx
├── README.md
└── Results
```

## Descripción de los scripts

| Script | Qué hace | Insumos que usa | Salida principal |
|---|---|---|---|
| `01_carga_datos.R` | Define rutas de entrada/salida y consolida las tablas de observaciones y metadatos en un solo objeto de trabajo. | Archivo Excel con pestañas Observations, Media, Deployment | Tablas consolidadas en memoria |
| `02_diversidad_iNEXT.R` | Calcula la riqueza (q0), diversidad de Shannon (q1) y de Simpson (q2), y las curvas de rarefacción/extrapolación por sitio y por monitor. | Tabla consolidada de observaciones + esfuerzo (Deployment) | Objeto con números de Hill y curvas de acumulación |
| `03_patrones_actividad.R` | Convierte las estampas de tiempo a tiempo solar (ajuste UTC-5) y a radianes; clasifica cada especie en un nicho (diurno, nocturno, crepuscular) según su hora pico. | Tabla Media (timestamps) | Tabla de horas de actividad por especie |
| `04_solapamiento_overlap.R` | Calcula la matriz de solapamiento de nicho temporal (coeficiente Δ) entre pares de especies, con bootstrap para los intervalos de confianza. | Salida de `03_patrones_actividad.R` | Matriz de solapamiento (`tab_actividad`) |
| `05_exportar_resultados.R` | Guarda el libro de Excel consolidado con todos los indicadores y los gráficos en alta resolución. | Salidas de los scripts anteriores | Libro `.xlsx` + archivos `.png` |


---

## Prerrequisitos

Para ejecutar correctamente este proyecto es necesario contar con **R (versión 4.0 o superior)** y las siguientes librerías. Se indican las versiones con las que se probó el flujo, para evitar problemas de compatibilidad en ejecuciones futuras:

| Librería | Uso en el proyecto | Versión probada |
|---|---|---|
| `tidyverse` | Manipulación de datos y gráficas | ‘2.0.0’ |
| `iNEXT` | Cálculo de números de Hill y curvas de rarefacción | ‘3.0.0’ |
| `overlap` | Estadística circular y solapamiento temporal | ‘0.3.9’|
| `lubridate` | Manejo de estampas de tiempo y zonas horarias | ‘1.9.2’|
| `ggridges` | Visualización de densidades de actividad (RidgePlots) | ‘0.5.6’ |
| `data.table`  | Lectura y escritura eficiente de datos | ‘1.17.8’|
| `openxlsx` | Lectura y escritura eficiente de datos | ‘4.2.5.2’|
| `ggridges` | Visualización de densidades de actividad (RidgePlots) | ‘0.5.6’ |

**Ejemplo de instalación:**

```r
install.packages(c("tidyverse", "iNEXT", "overlap", "lubridate", "ggridges", "openxlsx", "reshape2"))
```

---

## Archivos necesarios

El script está diseñado para leer archivos de Excel con la estructura de metadatos DarwinCore para fototrampeo y bioacústica. Se requiere el archivo principal con las siguientes pestañas:

* **Observations:** listado de registros con nombres científicos.
* **Media:** metadatos de archivos (vínculo entre fotos/audios y tiempo); el script usa esta tabla para construir la estampa de tiempo de cada detección.
* **Deployment:** ubicación de estaciones, tipos de hábitat y esfuerzo de muestreo.

**Descarga de archivos:**

* Puede descargar la plantilla de datos de ejemplo en: [Enlace al Repositorio/Data/I2D_FPVA_Fototrampeo_20260219.xlsx]

---

## Cómo ejecutar

Este script está pensado para correrse **de forma secuencial, bloque por bloque, con un único punto de interacción manual al inicio** (definir las rutas de entrada y salida). El resto de los bloques no requiere que el usuario modifique parámetros, salvo que quiera ajustar algo puntual (por ejemplo, el umbral de detecciones mínimas). Se indica explícitamente en cada paso.

1. **Configuración de entorno** *(requiere acción del usuario)*
   - Defina las rutas de entrada (`path_data`) y salida (`path_out`) al inicio del script.
   - Ejecute el bloque de carga para consolidar las tablas de observaciones y metadatos.

2. **Cálculo de indicadores de diversidad** *(se ejecuta sin intervención)*
   - Ejecute el Bloque 2 (`iNEXT`). El script calculará automáticamente la riqueza (q0), diversidad de Shannon (q1) y Simpson (q2).
   - Visualice las curvas de rarefacción para evaluar si el esfuerzo de muestreo fue suficiente.

3. **Análisis de patrones de actividad** *(se ejecuta sin intervención)*
   - Ejecute el Bloque 3. Se realizará la conversión de tiempo a radianes (ajustando la zona horaria UTC-5 si es necesario).
   - El sistema clasificará a cada especie en nichos: diurno, nocturno o crepuscular, basándose en su hora pico.

4. **Generación de solapamiento (overlap)** *(se ejecuta sin intervención)*
   - Ejecute el Bloque 4 para crear la matriz de solapamiento de nicho temporal.
   - *Nota:* el script solo incluirá especies con ≥ 5 registros para asegurar validez estadística.

5. **Exportación de resultados** *(se ejecuta sin intervención)*
   - Ejecute el bloque final para guardar el libro de Excel consolidado y los archivos PNG de alta resolución (300 dpi).

**Ejemplo de uso:**
Tras ejecutar el análisis, podrá consultar el objeto `tab_actividad` para identificar, por ejemplo, que el *Dasypus novemcinctus* presenta un nicho marcadamente nocturno con una hora pico estimada a las 22:45.

---

## Autores(as) y contacto

* **Juan C Rey** — *Investigador* — [jrey@humboldt.org.co]

## Licencia

Este proyecto está bajo la licencia MIT; consulte el archivo [LICENCIA](https://www.google.com/search?q=LICENCIA) para más detalles.

## Agradecimientos

* Al equipo de campo del proyecto **FPVA**  y a la comunidad por la recolección de los datos biológicos.
* Adaptación en los marcos de trabajo de Meredith & Ridout para el análisis de solapamiento temporal.

## Referencias metodológicas

1. Chao, A. et al. (2014). Rarefaction and extrapolation with Hill numbers. *Ecological Monographs*, 84: 45–67.
2. Hsieh, T.C. et al. (2016). iNEXT: an R package for rarefaction and extrapolation of species diversity. *Methods in Ecology and Evolution*, 7: 1451–1456.
3. Ridout, M.S. & Linkie, M. (2009). Estimating overlap of daily activity patterns from camera trap data. *JABES*, 14: 322–337.
4. Negret, P.J. et al. (2023). Metodología para el análisis de solapamiento de nicho temporal en fauna silvestre.
5. Kronfeld-Schor, N. & Dayan, T. (2003). Partitioning of time as an ecological resource. *Annual Review of Ecology, Evolution, and Systematics*, 34: 153–181.
