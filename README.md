# Indicadores generales de biodiversidad

Este repositorio contiene las herramientas computacionales para  caracterizar y comparar la diversidad usando diferentes indices como la serie de Hill, curvas de esfuerzo de muestero y patrones de atividad de las especies. El código permite transformar datos brutos de campo en indicadores de representatividad de muestreo y caracterización de nichos de actividad.

**Estado del Proyecto:** Estable / Finalizado. Optimizado para procesar grandes volúmenes de datos y generar salidas gráficas de alta resolución para reportes técnicos.

## Prerequisitos

Para ejecutar correctamente este script, es necesario contar con **R (versión 4.0 o superior)** y tener instaladas las siguientes bibliotecas:

* `tidyverse`: Para manipulación de datos y gráficas.
* `iNEXT`: Para el cálculo de números de Hill y curvas de rarefacción.
* `overlap`: Para estadística circular y solapamiento temporal.
* `lubridate`: Para el manejo de estampas de tiempo y zonas horarias.
* `ggridges`: Para la visualización de densidades de actividad (RidgePlots).
* `data.table` y `openxlsx`: Para lectura y escritura eficiente de datos.

**Ejemplo de instalación:**

```r
install.packages(c("tidyverse", "iNEXT", "overlap", "lubridate", "ggridges", "openxlsx", "reshape2"))

```

## Archivos Necesarios

El script está diseñado para leer archivos de Excel con la estructura de metadatos DarwinCore para fototrampeo y bioacústica. Se requiere el archivo principal con las siguientes pestañas:

* **Observations:** Listado de registros con nombres científicos.
* **Media:** Metadatos de archivos (vínculo entre fotos/audios y tiempo).
* **Deployment:** Ubicación de estaciones, tipos de hábitat y esfuerzo de muestreo.

**Descarga de archivos:**

* Puede descargar la plantilla de datos de ejemplo en: [Enlace al Repositorio/Data/I2D_FPVA_Fototrampeo_20260219.xlsx]

## Como ejecutar

Siga este orden lógico para garantizar la correcta ejecución de los análisis:

1. **Configuración de Entorno:**
* Defina las rutas de entrada (`path_data`) y salida (`path_out`) al inicio del script.
* Ejecute el bloque de carga para consolidar las tablas de observaciones y metadatos.


2. **Cálculo de Indicadores de Biodiversidad:**
* Ejecute el Bloque 2 (`iNEXT`). El script calculará automáticamente la riqueza (q0), diversidad de Shannon (q1) y Simpson (q2).
* Visualice las curvas de rarefacción para evaluar si el esfuerzo de muestreo fue suficiente.


3. **Análisis de Patrones de Actividad:**
* Ejecute el Bloque 3. Se realizará la conversión de tiempo a radianes (ajustando la zona horaria UTC-5 si es necesario).
* El sistema clasificará a cada especie en nichos: Diurno, Nocturno o Crepuscular basándose en su hora pico.


4. **Generación de Solapamiento (Overlap):**
* Ejecute el Bloque 4 para crear la matriz de solapamiento de nicho temporal.
* *Nota:* El script solo incluirá especies con $\ge 5$ registros para asegurar validez estadística.


5. **Exportación de Resultados:**
* Ejecute el Bloque final para guardar el libro de Excel consolidado y los archivos PNG de alta resolución (300 dpi).



**Ejemplo de uso:**
Tras ejecutar el análisis, podrá consultar el objeto `tab_actividad` para identificar, por ejemplo, que el *Dasypus novemcinctus* presenta un nicho marcadamente nocturno con una hora pico estimada a las 22:45.

## Autores(as) y contacto

* **Juan C Rey** - *Investigador* - [jrey@humboldt.org.co]
* **PurpleBooth** - *Manual de documentación base* - [PurpleBooth](https://github.com/PurpleBooth)

## Licencia

Este proyecto está bajo la licencia MIT, mira el archivo [LICENCIA](https://www.google.com/search?q=LICENCIA) para obtener más detalles.

## Agradecimientos

* Al equipo de campo del proyecto **FPVA** por la recolección de los datos biológicos.
* Inspiración en los marcos de trabajo de Meredith & Ridout para el análisis de solapamiento temporal.
