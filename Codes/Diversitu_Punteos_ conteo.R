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
library(overlap)


# Ajuste de rutas para AVES
path_data <- "~/Desktop/FPVA/Data/Puntos_conteo/I2D-BIO_2025_023.xlsx" 
path_out  <- "~/Desktop/FPVA/Resultados/Aves/"
if(!dir.exists(path_out)) dir.create(path_out, recursive = TRUE)

# Cargar tablas de Aves
obs_data  <- read.xlsx(path_data, sheet = "Registros")   # Tu primera tabla (registros)
med_data <- read.xlsx(path_data, sheet = "Evento")   # Tu segunda tabla (eventos/metadatos)

# Forma 1: Directa
obs_data <- filter(obs_data, taxonRank == "Especie")

# Join Maestro adaptado a la estructura de Aves
# Usamos 'eventID' como llave de unión entre registros y metadatos del punto
data_full <- as.data.table(obs_data) %>%
  left_join(select(as.data.table(med_data), 
                   eventID, parentEventID, eventDate, eventTime, 
                   habitat, decimalLatitude, decimalLongitude, samplingEffort), 
            by = "eventID") %>%
  filter(!is.na(scientificName) & scientificName != "")

# ==========================================================
# 2. BIODIVERSIDAD Y RAREFACCIÓN (AVES)
# ==========================================================

# 2.1 Esfuerzo y RAI (Normalizado por número de puntos de conteo)
# En aves, el esfuerzo suele ser el número total de puntos realizados
n_puntos <- length(unique(med_data$eventID))

tab_rai <- data_full %>%
  group_by(scientificName) %>%
  summarise(n = n()) %>%
  mutate(RAI = (n / n_puntos) * 100) %>% # Abundancia relativa por cada 100 puntos
  arrange(desc(n))

# 2.2 iNEXT y Tabla AsyEst
vector_iNEXT <- tab_rai$n
names(vector_iNEXT) <- tab_rai$scientificName
res_inext <- iNEXT(vector_iNEXT, q = c(0, 1, 2), datatype = "abundance")

df_asyest <- as.data.frame(res_inext$AsyEst)
colnames(df_asyest) <- c("Observed", "Estimator", "Est_se", "LCL", "UCL")
df_asyest$Metrica <- factor(rep(c("q0 (Riqueza)", "q1 (Shannon)", "q2 (Simpson)"), length.out = nrow(df_asyest)))

# 2.3 Gráficos
plot_hill <- ggplot(df_asyest, aes(x = Metrica, y = Estimator)) +
  geom_errorbar(aes(ymin = LCL, ymax = UCL), width = 0.2, color = "darkgreen") +
  geom_point(size = 4, color = "darkgreen") +
  geom_point(aes(y = Observed), shape = 1, size = 4, stroke = 1) +
  facet_wrap(~Metrica, scales = "free") + theme_bw() + 
  labs(title = "Diversidad Asintótica (Aves - Puntos de Conteo)")

plot_rarefaccion <- ggiNEXT(res_inext, type = 1, color.var = "Order.q") + theme_minimal()


#################################
# Cifras de Biodiversidad con iNEXT por categoria de habitat
#################################

# Agrupamos por categorias
# 1. Definimos el diccionario (basado en tu lista de med_data$habitat)
diccionario_habitats <- data.frame(
  habitat = c("Borde de bosque", "Borde de bosque de caño y potrero arbolado", 
              "Borde de bosque y potrero", "Borde de rastrojo", 
              "Bosque de caño Hondo", "Bosque entresacado con palmas", 
              "Bosque tropical", "Potrero arbolado", "Rastrojo inmerso en potrero"),
  Categoria = c("Borde", "Borde", "Borde", "Borde", 
                "Interior", "Interior", "Interior", 
                "Abierto", "Abierto")
)

# 2. Unión y Filtro
data_biodiv <- obs_data %>%
  # Primero filtramos solo especies
  filter(taxonRank == "Especie") %>%
  # Traemos la columna 'habitat' desde med_data usando eventID
  left_join(select(med_data, eventID, habitat), by = "eventID") %>%
  # Ahora que ya tenemos 'habitat', traemos la 'Categoria'
  left_join(diccionario_habitats, by = "habitat") %>%
  # Limpiamos posibles NAs
  filter(!is.na(Categoria))

