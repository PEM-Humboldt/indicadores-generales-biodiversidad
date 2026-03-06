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