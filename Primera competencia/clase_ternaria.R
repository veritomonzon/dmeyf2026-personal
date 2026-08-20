# ============================================================
# CARGA DE LIBRERIAS Y CARGA DE BASE
# ============================================================

library(haven)
library(descr)
library(dplyr)
library(data.table)

df <- read.csv("Primera competencia/competencia_01_crudo.csv")
View(df)

# ============================================================
# AED
# ============================================================

names(df)
str(df)
dim(df)

head(df[, c("numero_de_cliente", "foto_mes")])
sort(unique(df$foto_mes))

colSums(
  is.na(df[, c("numero_de_cliente", "foto_mes")])
)

sum(
  duplicated(df[, c("numero_de_cliente", "foto_mes")])
)

length(unique(df$numero_de_cliente))

table(
  tapply(df$foto_mes, df$numero_de_cliente, min)
)

table(
  tapply(df$foto_mes, df$numero_de_cliente, max)
)

range(df$foto_mes %/% 100)
range(df$foto_mes %% 100)

all(
  (df$foto_mes %% 100) %in% 1:12
)

# TRAYECTORIA TEMPORAL POR CLIENTE
meses_por_cliente <- split(
  df$foto_mes,
  df$numero_de_cliente
)

trayectoria_por_cliente <- data.frame(
  numero_de_cliente = type.convert(
    names(meses_por_cliente),
    as.is = TRUE
  ),
  trayectoria = vapply(
    meses_por_cliente,
    function(x) {
      paste(sort(unique(x)), collapse = " - ")
    },
    character(1)
  ),
  intermitente = vapply(
    meses_por_cliente,
    function(x) {
      x <- sort(unique(x))
      mes_secuencial <- (x %/% 100) * 12 + (x %% 100)

      any(diff(mes_secuencial) > 1)
    },
    logical(1)
  ),
  row.names = NULL
)

rm(meses_por_cliente)

dim(trayectoria_por_cliente)
head(trayectoria_por_cliente, 20)

sort(
  table(trayectoria_por_cliente$trayectoria),
  decreasing = TRUE
)

table(
  trayectoria_por_cliente$intermitente,
  useNA = "ifany"
)

View(
  trayectoria_por_cliente[
    trayectoria_por_cliente$intermitente,
  ]
)

# SEPARACION DE FOTO_MES

df$foto_anio <- df$foto_mes %/% 100
df$foto_num_mes <- df$foto_mes %% 100

unique(
  df[, c("foto_mes", "foto_anio", "foto_num_mes")]
)

# ============================================================
# CONSTRUCCION DE CLASE_TERNARIA
# ============================================================

# Criterio de asignacion:
# ¿El mes tiene dos meses futuros?
# ├── No  → NA
# └── Sí
#     ├── ¿No aparece en mes +1? → BAJA+1
#     └── Aparece en mes +1
#         ├── ¿No aparece en mes +2? → BAJA+2
#         └── Aparece en mes +2 → CONTINUA
#
# Nota: si el cliente reaparece despues de un hueco, eso NO cambia la
# clase ya asignada en los meses previos 

clave <- df$numero_de_cliente * 100 + df$foto_num_mes

mes_1 <- (clave + 1) %in% clave
mes_2 <- (clave + 2) %in% clave

df$clase_ternaria <- ifelse(
  df$foto_num_mes > max(df$foto_num_mes) - 2,
  NA_character_,
  ifelse(
    !mes_1,
    "BAJA+1",
    ifelse(!mes_2, "BAJA+2", "CONTINUA")
  )
)

table(
  df$foto_mes,
  df$clase_ternaria,
  useNA = "ifany"
)

table(
  df$foto_mes,
  is.na(df$clase_ternaria)
)

rm(clave, mes_1, mes_2)
df$foto_anio <- NULL
df$foto_num_mes <- NULL

View(df)

# ============================================================
# GUARDADO DEL RESULTADO
# ============================================================

saveRDS(df, "Primera competencia/competencia_01_clase_ternaria.rds")