# Verificación de datos por categoría
table(data_biodiv$Categoria)

# 1. Preparar lista para iNEXT
lista_categorias <- data_biodiv %>%
  group_by(Categoria, scientificName) %>%
  summarise(Abundancia = n(), .groups = "drop") %>%
  split(.$Categoria) %>%
  map(~ setNames(.x$Abundancia, .x$scientificName))

# 2. Ejecutar iNEXT (q=0 es Riqueza, q=1 es Shannon, q=2 es Simpson)
res_inext_cat <- iNEXT(lista_categorias, q = c(0, 1, 2), datatype = "abundance")

# 3. EXTRAER LAS CIFRAS (La tabla que querías)
cifras_asyest <- as.data.frame(res_inext_cat$AsyEst)
print(cifras_asyest)

#################################
# Visualización Comparativa
#################################
# Gráfica de Rarefacción facetada por Categoría de Hábitat
plot_rarefaccion_cat <- ggiNEXT(res_inext_cat, type = 1, facet.var = "Order.q") +
  theme_minimal() +
  scale_color_manual(values = c("Abierto" = "#f1c40f", "Borde" = "#e67e22", "Interior" = "#27ae60")) +
  scale_fill_manual(values = c("Abierto" = "#f1c40f", "Borde" = "#e67e22", "Interior" = "#27ae60")) +
  labs(title = "Curvas de Rarefacción por Categoría de Hábitat",
       x = "Individuos detectados", y = "Diversidad (Hill Numbers)")

print(plot_rarefaccion_cat)

# 1. Convertir la tabla a dataframe y limpiar nombres para ggplot
df_asyest_plot <- as.data.frame(res_inext_cat$AsyEst)

# 2. Ajustar nombres de las métricas para que se vean bien en los títulos
df_asyest_plot <- df_asyest_plot %>%
  mutate(Diversity = case_when(
    Diversity == "Species richness" ~ "q0: Riqueza de Especies",
    Diversity == "Shannon diversity" ~ "q1: Diversidad de Shannon",
    Diversity == "Simpson diversity" ~ "q2: Diversidad de Simpson"
  ))

# 3. Crear la gráfica
plot_asyest_final <- ggplot(df_asyest_plot, aes(x = Assemblage, y = Estimator, color = Assemblage)) +
  # Barras de error (Intervalos de Confianza al 95%)
  geom_errorbar(aes(ymin = LCL, ymax = UCL), width = 0.2, size = 1) +
  # Punto del Estimador (Diversidad Esperada)
  geom_point(size = 4) +
  # Punto de lo Observado (Diversidad Real en campo) para comparar
  geom_point(aes(y = Observed), color = "black", shape = 1, size = 4, stroke = 1.2) +
  # Dividir por tipo de Diversidad
  facet_wrap(~Diversity, scales = "free_y", ncol = 1) +
  # Estética
  scale_color_manual(values = c("Abierto" = "#f1c40f", "Borde" = "#e67e22", "Interior" = "#27ae60")) +
  theme_bw() +
  labs(title = "Comparativa de Diversidad Asintótica (Hill Numbers)",
       subtitle = "Puntos Azules/Color: Estimados (Chao) | Círculos Negros: Observados",
       x = "Categoría de Hábitat", 
       y = "Número Efectivo de Especies") +
  theme(strip.text = element_text(face = "bold", size = 11),
        legend.position = "none")

# Mostrar gráfica
print(plot_asyest_final)

# Graficas de solo q0 y de barras observadas
# Ajusta 'knots' a un número alto como 100 para suavizar la curva
res_inext_cat <- iNEXT(lista_categorias, q = 0, datatype = "abundance", knots = 100)

# Esto debería generar cintas suaves automáticamente
ggiNEXT(res_inext_cat, type = 1) +
  scale_color_manual(values = c("Abierto" = "#f1c40f", "Borde" = "#e67e22", "Interior" = "#27ae60")) +
  scale_fill_manual(values = c("Abierto" = "#f1c40f", "Borde" = "#e67e22", "Interior" = "#27ae60")) +
  theme_minimal()

