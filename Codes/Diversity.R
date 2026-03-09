# ==========================================================
# 1. CONFIGURACIÓN, LIBRERÍAS Y CARGA
# ==========================================================
library(tidyverse)
library(data.table)
library(openxlsx)
library(iNEXT)
library(overlap)
library(lubridate)
library(ggridges)
library(reshape2)
library(patchwork)

path_data <- "~/Desktop/FPVA/Data/Fototrampeo/I2D_FPVA_Fototrampeo_20260219.xlsx"
path_out  <- "~/Desktop/FPVA/Resultados/Fototrampeo/"
if(!dir.exists(path_out)) dir.create(path_out, recursive = TRUE)

obs  <- read.xlsx(path_data, sheet = "Observations")
media <- read.xlsx(path_data, sheet = "Media")
dev  <- read.xlsx(path_data, sheet = "Deployment")

# Joins y Limpieza
data_full <- as.data.table(obs) %>%
  left_join(select(as.data.table(media), mediaID, timestamp), by = "mediaID") %>%
  left_join(select(as.data.table(dev), deploymentID, locationName, habitat, latitude, longitude), by = "deploymentID") %>%
  filter(!is.na(scientificName) & scientificName != "")

# ==========================================================
# 2. BIODIVERSIDAD Y RAREFACCIÓN
# ==========================================================

# 2.1 Esfuerzo y RAI
esfuerzo_estaciones <- dev %>%
  mutate(inicio = as.Date(as_datetime(deploymentStart)),
         fin = as.Date(as_datetime(deploymentEnd)),
         dias = as.numeric(difftime(fin, inicio, units = "days"))) %>%
  filter(!is.na(dias))

total_esfuerzo <- sum(esfuerzo_estaciones$dias)

tab_rai <- data_full %>%
  group_by(scientificName) %>%
  summarise(n = n()) %>%
  mutate(RAI = (n / total_esfuerzo) * 100) %>%
  arrange(desc(n))

# 2.2 iNEXT y Tabla AsyEst
vector_iNEXT <- tab_rai$n
names(vector_iNEXT) <- tab_rai$scientificName
res_inext <- iNEXT(vector_iNEXT, q = c(0, 1, 2), datatype = "abundance")

df_asyest <- as.data.frame(res_inext$AsyEst)
colnames(df_asyest) <- c("Observed", "Estimator", "Est_se", "LCL", "UCL")
df_asyest$Metrica <- factor(rep(c("q0 (Riqueza)", "q1 (Shannon)", "q2 (Simpson)"), length.out = nrow(df_asyest)))

# 2.3 Gráficos Biodiversidad
plot_hill <- ggplot(df_asyest, aes(x = Metrica, y = Estimator)) +
  geom_errorbar(aes(ymin = LCL, ymax = UCL), width = 0.2, color = "royalblue") +
  geom_point(size = 4, color = "royalblue") +
  geom_point(aes(y = Observed), shape = 1, size = 4, stroke = 1) +
  facet_wrap(~Metrica, scales = "free") + theme_bw() + labs(title = "Diversidad Asintótica (Hill)")

plot_rarefaccion <- ggiNEXT(res_inext, type = 1, color.var = "Order.q") + theme_minimal()


# 2.4 Otros graficos
# 1. Preparar el vector de abundancia (Asumiendo que cada scientificName es una especie)
tab_abundancia_foto <- data_full %>%
  group_by(scientificName) %>%
  summarise(n = n()) %>%
  arrange(desc(n))

vector_iNEXT_foto <- tab_abundancia_foto$n
names(vector_iNEXT_foto) <- tab_abundancia_foto$scientificName

# 2. Ejecutar iNEXT para q=0
# Usamos knots = 100 para asegurar que la banda de confianza sea fluida y sin saltos
res_inext_foto <- iNEXT(vector_iNEXT_foto, q = 0, datatype = "abundance", knots = 100)

# 3. Graficar únicamente q0
plot_rarefaccion_foto <- ggiNEXT(res_inext_foto, type = 1) + 
  theme_minimal() +
  scale_color_manual(values = "royalblue") +
  scale_fill_manual(values = "royalblue") +
  labs(title = "Curva de Rarefacción: Fototrampeo",
       subtitle = "Riqueza de Especies (q0) - Todos los taxones incluidos",
       x = "Número de individuos (Detecciones)",
       y = "Riqueza de Especies") +
  theme(legend.position = "none")

