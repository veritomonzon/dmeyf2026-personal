# ============================================================
# CARGA DE LIBRERIAS Y CARGA DE BASE
# ============================================================

library(haven)
library(descr)
library(dplyr)
library(data.table)

# ============================================================
# LOG
# ============================================================

while (sink.number() > 0) sink()
closeAllConnections()

dir.create("Primera competencia/Video Miranda Wintour/logs", showWarnings = FALSE)

log_con <- file("Primera competencia/Video Miranda Wintour/logs/analisis_clustering_clientes.md", open = "wt")
sink(log_con, append = TRUE, split = TRUE)

# ============================================================
# CARGA DE BASE DE DATOS
# ============================================================

df <- readRDS("Primera competencia/competencia_01_clase_ternaria.rds")
View(df)

# ============================================================
# AED
# ============================================================

print(table(df$clase_ternaria, useNA = "ifany"))

print(sum(df$clase_ternaria == "BAJA+2", na.rm = TRUE))
print(sum(df$clase_ternaria %in% c("BAJA+1", "BAJA+2"), na.rm = TRUE))

# ============================================================
# CIERRE DEL LOG
# ============================================================

sink(type = "message")  # segunda vez, para desapilar la capa extra
sink()
close(log_con)