# Filtrar el objeto de iNEXT para mostrar solo q = 0
plot_rarefaccion_q0 <- ggiNEXT(res_inext_cat, type = 1) +
  # Filtramos por Order.q == 0
  facet_null() + 
  aes(subset = (Order.q == 0)) +
  theme_minimal() +
  scale_color_manual(values = c("Abierto" = "#f1c40f", "Borde" = "#e67e22", "Interior" = "#27ae60")) +
  scale_fill_manual(values = c("Abierto" = "#f1c40f", "Borde" = "#e67e22", "Interior" = "#27ae60")) +
  labs(title = "Curvas de Rarefacción: Riqueza de Especies (q0)",
       subtitle = "Comparativa por categoría de hábitat",
       x = "Individuos detectados", 
       y = "Riqueza de Especies")

print(plot_rarefaccion_q0)

####
# 1. Preparar los datos de q0
df_q0_final <- as.data.frame(res_inext_cat$AsyEst) %>%
  filter(Diversity == "Species richness")

# 2. Crear la gráfica de barras superpuestas
plot_riqueza_barras <- ggplot(df_q0_final, aes(x = Assemblage)) +
  # BARRA DE FONDO: Riqueza Estimada (Transparente o gris claro)
  #geom_bar(aes(y = Estimator), stat = "identity", fill = "grey90", color = "grey70", width = 0.7) +
  
  # BARRA FRONTAL: Riqueza Observada (Colores por categoría)
  geom_bar(aes(y = Observed, fill = Assemblage), stat = "identity", width = 0.5) +
  
  # BARRAS DE ERROR: Sobre el estimador
  #geom_errorbar(aes(ymin = LCL, ymax = UCL), width = 0.15, size = 0.8, color = "black") +
  
  # ETIQUETA: Número Observado (dentro de la barra de color)
  geom_text(aes(y = Observed, label = round(Observed, 0)), 
            vjust = 1.5, color = "white", fontface = "bold", size = 4.5) +
  
  # ETIQUETA: Número Estimado (arriba de la barra gris)
  #geom_text(aes(y = Estimator, label = paste("Est:", round(Estimator, 0))), 
  #vjust = -1, color = "grey30", fontface = "italic", size = 3.5) +
  
  # Estética y Colores
  scale_fill_manual(values = c("Abierto" = "#f1c40f", "Borde" = "#e67e22", "Interior" = "#27ae60")) +
  theme_minimal() +
  labs(title = "Riqueza de Especies: Observada",
       #subtitle = "Barra de color: Observado | Barra gris: Estimado total esperado",
       x = "Categoría de Hábitat", 
       y = "Número de Especies") +
  theme(legend.position = "none",
        panel.grid.major.x = element_blank(),
        axis.text = element_text(size = 10, color = "black", face = "bold"))

# Mostrar gráfica
print(plot_riqueza_barras)



# ==========================================================
# 3. PATRONES DE ACTIVIDAD (AVES)
# ==========================================================

# 1. Preparación de los datos de tiempo
data_actividad_aves <- obs_data %>%
  filter(!is.na(eventTime)) %>%
  mutate(
    # Extraemos la hora de inicio antes del "/" (ej: "6:25/6:35" -> "6:25")
    hora_limpia = sub("/.*", "", eventTime),
    # Convertimos a formato de tiempo
    time_obj = parse_date_time(hora_limpia, orders = c("HM", "HMS")),
    # Obtenemos la hora en formato decimal (ej: 6:30 -> 6.5)
    hora_decimal = hour(time_obj) + minute(time_obj)/60,
    # Convertimos a radianes para análisis circular (overlap)
    radianes = hora_decimal * 2 * pi / 24
  ) %>%
  filter(!is.na(hora_decimal))

# 2. Resumen de actividad por especie
tab_picos_aves <- data_actividad_aves %>%
  group_by(scientificName) %>%
  summarise(
    Detecciones = n(),
    Hora_Pico_Decimal = median(hora_decimal, na.rm = TRUE)
  ) %>%
  mutate(
    Hora_Pico_HHMM = sprintf("%02d:%02d", floor(Hora_Pico_Decimal), 
                             round((Hora_Pico_Decimal %% 1) * 60))
  ) %>%
  arrange(desc(Detecciones))

print(head(tab_picos_aves))


######################
# Graficas
######################
# Seleccionamos las especies con más de 5 registros para que la densidad sea válida
especies_frecuentes <- tab_picos_aves %>% filter(Detecciones >= 5) %>% pull(scientificName)