print(plot_rarefaccion_foto)

# ==========================================================
# 2.1 CÁLCULO DE IAR Y TASAS (Preparado para comparaciones)
# ==========================================================

# Definimos el filtro de especies binominales (Género + epíteto)
data_especies <- data_full %>%
  filter(grepl("^[A-Za-z]+ [a-z]+", scientificName))

# Calculamos la tabla base
tab_rai_final <- data_especies %>%
  group_by(scientificName) %>%
  summarise(n_eventos = n()) %>%
  mutate(
    Esfuerzo_Total = total_esfuerzo,
    # Tasa de Encuentro: Úsala para comparar especies entre sí en este muestreo
    Tasa_Encuentro = (n_eventos / total_esfuerzo) * 100,
    # IAR: Guárdalo para comparar esta misma especie con el futuro muestreo
    IAR = Tasa_Encuentro 
  ) %>%
  arrange(desc(n_eventos))

# Seleccionamos el Top 10 para la gráfica
top_10_datos <- tab_rai_final %>% slice_max(n_eventos, n = 10)

# Graficamos y visualizamos 

plot_top10_rai <- ggplot(top_10_datos, aes(x = reorder(scientificName, Tasa_Encuentro), y = Tasa_Encuentro)) +
  geom_segment(aes(x = reorder(scientificName, Tasa_Encuentro), xend = reorder(scientificName, Tasa_Encuentro), 
                   y = 0, yend = Tasa_Encuentro), color = "grey") +
  geom_point(color = "royalblue", size = 4) +
  coord_flip() +
  theme_minimal() +
  labs(
    title = "Top 10 Especies con Mayor Tasa de Encuentro",
    subtitle = paste("Esfuerzo total:", round(total_esfuerzo, 1), "días-trampa"),
    x = NULL,
    y = "Eventos por cada 100 días-trampa",
    caption = "Filtro: Solo nombres binominales (Género especie).\nBasado en recomendaciones de Mandujano (2024)."
  ) +
  theme(panel.grid.minor = element_blank())

print(plot_top10_rai)


# ==========================================================
# 3. PATRONES DE ACTIVIDAD
# ==========================================================

# 3.1 Procesamiento Temporal (Ajuste UTC-5)
data_actividad <- data_full %>%
  mutate(time_local = as_datetime(timestamp) - hours(5), 
         hora_decimal = hour(time_local) + minute(time_local)/60 + second(time_local)/3600,
         radianes = hora_decimal * 2 * pi / 24) %>%
  filter(!is.na(radianes))

# Función Pico
get_peak_hour <- function(rad) {
  if(length(rad) < 5) return(NA)
  dens <- density(rad, from = 0, to = 2*pi)
  return((dens$x[which.max(dens$y)] * 24) / (2 * pi))
}

tab_actividad <- data_actividad %>%
  group_by(scientificName) %>%
  summarise(Abundancia = n(), Hora_Pico_Dec = get_peak_hour(radianes)) %>%
  mutate(Hora_Pico = sprintf("%02d:%02d", floor(Hora_Pico_Dec), round((Hora_Pico_Dec %% 1) * 60)),
         Nicho = case_when(Hora_Pico_Dec >= 5 & Hora_Pico_Dec <= 7 ~ "Crepuscular (Alba)",
                           Hora_Pico_Dec > 7 & Hora_Pico_Dec < 17 ~ "Diurno",
                           Hora_Pico_Dec >= 17 & Hora_Pico_Dec <= 19 ~ "Crepuscular (Ocaso)",
                           TRUE ~ "Nocturno"))

# 3.2 RidgePlot
plot_ridges <- data_actividad %>%
  left_join(select(tab_actividad, scientificName, Nicho, Hora_Pico_Dec), by = "scientificName") %>%
  ggplot(aes(x = hora_decimal, y = reorder(scientificName, Hora_Pico_Dec), fill = Nicho)) +
  geom_density_ridges(alpha = 0.7, scale = 1.2) +
  scale_fill_manual(values = c("#f39c12", "#2ecc71", "#d35400", "#2c3e50")) +
  theme_minimal() + labs(title = "Actividad por Especie", x = "Hora", y = "Especie")

# ==========================================================
# 4. MATRIZ DE SOLAPAMIENTO (OVERLAP)
# ==========================================================