plot_actividad_aves <- data_actividad_aves %>%
  filter(scientificName %in% especies_frecuentes) %>%
  ggplot(aes(x = hora_decimal, y = reorder(scientificName, hora_decimal, median), fill = ..x..)) +
  geom_density_ridges_gradient(scale = 1.5, rel_min_height = 0.01) +
  scale_fill_viridis_c(option = "plasma", name = "Hora") +
  scale_x_continuous(limits = c(5, 12), breaks = seq(5, 12, 1)) +
  theme_minimal() +
  labs(
    title = "Patrones de Actividad Vocal - Aves",
    subtitle = "Basado en registros de puntos de conteo (Hora Local)",
    x = "Hora del Día",
    y = "Especie"
  ) +
  theme(legend.position = "none")

print(plot_actividad_aves)

# Gráfica por categoria
# 1. Asegurarnos de que el tiempo esté procesado en el dataset categorizado
data_actividad_cat <- data_biodiv %>%
  filter(!is.na(eventTime)) %>%
  mutate(
    hora_limpia = sub("/.*", "", eventTime),
    time_obj = parse_date_time(hora_limpia, orders = c("HM", "HMS")),
    hora_decimal = hour(time_obj) + minute(time_obj)/60
  ) %>%
  filter(!is.na(hora_decimal))

# 2. Gráfica comparativa por Categoría
plot_actividad_por_cat <- ggplot(data_actividad_cat, aes(x = hora_decimal, y = Categoria, fill = Categoria)) +
  geom_density_ridges(alpha = 0.7, scale = 1.5, color = "white") +
  scale_fill_manual(values = c("Abierto" = "#f1c40f", "Borde" = "#e67e22", "Interior" = "#27ae60")) +
  scale_x_continuous(limits = c(5, 12), breaks = seq(5, 12, 1)) +
  theme_minimal() +
  labs(title = "Distribución Temporal del Esfuerzo de Muestreo por Hábitat",
       subtitle = "Densidad de registros detectados durante la mañana",
       x = "Hora del Día", y = "Categoría de Hábitat") +
  theme(legend.position = "none")

print(plot_actividad_por_cat)


# Ahora por categoria y especie

# Filtrar especies con al menos 3 registros en su categoría para que la curva sea real
data_plot_spp_cat <- data_actividad_cat %>%
  group_by(Categoria, scientificName) %>%
  mutate(n_spp_cat = n()) %>%
  filter(n_spp_cat >= 3) %>% 
  ungroup()

# Graficamos resultados
plot_spp_por_habitat <- function(target_cat, color_base) {
  df_filtered <- data_plot_spp_cat %>% filter(Categoria == target_cat)
  
  ggplot(df_filtered, aes(x = hora_decimal, y = reorder(scientificName, hora_decimal, median))) +
    # 1. Cambiamos a geom_density_ridges normal para usar un solo color
    # Usamos 'fill = color_base' fuera de aes() para que sea fijo
    geom_density_ridges(scale = 1.5, rel_min_height = 0.01, 
                        color = "white", fill = color_base, alpha = 0.8) +
    
    # 2. Eliminamos scale_fill_viridis_c ya que no queremos degradados
    scale_x_continuous(limits = c(5, 12), breaks = seq(5, 12, 1)) +
    theme_minimal() +
    labs(title = paste("Patrones de Actividad:", target_cat),
         subtitle = "Especies con >= 3 registros",
         x = "Hora del Día", y = NULL) +
    theme(legend.position = "none",
          axis.text.y = element_text(size = 8),
          # Opcional: Colorear el título del hábitat para mayor claridad
          plot.title = element_text(color = color_base, face = "bold"))
}

# --- GENERAR LOS TRES GRÁFICOS (Ahora sí respetarán los colores) ---
p_abierto  <- plot_spp_por_habitat("Abierto", "#f1c40f")
p_borde    <- plot_spp_por_habitat("Borde", "#e67e22")
p_interior <- plot_spp_por_habitat("Interior", "#27ae60")

# Visualizar en paralelo
library(patchwork)
p_abierto | p_borde | p_interior