spp_list <- tab_actividad$scientificName
n_spp <- length(spp_list)
matriz_overlap <- matrix(NA, n_spp, n_spp, dimnames = list(spp_list, spp_list))

for(i in 1:n_spp) {
  for(j in 1:n_spp) {
    rad_i <- data_actividad$radianes[data_actividad$scientificName == spp_list[i]]
    rad_j <- data_actividad$radianes[data_actividad$scientificName == spp_list[j]]
    if(length(rad_i) >= 5 & length(rad_j) >= 5) matriz_overlap[i,j] <- overlapEst(rad_i, rad_j, type="Dhat4")
  }
}

# Heatmap
matriz_plot <- matriz_overlap
matriz_plot[upper.tri(matriz_plot)] <- NA
df_ov_plot <- melt(matriz_plot, na.rm = TRUE)

plot_overlap_map <- ggplot(df_ov_plot, aes(Var1, Var2, fill = value)) +
  geom_tile() + scale_fill_gradientn(colors = c("#fff5f0", "#fb6a4a", "#67000d"), limits = c(0, 1)) +
  theme_minimal() + theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
  labs(title = "Matriz de Solapamiento Temporal", x = NULL, y = NULL)


# ==========================================================
# 4.1. Indicador de patron de actividad y coeficiente de solapamiento
# ==========================================================

# 4. Cálculo de Matriz de Solapamiento (Siguiendo a Negret et al. 2023)
n_top <- length(top_10_spp)
matriz_delta <- matrix(1, n_top, n_top, dimnames = list(top_10_spp, top_10_spp))

for(i in 1:(n_top-1)) {
  for(j in (i+1):n_top) {
    rad_i <- data_actividad_top$radianes[data_actividad_top$scientificName == top_10_spp[i]]
    rad_j <- data_actividad_top$radianes[data_actividad_top$scientificName == top_10_spp[j]]
    
    # Validamos que ambas especies tengan suficientes datos (mínimo 5 según literatura)
    if(length(rad_i) >= 5 & length(rad_j) >= 5) {
      
      # CORRECCIÓN: Los argumentos deben ir en Mayúsculas ("Dhat1", "Dhat4")
      estimador <- if(min(length(rad_i), length(rad_j)) > 50) "Dhat4" else "Dhat1"
      
      val <- overlapEst(rad_i, rad_j, type = estimador)
      matriz_delta[i,j] <- matriz_delta[j,i] <- val
      
    } else {
      # Si no hay datos suficientes, asignamos NA
      matriz_delta[i,j] <- matriz_delta[j,i] <- NA
    }
  }
}
# Graficamos
# Función Radial Actualizada
plot_radial_activity <- function(data, spp_name) {
  df_spp <- data %>% filter(scientificName == spp_name)
  n_obs <- nrow(df_spp)
  
  ggplot(df_spp, aes(x = hora_decimal)) +
    # Capa de histograma de fondo (24 horas)
    geom_histogram(aes(y = ..density..), bins = 24, fill = "grey92", color = "white") +
    # Densidad de Kernel
    geom_density(fill = "royalblue", alpha = 0.3, color = "royalblue", linewidth = 0.8) + 
    scale_x_continuous(breaks = seq(0, 21, by = 3), limits = c(0, 24),
                       labels = c("00","03","06","09","12","15","18","21")) +
    coord_polar(start = 0) +
    theme_minimal() +
    labs(title = spp_name, 
         subtitle = paste("n =", n_obs), # Incluimos el n como sugiere Negret
         x = NULL, y = NULL) +
    theme(axis.text.y = element_blank(),
          panel.grid.minor = element_blank(),
          plot.title = element_text(size = 10, face = "bold", hjust = 0.5),
          plot.subtitle = element_text(size = 8, hjust = 0.5))
}

# Volver a generar la lista con la función corregida
lista_radiales <- lapply(top_10_spp, function(s) plot_radial_activity(data_actividad_top, s))


# 1. Unir los 10 radiales en una sola gráfica (panel de 2 filas x 5 columnas)
grafica_actividad_integrada <- wrap_plots(lista_radiales, ncol = 5) + 
  plot_layout(guides = 'collect') + # Agrupa leyendas si las hubiera
  plot_annotation(
    title = "Patrones de Actividad Temporal: Top 10 Especies",
    subtitle = "Gráficos radiales de densidad (Ciclo de 24 horas)",
    caption = "Basado en la metodología de Negret et al. (2023) | Datos: Fototrampeo",
    theme = theme(
      plot.title = element_text(size = 18, face = "bold", hjust = 0.5),
      plot.subtitle = element_text(size = 14, hjust = 0.5)
    )
  )

# 2. Mostrar la gráfica en RStudio
print(grafica_actividad_integrada)

# 3. Guardar la gráfica en alta resolución para informe
ggsave(paste0(path_out, "05_Panel_Actividad_Radial_Top10.png"), 
       grafica_actividad_integrada, 
       width = 16, height = 8, dpi = 300)

# visualización 
# Heatmap mejorado con paleta "Magma" 
library(reshape2)
df_overlap <- melt(matriz_delta, na.rm = TRUE)

plot_overlap <- ggplot(df_overlap, aes(Var1, Var2, fill = value)) +
  geom_tile(color = "white") +
  scale_fill_viridis_c(option = "magma", limit = c(0,1), name = "Coef. Delta (Δ)") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 9),
        axis.text.y = element_text(size = 9)) +
  labs(title = "Matriz de Solapamiento Temporal (Negret et al. 2023)",
       subtitle = "Estimadores Dhat1/Dhat4 según tamaño de muestra",
       x = NULL, y = NULL)

print(plot_overlap)

# ==========================================================
# 4.2 ÍNDICES DE DIURNALIDAD Y NOCTURNALIDAD
# ==========================================================

tab_periodos <- data_actividad_top %>%
  mutate(Periodo = case_when(
    hora_decimal >= 5 & hora_decimal < 7   ~ "Crepuscular",
    hora_decimal >= 7 & hora_decimal < 17  ~ "Diurno",
    hora_decimal >= 17 & hora_decimal < 19 ~ "Crepuscular",
    TRUE                                   ~ "Nocturno"
  )) %>%
  group_by(scientificName, Periodo) %>%
  summarise(n = n(), .groups = "drop_last") %>%
  mutate(Proporcion = (n / sum(n)) * 100)

# Ver tabla de resultados
print(tab_periodos)

# grafica
plot_nicho_temporal <- ggplot(tab_periodos, aes(x = reorder(scientificName, Proporcion), y = Proporcion, fill = Periodo)) +
  geom_bar(stat = "identity", position = "stack") +
  scale_fill_manual(values = c("Crepuscular" = "#f39c12", "Diurno" = "#f1c40f", "Nocturno" = "#2c3e50")) +
  coord_flip() +
  theme_minimal() +
  labs(
    title = "Estratificación del Nicho Temporal (Top 10)",
    subtitle = "Proporción de registros por periodo del día",
    x = "", y = "Porcentaje de registros (%)",
    fill = "Periodo"
  )

print(plot_nicho_temporal)


# 
indice_nocturnalidad <- tab_periodos %>%
  filter(Periodo == "Nocturno") %>%
  select(scientificName, IN = Proporcion) %>%
  arrange(desc(IN))

# Este índice va de 0 (estrictamente diurno) a 100 (estrictamente nocturno)
print(indice_nocturnalidad)


# ==========================================================
# 5. EXPORTACIÓN FINAL
# ==========================================================

# Excel Consolidado
wb <- createWorkbook()
addWorksheet(wb, "RAI_Abundancia"); writeData(wb, "RAI_Abundancia", tab_rai)
addWorksheet(wb, "Diversidad_Hill"); writeData(wb, "Diversidad_Hill", df_asyest)
addWorksheet(wb, "Nichos_Actividad"); writeData(wb, "Nichos_Actividad", tab_actividad)
addWorksheet(wb, "Matriz_Solapamiento"); writeData(wb, "Matriz_Solapamiento", matriz_overlap, rowNames = TRUE)
saveWorkbook(wb, paste0(path_out, "Resultados_Consolidados_FPVA.xlsx"), overwrite = TRUE)

# Guardar Gráficos
ggsave(paste0(path_out, "01_Hill_Plot.png"), plot_hill, width = 10, height = 6)
ggsave(paste0(path_out, "02_Rarefaccion.png"), plot_rarefaccion, width = 10, height = 6)
ggsave(paste0(path_out, "03_RidgePlot_Actividad.png"), plot_ridges, width = 10, height = 8)
ggsave(paste0(path_out, "04_Heatmap_Overlap.png"), plot_overlap_map, width = 12, height = 10)

message("Análisis completo. Todos los archivos están en: ", path_out)