# Guardamos resultados
# Guardar cada uno por separado para que se lean bien los nombres de las especies
ggsave(paste0(path_out, "Actividad_Spp_Abierto.png"), p_abierto, width = 8, height = 10)
ggsave(paste0(path_out, "Actividad_Spp_Borde.png"), p_borde, width = 8, height = 10)
ggsave(paste0(path_out, "Actividad_Spp_Interior.png"), p_interior, width = 8, height = 10)

# ==========================================================
# 4. MATRIZ DE SOLAPAMIENTO Y EXPORTACIÓN
# ==========================================================
# 1. Asegurar que tenemos tiempo y radianes en el dataset categorizado
data_actividad_cat <- data_biodiv %>%
  filter(!is.na(eventTime)) %>%
  mutate(
    # Extraer hora limpia
    hora_limpia = sub("/.*", "", eventTime),
    # Convertir a objeto de tiempo
    time_obj = parse_date_time(hora_limpia, orders = c("HM", "HMS")),
    # Hora decimal (ej. 6.5)
    hora_decimal = hour(time_obj) + minute(time_obj)/60,
    # CÁLCULO DE RADIANES (Lo que faltaba)
    radianes = hora_decimal * 2 * pi / 24
  ) %>%
  filter(!is.na(radianes))

# 2. Ahora sí extraemos los vectores numéricos
rad_abierto  <- as.numeric(data_actividad_cat$radianes[data_actividad_cat$Categoria == "Abierto"])
rad_borde    <- as.numeric(data_actividad_cat$radianes[data_actividad_cat$Categoria == "Borde"])
rad_interior <- as.numeric(data_actividad_cat$radianes[data_actividad_cat$Categoria == "Interior"])

# 3. Verificación de conteo (Debe haber al menos 5 por grupo para que overlapEst no falle)
print(paste("Registros Abierto:", length(rad_abierto)))
print(paste("Registros Borde:", length(rad_borde)))
print(paste("Registros Interior:", length(rad_interior)))

# ==========================================================
# 4. MATRIZ DE SOLAPAMIENTO (OVERLAP) - Versión Robusta
# ==========================================================

# Función para calcular solapamiento seguro
calcular_olap <- function(rad1, rad2, label) {
  if(length(rad1) >= 5 & length(rad2) >= 5) {
    val <- overlapEst(rad1, rad2, type="Dhat1")
    message(paste("Solapamiento", label, ":", round(val, 3)))
    return(val)
  } else {
    message(paste("Datos insuficientes para solapamiento", label))
    return(NA)
  }
}

# Ejecutar comparaciones
olap_ab_int  <- calcular_olap(rad_abierto, rad_interior, "Abierto vs Interior")
olap_bor_int <- calcular_olap(rad_borde, rad_interior, "Borde vs Interior")
olap_ab_bor  <- calcular_olap(rad_abierto, rad_borde, "Abierto vs Borde")

# Configuramos el área de dibujo para ver 2 gráficas (una al lado de la otra)
par(mfrow = c(1, 2)) 

# --- Gráfica 1: Interior vs Abierto ---
if(length(rad_interior) >= 5 & length(rad_abierto) >= 5) {
  overlapPlot(rad_interior, rad_abierto, 
              main = "Solapamiento: Interior vs Abierto",
              col = c("#27ae60", "#f1c40f"), # Verde y Amarillo
              shade = TRUE, olp = list(color = "lightgrey", alpha = 0.5))
  legend("topright", c("Interior", "Abierto"), fill = c("#27ae60", "#f1c40f"), bty = "n")
  text(x = 3, y = 0.05, labels = paste("Delta =", round(olap_ab_int, 2)), font = 2)
}

# --- Gráfica 2: Borde vs Interior ---
if(length(rad_borde) >= 5 & length(rad_interior) >= 5) {
  overlapPlot(rad_borde, rad_interior, 
              main = "Solapamiento: Borde vs Interior",
              col = c("#e67e22", "#27ae60"), # Naranja y Verde
              shade = TRUE, olp = list(color = "lightgrey", alpha = 0.5))
  legend("topright", c("Borde", "Interior"), fill = c("#e67e22", "#27ae60"), bty = "n")
  text(x = 3, y = 0.05, labels = paste("Delta =", round(olap_bor_int, 2)), font = 2)
}

# Restauramos el panel a 1x1
par(mfrow = c(1, 1))


# Solo se genera si matriz_overlap tiene datos
if(exists("plot_overlap_map")) {
  print(plot_overlap_map)
}

# Graficamos la matriz de solapamiento
# Filtramos especies que tengan al menos 5 registros para que la matriz sea útil
spp_validas <- data_actividad_aves %>%
  group_by(scientificName) %>%
  summarise(n = n()) %>%
  filter(n >= 5) %>%
  pull(scientificName)

n_spp <- length(spp_validas)

if(n_spp > 1) {
  matriz_overlap <- matrix(NA, n_spp, n_spp, dimnames = list(spp_validas, spp_validas))
  
  for(i in 1:n_spp) {
    for(j in 1:n_spp) {
      rad_i <- as.numeric(data_actividad_aves$radianes[data_actividad_aves$scientificName == spp_validas[i]])
      rad_j <- as.numeric(data_actividad_aves$radianes[data_actividad_aves$scientificName == spp_validas[j]])
      
      # Usamos Dhat4 si hay muchos datos (>50), Dhat1 si hay pocos
      tipo_delta <- ifelse(length(rad_i) > 50 & length(rad_j) > 50, "Dhat4", "Dhat1")
      matriz_overlap[i,j] <- overlapEst(rad_i, rad_j, type = tipo_delta)
    }
  }
  
  # Heatmap Estético
  matriz_plot <- matriz_overlap
  matriz_plot[upper.tri(matriz_plot)] <- NA # Solo mostramos la mitad inferior
  df_ov_plot <- melt(matriz_plot, na.rm = TRUE)
  
  plot_overlap_map <- ggplot(df_ov_plot, aes(Var1, Var2, fill = value)) +
    geom_tile(color = "white") + 
    scale_fill_gradientn(colors = c("#fff5f0", "#fb6a4a", "#67000d"), 
                         limits = c(0, 1), name = "Índice Delta") +
    theme_minimal() + 
    theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 8),
          axis.text.y = element_text(size = 8)) +
    labs(title = "Solapamiento de Nicho Temporal entre Especies", 
         subtitle = "Valores cercanos a 1 indican alta sincronía en actividad",
         x = NULL, y = NULL)
} else {
  message("No hay suficientes especies con registros >= 5 para generar la matriz.")
  matriz_overlap <- matrix("Datos Insuficientes")
  plot_overlap_map <- ggplot() + labs(title = "Matriz no generada por falta de datos")
}

# ==========================================================
# 5. EXPORTACIÓN FINAL
# ==========================================================

# 5.1 Excel Consolidado
wb <- createWorkbook()
# Asegúrate de usar los nombres de tabla que definimos en los pasos anteriores
addWorksheet(wb, "Diversidad_Asintotica"); writeData(wb, "Diversidad_Asintotica", cifras_asyest)
addWorksheet(wb, "Picos_Actividad"); writeData(wb, "Picos_Actividad", tab_picos_aves) # Tabla de especies y sus horas
addWorksheet(wb, "Matriz_Solapamiento"); writeData(wb, "Matriz_Solapamiento", matriz_overlap, rowNames = TRUE)

saveWorkbook(wb, paste0(path_out, "Resultados_Biodiversidad_Actividad.xlsx"), overwrite = TRUE)

# 5.2 Guardar Gráficos con alta resolución
# Riqueza Observada vs Estimada (La de barras que hicimos)
ggsave(paste0(path_out, "01_Riqueza_Hibrida_q0.png"), plot_riqueza_barras, width = 8, height = 6, dpi = 300)

# Rarefacción Global (La curva suave)
ggsave(paste0(path_out, "02_Rarefaccion_Suave.png"), plot_rarefaccion_q0, width = 8, height = 6, dpi = 300)

# Actividad por Categoría (RidgePlot de especies)
# Si usaste patchwork para unir p_abierto, p_borde y p_interior:
p_final_actividad <- (p_abierto | p_borde | p_interior)
ggsave(paste0(path_out, "03_Actividad_por_Habitat.png"), p_final_actividad, width = 15, height = 10, dpi = 300)

# Heatmap de Solapamiento
ggsave(paste0(path_out, "04_Heatmap_Overlap.png"), plot_overlap_map, width = 10, height = 8, dpi = 300)

message("--- PROCESO FINALIZADO CON ÉXITO ---")
message("Archivos guardados en: ", path_out)