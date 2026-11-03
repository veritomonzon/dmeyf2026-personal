# ============================================================
# CARGA DE LIBRERIAS Y CARGA DE BASE
# ============================================================

library(haven)
library(descr)
library(dplyr)
library(data.table)
library(naniar)
library(visdat)
library(ggplot2)
library(tidyr)
library(cluster)
library(lightgbm)

# ============================================================
# LOG
# ============================================================

while (sink.number() > 0) sink()
closeAllConnections()

dir.create("Primera competencia/Video Miranda Wintour/logs", showWarnings = FALSE)
dir.create("Primera competencia/Video Miranda Wintour/plots", showWarnings = FALSE)

log_con <- file("Primera competencia/Video Miranda Wintour/logs/analisis_clustering_clientes.md", open = "wt")
sink(log_con, append = TRUE, split = TRUE)

# ============================================================
# CARGA DE BASE DE DATOS
# ============================================================

df <- readRDS("Primera competencia/competencia_01_clase_ternaria.rds")
View(df)

# ============================================================
# FILTRADO DE POBLACION: clientes BAJA+2 (accionables) + su historia completa
# ============================================================

clientes_baja2 <- unique(df$numero_de_cliente[df$clase_ternaria == "BAJA+2" & !is.na(df$clase_ternaria)])
print(length(clientes_baja2))

df_poblacion <- df[df$numero_de_cliente %in% clientes_baja2, ]
print(table(df_poblacion$foto_mes))

# chequeo: los clientes con fila en foto_mes 202108, tienen trayectoria con huecos (intermitentes)?
clientes_202108 <- df_poblacion$numero_de_cliente[df_poblacion$foto_mes == 202108]

trayectoria_baja2 <- df_poblacion %>%
  group_by(numero_de_cliente) %>%
  summarise(
    trayectoria = paste(sort(unique(foto_mes)), collapse = " - "),
    intermitente = {
      meses <- sort(unique(foto_mes))
      mes_secuencial <- (meses %/% 100) * 12 + (meses %% 100)
      any(diff(mes_secuencial) > 1)
    }
  )
print(trayectoria_baja2[trayectoria_baja2$numero_de_cliente %in% clientes_202108, ])

# confirmado: los 17 son intermitentes -> se excluyen de toda la poblacion (trayectoria no real)
df_poblacion <- df_poblacion[!df_poblacion$numero_de_cliente %in% clientes_202108, ]
print(length(unique(df_poblacion$numero_de_cliente)))
print(table(df_poblacion$foto_mes))

# ============================================================
# ETL
# ============================================================

# tipificacion de variables categoricas
vars_categoricas <- c(
  "active_quarter", "cliente_vip", "internet", "cdescubierto_preacordado",
  "tcuentas", "ccaja_seguridad", "tcallcenter", "thomebanking", "tmobile_app",
  "Master_delinquency", "Master_status", "Visa_delinquency", "Visa_status"
)
df_poblacion[vars_categoricas] <- lapply(df_poblacion[vars_categoricas], as.factor)
print(str(df_poblacion[vars_categoricas]))

# variables numericas
vars_numericas <- df_poblacion %>%
  select(where(is.numeric)) %>%
  select(-numero_de_cliente, -foto_mes)
print(summary(vars_numericas))

# revision de valores atipicos / posiblemente imposibles, detectados en el summary() anterior:
# - Visa_Fvencimiento: minimo de -2.914.178 dias (diccionario: "dias para el vencimiento
#   del plastico"), orden de magnitud muy superior al resto de las variables en dias.
# - Master_Fvencimiento: rango -2251 a 6484 dias.
# - mcaja_ahorro: minimo de -5999 pesos (saldo negativo en caja de ahorro).
# - ccaja_ahorro: minimo de 2, nunca 0 ni 1 (posible caracteristica del Paquete Premium:
#   caja en pesos + caja en dolares, ver mcaja_ahorro_dolares).
# - mcuenta_corriente: minimo de -1.789.913,3 pesos (ya revisado en sesion anterior, no se
#   considera un error, queda como esta).
# - Master_msaldototal / Visa_msaldototal: minimos muy negativos.
# - mcomisiones_mantenimiento: minimo de -11.191 pesos.
vars_revisar <- c(
  "Visa_Fvencimiento", "Master_Fvencimiento", "mcaja_ahorro",
  "ccaja_ahorro", "mcuenta_corriente", "Master_msaldototal",
  "Visa_msaldototal", "mcomisiones_mantenimiento"
)
for (v in vars_revisar) {
  cat("\n---", v, "---\n")
  print(quantile(df_poblacion[[v]], probs = c(0, .01, .05, .25, .5, .75, .95, .99, 1), na.rm = TRUE))
}

# inspeccion del cliente con valor atipico en Visa_Fvencimiento
idx_atipico <- which(df_poblacion$Visa_Fvencimiento == min(df_poblacion$Visa_Fvencimiento, na.rm = TRUE))
cliente_atipico <- df_poblacion$numero_de_cliente[idx_atipico]
print(glimpse(df_poblacion[idx_atipico, ]))
print(df_poblacion[df_poblacion$numero_de_cliente %in% cliente_atipico, ]) # todas las filas de esos clientes

# cuantos valores imposibles hay en Fvencimiento (< -3650 dias, mas de 10 anios), son todos iguales?
for (v in c("Visa_Fvencimiento", "Master_Fvencimiento")) {
  cat("\n---", v, "---\n")
  valores_raros <- df_poblacion[[v]][df_poblacion[[v]] < -3650 & !is.na(df_poblacion[[v]])]
  print(table(valores_raros))
}

# los valores raros de Visa_Fvencimiento son el mismo grupo de clientes en meses consecutivos
# (confirmado: mismo cliente, valor sube ~30 cada mes -> bug de fecha de vencimiento fija/rota)
filas_raras <- df_poblacion[!is.na(df_poblacion$Visa_Fvencimiento) & df_poblacion$Visa_Fvencimiento < -3650, ]
print(filas_raras[order(filas_raras$numero_de_cliente, filas_raras$foto_mes), c("numero_de_cliente", "foto_mes", "Visa_Fvencimiento")])

# correccion: no se puede reconstruir el dato real desde otra variable (chequeado contra el
# diccionario de datos oficial) -> se pasa a NA
df_poblacion$Visa_Fvencimiento[df_poblacion$Visa_Fvencimiento < -3650 & !is.na(df_poblacion$Visa_Fvencimiento)] <- NA
print(sum(is.na(df_poblacion$Visa_Fvencimiento)))

# mismo chequeo para Master_Fvencimiento, del lado positivo (a futuro, > 3650 dias)
valores_raros_master <- df_poblacion$Master_Fvencimiento[df_poblacion$Master_Fvencimiento > 3650 & !is.na(df_poblacion$Master_Fvencimiento)]
print(table(valores_raros_master))

filas_raras_master <- df_poblacion[!is.na(df_poblacion$Master_Fvencimiento) & df_poblacion$Master_Fvencimiento > 3650, ]
print(filas_raras_master[order(filas_raras_master$numero_de_cliente, filas_raras_master$foto_mes), c("numero_de_cliente", "foto_mes", "Master_Fvencimiento")])

# mismo bug confirmado (cliente 23711340 en 3 meses seguidos) + 1 caso aislado -> los 4 a NA
df_poblacion$Master_Fvencimiento[df_poblacion$Master_Fvencimiento > 3650 & !is.na(df_poblacion$Master_Fvencimiento)] <- NA
print(sum(is.na(df_poblacion$Master_Fvencimiento)))

# resumen de valores negativos: cuantas filas y que tan negativas
resumen_negativos <- function(variable) {
  x <- df_poblacion[[variable]]
  negativos <- x[!is.na(x) & x < 0]
  cat("\n---", variable, ": filas negativas ---\n")
  print(length(negativos))
  print(round(length(negativos) / sum(!is.na(x)) * 100, 2))
  print(summary(negativos))
  invisible(negativos)
}

negativos_caja_ahorro <- resumen_negativos("mcaja_ahorro")
# 2 filas (0.01%), caso aislado sin patron -> se deja como esta (posible comision que supero el saldo)

negativos_comisiones <- resumen_negativos("mcomisiones_mantenimiento")
# 290 filas (2.04%): se chequea si son multiplos de la comision tipica (1774.04, reversas exactas)
cociente <- negativos_comisiones / 1774.04
print(table(round(cociente, 1)))
# patron parcial (36% son ~ -1x la comision tipica), el resto disperso -> valores reales y
# variados (devoluciones de distinto monto), no un bug de carga -> se deja como esta

# Master_msaldototal / Visa_msaldototal: filas muy por debajo del percentil 1 (10x), y quienes son
for (v in c("Master_msaldototal", "Visa_msaldototal")) {
  cat("\n---", v, "---\n")
  p1 <- quantile(df_poblacion[[v]], probs = .01, na.rm = TRUE)
  extremos <- df_poblacion[!is.na(df_poblacion[[v]]) & df_poblacion[[v]] < p1 * 10, ]
  print(extremos[order(extremos$numero_de_cliente, extremos$foto_mes), c("numero_de_cliente", "foto_mes", v)])
}

# cliente 27418862, foto_mes 202107: minimo absoluto en Master Y Visa el mismo mes -> inspeccion
print(glimpse(df_poblacion[df_poblacion$numero_de_cliente == 27418862 & df_poblacion$foto_mes == 202107, ]))
# fila con contradicciones (ctarjeta_master/visa = 0 pero con status y saldo cargados;
# transacciones = 0 pero con consumos > 0), justo en el ultimo mes antes de irse (BAJA+1)
# -> parece una fila corrupta puntual, no un valor real

# confirmado que no es un patron general: la mediana de saldo en status=6 (en proceso de cierre)
# es normal (0 en Master, 1145 en Visa); el extremo es solo este cliente
print(summary(df_poblacion$Master_msaldototal[df_poblacion$Master_status == "6"]))
print(summary(df_poblacion$Visa_msaldototal[df_poblacion$Visa_status == "6"]))

# correccion: solo esta fila puntual -> NA (no se puede reconstruir el valor real)
fila_corrupta <- df_poblacion$numero_de_cliente == 27418862 & df_poblacion$foto_mes == 202107
df_poblacion$Master_msaldototal[fila_corrupta] <- NA
df_poblacion$Visa_msaldototal[fila_corrupta] <- NA
print(sum(is.na(df_poblacion$Master_msaldototal)))
print(sum(is.na(df_poblacion$Visa_msaldototal)))

# deteccion y correccion: variable con 100% de ceros en un mes puntual (bug de carga, Clase 06:
# el proceso de carga no corrio para esa variable ese mes y quedo el default en 0 en vez de NA)
detectar_todo_cero <- function(variable, mes) {
  x <- df_poblacion[[variable]][df_poblacion$foto_mes == mes]
  x_valido <- x[!is.na(x)]
  length(x_valido) > 0 && all(x_valido == 0)
}
combos <- expand.grid(
  variable = names(vars_numericas),
  foto_mes = sort(unique(df_poblacion$foto_mes)),
  stringsAsFactors = FALSE
)
combos$todo_cero <- mapply(detectar_todo_cero, combos$variable, combos$foto_mes)
vars_mes_sospechosas <- combos[combos$todo_cero, ]
print(vars_mes_sospechosas)

for (i in seq_len(nrow(vars_mes_sospechosas))) {
  v <- vars_mes_sospechosas$variable[i]
  m <- vars_mes_sospechosas$foto_mes[i]
  fila <- df_poblacion$foto_mes == m & !is.na(df_poblacion[[v]]) & df_poblacion[[v]] == 0
  df_poblacion[[v]][fila] <- NA
}

# Master_madelantodolares / Visa_madelantodolares quedaron 100% NA tras la correccion -> se sacan
df_poblacion <- df_poblacion %>% select(-Master_madelantodolares, -Visa_madelantodolares)
View(df_poblacion)

# consumo/pago/adelanto de tarjeta: un NA ahi puede ser "no tiene la tarjeta" (NA real) o "tiene
# la tarjeta pero no la uso ese mes" (0 real, mal cargado como NA) -> paso a paso completo de
# la verificacion documentado en PLAN.md, seccion "Decisiones de limpieza aplicadas"
vars_a_chequear <- c(
  "Master_mconsumospesos", "Master_madelantopesos", "Master_cadelantosefectivo",
  "Visa_mconsumospesos", "Visa_madelantopesos", "Visa_cadelantosefectivo"
)
for (v in vars_a_chequear) {
  ancla <- if (startsWith(v, "Master")) "Master_msaldototal" else "Visa_msaldototal"
  tabla <- table(sin_tarjeta = is.na(df_poblacion[[ancla]]), na_variable = is.na(df_poblacion[[v]]))
  cat("\n---", v, "(ancla:", ancla, ") ---\n")
  print(tabla)
}

# descartada la explicacion de estado de cuenta (el NA extra no se concentra en status de cierre)
cruzar_na_status <- function(variable, ancla, status_col) {
  con_tarjeta <- !is.na(df_poblacion[[ancla]])
  tabla <- table(
    status = df_poblacion[[status_col]][con_tarjeta],
    na_variable = is.na(df_poblacion[[variable]][con_tarjeta])
  )
  cat("\n---", variable, "x", status_col, "(% NA por status) ---\n")
  print(round(prop.table(tabla, margin = 1) * 100, 1))
}
cruzar_na_status("Master_mconsumospesos", "Master_msaldototal", "Master_status")
cruzar_na_status("Master_madelantopesos", "Master_msaldototal", "Master_status")
cruzar_na_status("Visa_mconsumospesos", "Visa_msaldototal", "Visa_status")
cruzar_na_status("Visa_madelantopesos", "Visa_msaldototal", "Visa_status")

# confirmado con 0 transacciones ese mes -> es "sin actividad", no dato perdido
verificar_na_vs_transacciones <- function(variable, ancla, trx_col) {
  con_tarjeta <- !is.na(df_poblacion[[ancla]])
  na_var <- is.na(df_poblacion[[variable]]) & con_tarjeta
  cat("\n---", variable, "vs", trx_col, "---\n")
  print(table(cero_transacciones = df_poblacion[[trx_col]][na_var] == 0))
}
verificar_na_vs_transacciones("Master_mconsumospesos", "Master_msaldototal", "ctarjeta_master_transacciones")
verificar_na_vs_transacciones("Visa_mconsumospesos", "Visa_msaldototal", "ctarjeta_visa_transacciones")
verificar_na_vs_transacciones("Master_madelantopesos", "Master_msaldototal", "ctarjeta_master_transacciones")
verificar_na_vs_transacciones("Visa_madelantopesos", "Visa_msaldototal", "ctarjeta_visa_transacciones")

# correccion: consumo/pago (con tarjeta, 0 transacciones) -> 0
# Visa tiene 1 excepcion (transacciones > 0, dato realmente faltante) que se deja en NA
vars_consumo_master <- c("Master_mconsumospesos", "Master_mconsumosdolares", "Master_mpagospesos", "Master_mpagosdolares")
vars_consumo_visa <- c("Visa_mconsumospesos", "Visa_mconsumosdolares", "Visa_mpagospesos", "Visa_mpagosdolares")

con_tarjeta_master <- !is.na(df_poblacion$Master_msaldototal)
for (v in vars_consumo_master) df_poblacion[[v]][con_tarjeta_master & is.na(df_poblacion[[v]])] <- 0

con_tarjeta_visa <- !is.na(df_poblacion$Visa_msaldototal)
fila_excepcion <- con_tarjeta_visa & is.na(df_poblacion$Visa_mconsumospesos) & df_poblacion$ctarjeta_visa_transacciones > 0
for (v in vars_consumo_visa) df_poblacion[[v]][con_tarjeta_visa & is.na(df_poblacion[[v]]) & !fila_excepcion] <- 0

print(colSums(is.na(df_poblacion[c(vars_consumo_master, vars_consumo_visa)])))

# correccion parcial: adelantos (con tarjeta, 0 transacciones totales) -> 0
vars_adelanto_master <- c("Master_madelantopesos", "Master_cadelantosefectivo")
vars_adelanto_visa <- c("Visa_madelantopesos", "Visa_cadelantosefectivo")

cero_trx_master <- con_tarjeta_master & is.na(df_poblacion$Master_madelantopesos) & df_poblacion$ctarjeta_master_transacciones == 0
for (v in vars_adelanto_master) df_poblacion[[v]][cero_trx_master] <- 0

cero_trx_visa <- con_tarjeta_visa & is.na(df_poblacion$Visa_madelantopesos) & df_poblacion$ctarjeta_visa_transacciones == 0
for (v in vars_adelanto_visa) df_poblacion[[v]][cero_trx_visa] <- 0

# grupo ambiguo restante (con transacciones > 0, aun asi NA en adelantos): tiene consumo real?
ambiguo_master <- con_tarjeta_master & is.na(df_poblacion$Master_madelantopesos) & df_poblacion$ctarjeta_master_transacciones > 0
ambiguo_visa <- con_tarjeta_visa & is.na(df_poblacion$Visa_madelantopesos) & df_poblacion$ctarjeta_visa_transacciones > 0

consumo_master_ambiguo <- df_poblacion$Master_mconsumospesos[ambiguo_master] + df_poblacion$Master_mconsumosdolares[ambiguo_master]
print(table(consumo_cero = consumo_master_ambiguo == 0, useNA = "ifany"))

consumo_visa_ambiguo <- df_poblacion$Visa_mconsumospesos[ambiguo_visa] + df_poblacion$Visa_mconsumosdolares[ambiguo_visa]
print(table(consumo_cero = consumo_visa_ambiguo == 0, useNA = "ifany"))

# remanente sin consumo tampoco (transacciones > 0, consumo y adelanto en 0): tiene debitos
# automaticos o consumo por la via alternativa mtarjeta_*_consumo? (confirmado: es consumo real
# que no quedo en la primera columna, no adelanto ni debito automatico)
raro_master <- ambiguo_master & !is.na(df_poblacion$Master_mconsumospesos) &
  (df_poblacion$Master_mconsumospesos + df_poblacion$Master_mconsumosdolares == 0)
raro_visa <- ambiguo_visa & !is.na(df_poblacion$Visa_mconsumospesos) &
  (df_poblacion$Visa_mconsumospesos + df_poblacion$Visa_mconsumosdolares == 0)

print(summary(df_poblacion$mtarjeta_master_consumo[raro_master]))
print(summary(df_poblacion$mttarjeta_master_debitos_automaticos[raro_master]))
print(summary(df_poblacion$mtarjeta_visa_consumo[raro_visa]))
print(summary(df_poblacion$mttarjeta_visa_debitos_automaticos[raro_visa]))

# correccion final: todo el grupo ambiguo -> 0 (excepto la fila excepcion de Visa)
for (v in vars_adelanto_master) df_poblacion[[v]][ambiguo_master] <- 0
for (v in vars_adelanto_visa) df_poblacion[[v]][ambiguo_visa & !is.na(df_poblacion$Visa_mconsumospesos)] <- 0

print(colSums(is.na(df_poblacion[c(vars_consumo_master, vars_consumo_visa, vars_adelanto_master, vars_adelanto_visa)])))

# ============================================================
# AED
# ============================================================

print(dim(df_poblacion))
print(str(df_poblacion, list.len = ncol(df_poblacion)))

# evaluacion de datos faltantes: estado final, despues de todas las correcciones de arriba
# (a proposito al final del ETL, no antes: es la foto del dataset ya limpio, no una version duplicada)
print(n_miss(df_poblacion))
print(prop_miss(df_poblacion))
print(sum(complete.cases(df_poblacion)))
print(miss_var_summary(df_poblacion), n = 156)

g1 <- vis_miss(df_poblacion, warn_large_data = FALSE)
print(g1)
ggsave("Primera competencia/Video Miranda Wintour/plots/vis_miss.png", g1, width = 14, height = 10)

g2 <- gg_miss_var(df_poblacion, show_pct = TRUE)
print(g2)
ggsave("Primera competencia/Video Miranda Wintour/plots/gg_miss_var.png", g2, width = 10, height = 20)

g3 <- vis_dat(df_poblacion, sort_type = TRUE, warn_large_data = FALSE)
print(g3)
ggsave("Primera competencia/Video Miranda Wintour/plots/vis_dat.png", g3, width = 14, height = 10)

# distribuciones univariadas: CONTINUA vs BAJA, variables de mayor importancia
vars_importancia <- c(
  "ctrx_quarter", "mpasivos_margen", "mcuentas_saldo", "mcaja_ahorro",
  "cpayroll_trx", "mtarjeta_visa_consumo", "Visa_msaldopesos",
  "mprestamos_personales", "mpayroll", "mcuenta_corriente"
)
df_dist <- df_poblacion %>%
  filter(!is.na(clase_ternaria)) %>%
  mutate(grupo = ifelse(clase_ternaria == "CONTINUA", "CONTINUA", "BAJA")) %>%
  select(grupo, all_of(vars_importancia)) %>%
  pivot_longer(-grupo, names_to = "variable", values_to = "valor")
print(table(df_dist$grupo))

g4 <- ggplot(df_dist, aes(x = grupo, y = valor)) +
  geom_boxplot(outlier.size = 0.5) +
  facet_wrap(~variable, scales = "free_y") +
  labs(title = "Distribucion de variables de mayor importancia: CONTINUA vs BAJA")
print(g4)
ggsave("Primera competencia/Video Miranda Wintour/plots/distribuciones_continua_vs_baja.png", g4, width = 14, height = 10)

# CORRELACION ENTRE VARIABLES NUMERICAS (para detectar redundancia antes del ranking)

vars_numericas_actuales <- intersect(names(vars_numericas), names(df_poblacion))

matriz_cor <- cor(df_poblacion[, vars_numericas_actuales], use = "pairwise.complete.obs")

pares_altos <- which(abs(matriz_cor) > 0.9 & upper.tri(matriz_cor), arr.ind = TRUE)

pares_altos_df <- data.frame(
  var1 = rownames(matriz_cor)[pares_altos[, 1]],
  var2 = colnames(matriz_cor)[pares_altos[, 2]],
  correlacion = matriz_cor[pares_altos]
)
pares_altos_df <- pares_altos_df[order(-abs(pares_altos_df$correlacion)), ]

print(pares_altos_df)

umbral <- 0.7
pares_umbral <- which(abs(matriz_cor) > umbral & upper.tri(matriz_cor), arr.ind = TRUE)
pares_umbral_df <- data.frame(
  var1 = rownames(matriz_cor)[pares_umbral[, 1]],
  var2 = colnames(matriz_cor)[pares_umbral[, 2]],
  correlacion = matriz_cor[pares_umbral]
)
pares_umbral_df <- pares_umbral_df[order(-abs(pares_umbral_df$correlacion)), ]
print(nrow(pares_umbral_df))
print(pares_umbral_df)

prop_cero <- sapply(df_poblacion[, vars_numericas_actuales], function(x) mean(x == 0, na.rm = TRUE))
prop_cero_ordenado <- sort(prop_cero, decreasing = TRUE)
print(prop_cero_ordenado)

# ============================================================
# RANKING MENSUAL (percentil dentro de cada foto_mes, separando signo)
# ============================================================

# set de variables para el ranking: top-10 de importancia + variables
# adicionales elegidas tras el chequeo de correlacion y de ceros (ver PLAN.md)
vars_ranking <- c(
  vars_importancia, # las 10 de mayor importancia
  "mrentabilidad_annual", "mactivos_margen",
  "cliente_antiguedad", "cliente_edad", "cproductos",
  "mcuenta_debitos_automaticos",
  "mtransferencias_emitidas", "mtransferencias_recibidas",
  "matm",
  "mtarjeta_master_consumo", "Master_msaldototal",
  "mcomisiones",
  "chomebanking_transacciones", "cmobile_app_trx",
  "ccallcenter_transacciones"
)
print(length(vars_ranking))
print(vars_ranking)

# funcion: rankea una variable dentro de un mes, tratando valores positivos y
# negativos por separado (y dejando 0 en 0) - asi el signo (deuda vs saldo a
# favor) no se mezcla en un mismo percentil (tip Clase 06)
rankear_por_signo <- function(x) {
  out <- rep(NA_real_, length(x))
  pos <- !is.na(x) & x > 0
  neg <- !is.na(x) & x < 0
  cero <- !is.na(x) & x == 0
  out[pos] <- rank(x[pos]) / sum(pos) # percentil entre 0 y 1
  out[neg] <- -rank(-x[neg]) / sum(neg) # percentil entre -1 y 0
  out[cero] <- 0
  out
}

# aplicacion mes a mes: crea columnas nuevas con sufijo "_rank", sin tocar
# las columnas originales (esas se usan despues para nombrar/cuantificar
# los perfiles con valores crudos)
df_poblacion <- df_poblacion %>%
  group_by(foto_mes) %>%
  mutate(across(all_of(vars_ranking), rankear_por_signo, .names = "{.col}_rank")) %>%
  ungroup()

print(summary(df_poblacion %>% select(ends_with("_rank"))))

# ============================================================
# EVOLUCION TEMPORAL: trayectoria de variables clave, CONTINUA vs BAJA
# (en posicion relativa / percentil mensual, no en valores crudos, para que
# no se mezcle el efecto de "en que mes calendario le toco a cada cliente")
# ============================================================

# eje comun: meses antes del ultimo mes observado por cliente (0 = ultimo mes,
# 1 = un mes antes, etc.) - asi se pueden comparar clientes con distintas
# ventanas de meses
df_evolucion <- df_poblacion %>%
  mutate(mes_secuencial = (foto_mes %/% 100) * 12 + (foto_mes %% 100)) %>%
  group_by(numero_de_cliente) %>%
  mutate(meses_para_fin = max(mes_secuencial) - mes_secuencial) %>%
  ungroup()

print(table(df_evolucion$meses_para_fin))

# variables a graficar: las 10 de mayor importancia, en su version "_rank"
# (posicion relativa dentro de cada mes, ya calculada en el bloque de ranking)
vars_importancia_rank <- paste0(vars_importancia, "_rank")

# los perfiles van a salir del clustering, no de un split armado a mano aca
df_evol_long <- df_evolucion %>%
  select(meses_para_fin, all_of(vars_importancia_rank)) %>%
  pivot_longer(-meses_para_fin, names_to = "variable", values_to = "valor") %>%
  mutate(variable = sub("_rank$", "", variable))

resumen_evol <- df_evol_long %>%
  group_by(variable, meses_para_fin) %>%
  summarise(
    mediana = median(valor, na.rm = TRUE),
    q25 = quantile(valor, 0.25, na.rm = TRUE),
    q75 = quantile(valor, 0.75, na.rm = TRUE),
    n = sum(!is.na(valor)),
    .groups = "drop"
  )
print(resumen_evol, n = 200)

# grafico: linea de mediana + banda de IQR, una faceta por variable, toda
# la poblacion junta
g5 <- ggplot(resumen_evol, aes(x = meses_para_fin, y = mediana)) +
  geom_ribbon(aes(ymin = q25, ymax = q75), alpha = 0.2) +
  geom_line() +
  facet_wrap(~variable, scales = "free_y") +
  scale_x_reverse() +
  labs(
    title = "Evolucion temporal (posicion relativa mensual) de variables clave - poblacion BAJA+2",
    x = "Meses antes del ultimo mes observado",
    y = "Posicion relativa dentro del mes (mediana, banda = rango intercuartil)"
  )
print(g5)
ggsave("Primera competencia/Video Miranda Wintour/plots/evolucion_temporal.png", g5, width = 14, height = 10)

# ============================================================
# SUPERVISED CLUSTERING CON SHAP VALUES (Metodología Aidan Cooper 2026)
# ============================================================

cat("\n--- Entrenando modelo supervisado para extraer drivers (SHAP) ---\n")

# 1. Preparar muestra de entrenamiento rápida: BAJA+2 vs CONTINUA (meses 202103 a 202105)
set.seed(42)
df_train_sub <- df %>%
  filter(clase_ternaria %in% c("BAJA+2", "CONTINUA"), foto_mes %in% c(202103, 202104, 202105))

bajas_sub <- df_train_sub %>% filter(clase_ternaria == "BAJA+2")
continua_sub <- df_train_sub %>%
  filter(clase_ternaria == "CONTINUA") %>%
  sample_n(nrow(bajas_sub) * 5)
muestra_lgb <- bind_rows(bajas_sub, continua_sub)

y_lgb <- ifelse(muestra_lgb$clase_ternaria == "BAJA+2", 1, 0)
X_lgb <- as.matrix(muestra_lgb[, vars_ranking])

dtrain <- lgb.Dataset(X_lgb, label = y_lgb)
params <- list(
  objective = "binary",
  learning_rate = 0.05,
  num_leaves = 31,
  min_data_in_leaf = 50,
  verbose = -1
)
modelo_lgb <- lgb.train(params, dtrain, nrounds = 100, verbose = -1)

# 2. Resumen por cliente BAJA+2 y cálculo de matriz SHAP nativa
vars_rank <- paste0(vars_ranking, "_rank")

df_cliente_prom <- df_poblacion %>%
  group_by(numero_de_cliente) %>%
  summarise(
    across(all_of(vars_ranking), ~ mean(.x, na.rm = TRUE)),
    across(all_of(vars_rank), ~ mean(.x, na.rm = TRUE)),
    .groups = "drop"
  )

X_clientes <- as.matrix(df_cliente_prom[, vars_ranking])

# predict type = "contrib" devuelve directamente los SHAP values en LightGBM
shap_raw <- predict(modelo_lgb, X_clientes, type = "contrib")

# Excluimos la última columna (bias/base value) para quedarnos con los drivers puros
shap_matrix <- shap_raw[, 1:length(vars_ranking)]
colnames(shap_matrix) <- vars_ranking

cat("Dimensiones de la matriz SHAP:", dim(shap_matrix), "\n")

# 3. Clustering sobre los SHAP Values (espacio de drivers de fuga)
# Al estar en escala log-odds homogénea, la distancia euclídea es óptima y no sufre por escalas
dist_shap <- dist(shap_matrix)

# Barrido de Silhouette sobre SHAP
resumen_pam_shap <- do.call(rbind, lapply(2:6, function(k) {
  res <- pam(dist_shap, k = k, diss = TRUE)
  data.frame(k = k, silhouette = res$silinfo$avg.width)
}))
print(resumen_pam_shap)

g7 <- ggplot(resumen_pam_shap, aes(x = k, y = silhouette)) +
  geom_line() +
  geom_point(size = 2) +
  scale_x_continuous(breaks = 2:6) +
  labs(
    title = "Silhouette promedio por k (PAM sobre SHAP values)",
    x = "k (cantidad de clusters)", y = "Silhouette promedio"
  )
ggsave("Primera competencia/Video Miranda Wintour/plots/pam_silhouette_k.png", g7, width = 8, height = 5)

# Dendrograma jerárquico Ward sobre la distancia SHAP
hc_shap <- hclust(dist_shap, method = "ward.D2")
png("Primera competencia/Video Miranda Wintour/plots/dendrograma_ward.png", width = 1400, height = 800)
plot(hc_shap, labels = FALSE, main = "Dendrograma (Ward sobre SHAP) - clientes BAJA+2", xlab = "", sub = "")
dev.off()

# PAM k=2 sobre SHAP values
k_elegido_shap <- 2
pam_shap <- pam(dist_shap, k = k_elegido_shap, diss = TRUE)

df_cliente <- df_cliente_prom
df_cliente$cluster <- pam_shap$clustering
print(table(df_cliente$cluster))

# Medoides reales de cada fenotipo SHAP
medoides <- df_cliente$numero_de_cliente[pam_shap$id.med]
cat("\nMedoides detectados por SHAP:", medoides, "\n")

# 4. ¿Qué drivers explican cada cluster? (Diferencia de SHAP promedio)
df_shap_analisis <- as.data.frame(shap_matrix)
df_shap_analisis$cluster <- df_cliente$cluster

shap_por_cluster <- df_shap_analisis %>%
  group_by(cluster) %>%
  summarise(across(everything(), mean)) %>%
  pivot_longer(-cluster, names_to = "variable", values_to = "shap_medio") %>%
  pivot_wider(names_from = cluster, values_from = shap_medio, names_prefix = "shap_cluster_") %>%
  mutate(diferencia_shap = abs(shap_cluster_1 - shap_cluster_2)) %>%
  arrange(desc(diferencia_shap))

cat("\n--- Top 10 variables que diferencian el mecanismo de fuga (SHAP) ---\n")
print(head(shap_por_cluster, 10))

# # ============================================================
# # CLUSTERING: Gower + Ward + PAM, sobre un vector por cliente
# # ============================================================

# # resumen por cliente: promedio de cada variable _rank en toda su ventana
# # de meses (un cliente = una fila, insumo para la distancia de Gower)
# vars_rank <- paste0(vars_ranking, "_rank")

# df_cliente <- df_poblacion %>%
#   group_by(numero_de_cliente) %>%
#   summarise(across(all_of(vars_rank), ~ mean(.x, na.rm = TRUE))) %>%
#   ungroup()

# print(dim(df_cliente))
# print(colSums(is.na(df_cliente))) # clientes sin ese producto en ningun mes -> NaN

# # distancia de Gower: soporta los NA que quedan (ej. clientes que nunca
# # tuvieron tarjeta Visa -> Visa_msaldopesos_rank siempre NA/NaN)
# gower_dist <- daisy(df_cliente %>% select(-numero_de_cliente), metric = "gower")
# print(summary(gower_dist))

# # ------------------------------------------------------------
# # jerarquico (Ward) + dendrograma
# # ------------------------------------------------------------
# hc <- hclust(gower_dist, method = "ward.D2")

# png("Primera competencia/Video Miranda Wintour/plots/dendrograma_ward.png", width = 1400, height = 800)
# plot(hc, labels = FALSE, main = "Dendrograma (Ward) - clientes BAJA+2", xlab = "", sub = "")
# dev.off()

# # ------------------------------------------------------------
# # PAM: barrido de k=2..8, silhouette promedio por k
# # ------------------------------------------------------------
# resumen_pam <- do.call(rbind, lapply(2:8, function(k) {
#   res <- pam(gower_dist, k = k, diss = TRUE)
#   data.frame(k = k, silhouette = res$silinfo$avg.width)
# }))
# print(resumen_pam)

# g7 <- ggplot(resumen_pam, aes(x = k, y = silhouette)) +
#   geom_line() +
#   geom_point(size = 2) +
#   scale_x_continuous(breaks = 2:8) +
#   labs(
#     title = "Silhouette promedio por k (PAM, distancia de Gower)",
#     x = "k (cantidad de clusters)", y = "silhouette promedio"
#   )
# print(g7)
# ggsave("Primera competencia/Video Miranda Wintour/plots/pam_silhouette_k.png", g7, width = 8, height = 5)

# # k elegido segun el mayor silhouette del barrido - ajustable a mano despues
# # de mirar el grafico si otro k da perfiles mas interpretables
# k_elegido <- resumen_pam$k[which.max(resumen_pam$silhouette)]
# print(k_elegido)

# pam_final <- pam(gower_dist, k = k_elegido, diss = TRUE)
# df_cliente$cluster <- pam_final$clustering
# print(table(df_cliente$cluster))

# # medoides: el "cliente tipo" real de cada cluster (util para nombrar los
# # perfiles en el video)
# medoides <- df_cliente$numero_de_cliente[pam_final$id.med]
# print(medoides)

# ============================================================
# CARACTERIZACION DE CLUSTERS
# ============================================================

# perfil promedio (posicion relativa) de cada cluster vs el otro, para ver
# que variables los separan mas
perfil_rank <- df_cliente %>%
  select(cluster, all_of(vars_rank)) %>%
  pivot_longer(-cluster, names_to = "variable", values_to = "valor") %>%
  group_by(cluster, variable) %>%
  summarise(media = mean(valor, na.rm = TRUE), .groups = "drop") %>%
  pivot_wider(names_from = cluster, values_from = media, names_prefix = "cluster_")

perfil_rank$diferencia <- perfil_rank$cluster_1 - perfil_rank$cluster_2
perfil_rank <- perfil_rank[order(-abs(perfil_rank$diferencia)), ]
print(perfil_rank, n = 30)

# perfil en valores crudos (pesos, cantidades) por cliente: promedio de cada
# variable original (no rankeada) en su ventana de meses, para cuantificar
# magnitudes reales por cluster
df_cliente_crudo <- df_poblacion %>%
  group_by(numero_de_cliente) %>%
  summarise(across(all_of(vars_ranking), ~ mean(.x, na.rm = TRUE))) %>%
  ungroup() %>%
  left_join(df_cliente %>% select(numero_de_cliente, cluster), by = "numero_de_cliente")

perfil_crudo <- df_cliente_crudo %>%
  select(cluster, all_of(vars_ranking)) %>%
  pivot_longer(-cluster, names_to = "variable", values_to = "valor") %>%
  group_by(cluster, variable) %>%
  summarise(mediana = median(valor, na.rm = TRUE), .groups = "drop") %>%
  pivot_wider(names_from = cluster, values_from = mediana, names_prefix = "cluster_")
print(perfil_crudo, n = 30)

# perfil de los medoides (el "cliente tipo" real de cada cluster), en crudo
perfil_medoides <- df_cliente_crudo %>%
  filter(numero_de_cliente %in% medoides) %>%
  select(numero_de_cliente, cluster, all_of(vars_ranking))
print(perfil_medoides)

# ============================================================
# CUANTIFICACION: plata en juego por cluster, con el valor oficial
# de la funcion de ganancia de la competencia (PDF de presentacion del
# problema, pag. 27-32): cada BAJA+2 retenido = $1.072.500,
# cada envio que no sirve = -$27.500
# ============================================================

valor_cliente_retenido <- 1072500

plata_en_juego <- df_cliente_crudo %>%
  group_by(cluster) %>%
  summarise(n_clientes = n(), .groups = "drop") %>%
  mutate(
    valor_potencial_100pct = n_clientes * valor_cliente_retenido,
    valor_retenido_10pct = n_clientes * 0.10 * valor_cliente_retenido,
    valor_retenido_20pct = n_clientes * 0.20 * valor_cliente_retenido
  )
print(plata_en_juego)

# ganancia neta: descuenta el costo de los envios que NO funcionan
# ($27.500 c/u, misma formula del PDF de presentacion del problema)
valor_envio_inutil <- 27500

plata_en_juego <- plata_en_juego %>%
  mutate(
    ganancia_neta_10pct = (n_clientes * 0.10 * valor_cliente_retenido) -
      (n_clientes * 0.90 * valor_envio_inutil),
    ganancia_neta_20pct = (n_clientes * 0.20 * valor_cliente_retenido) -
      (n_clientes * 0.80 * valor_envio_inutil)
  )
print(plata_en_juego)

# ============================================================
# LIFT POR CLUSTER: mediana_cluster / mediana_global, por variable
# ============================================================

lift_clusters <- df_cliente_crudo %>%
  select(cluster, all_of(vars_ranking)) %>%
  pivot_longer(-cluster, names_to = "variable", values_to = "valor") %>%
  group_by(variable) %>%
  mutate(mediana_global = median(valor, na.rm = TRUE)) %>%
  ungroup() %>%
  group_by(cluster, variable, mediana_global) %>%
  summarise(mediana_cluster = median(valor, na.rm = TRUE), .groups = "drop") %>%
  mutate(lift = ifelse(mediana_global != 0, mediana_cluster / mediana_global, NA_real_))

lift_wide <- lift_clusters %>%
  select(cluster, variable, lift) %>%
  pivot_wider(names_from = cluster, values_from = lift, names_prefix = "lift_cluster_")
print(lift_wide, n = 30)

# ============================================================
# EVOLUCION TEMPORAL POR CLUSTER (CALIBRACION DE ESCALAS Y TITULO)
# ============================================================

df_evolucion_cluster <- df_evolucion %>%
  inner_join(df_cliente %>% select(numero_de_cliente, cluster), by = "numero_de_cliente")

vars_evol_cluster <- c("ctrx_quarter_rank", "mcuentas_saldo_rank", "mtarjeta_visa_consumo_rank")

resumen_evol_cluster <- df_evolucion_cluster %>%
  select(cluster, meses_para_fin, all_of(vars_evol_cluster)) %>%
  pivot_longer(-c(cluster, meses_para_fin), names_to = "variable", values_to = "valor") %>%
  mutate(
    variable = sub("_rank$", "", variable),
    variable = case_when(
      variable == "ctrx_quarter" ~ "Actividad (Transacciones)",
      variable == "mcuentas_saldo" ~ "Saldo total en cuentas",
      variable == "mtarjeta_visa_consumo" ~ "Consumo con tarjeta Visa",
      TRUE ~ variable
    ),
    variable = factor(variable, levels = c(
      "Actividad (Transacciones)",
      "Saldo total en cuentas",
      "Consumo con tarjeta Visa"
    )),
    perfil = ifelse(cluster == 1, "Fenotipo Hipoinflamatorio (67%)", "Fenotipo Hiperinflamatorio (33%)")
  ) %>%
  group_by(perfil, variable, meses_para_fin) %>%
  summarise(
    # Media para que la trayectoria refleje la caida real de ambos perfiles y no quede clavada en 0
    valor_centro = mean(valor, na.rm = TRUE),
    q25 = quantile(valor, 0.25, na.rm = TRUE),
    q75 = quantile(valor, 0.75, na.rm = TRUE),
    n = sum(!is.na(valor)),
    .groups = "drop"
  )

# Anclas limpias: Actividad y Visa de 0 a 1; Saldo simetrico de -0.75 a 0.75
df_anclas_ejes <- data.frame(
  variable = factor(rep(c(
    "Actividad (Transacciones)",
    "Saldo total en cuentas",
    "Consumo con tarjeta Visa"
  ), each = 2), levels = levels(resumen_evol_cluster$variable)),
  meses_para_fin = 0,
  valor = c(0, 1, -0.75, 0.75, 0, 1)
)

df_linea_cero <- data.frame(
  variable = factor("Saldo total en cuentas", levels = levels(resumen_evol_cluster$variable)),
  y = 0
)

g8 <- ggplot(resumen_evol_cluster, aes(x = meses_para_fin, y = valor_centro, color = perfil, fill = perfil)) +
  geom_blank(data = df_anclas_ejes, aes(x = meses_para_fin, y = valor), inherit.aes = FALSE) +
  geom_hline(data = df_linea_cero, aes(yintercept = y), linetype = "dashed", color = "gray55", linewidth = 0.6, inherit.aes = FALSE) +
  geom_ribbon(aes(ymin = q25, ymax = q75), alpha = 0.18, color = NA) +
  geom_line(linewidth = 1.3) +
  geom_point(size = 2.6) +
  facet_wrap(~variable, scales = "free_y") +
  scale_x_reverse() +
  scale_y_continuous(breaks = seq(-0.75, 1, by = 0.25)) +
  scale_color_manual(values = c("Fenotipo Hipoinflamatorio (67%)" = "#D9381E", "Fenotipo Hiperinflamatorio (33%)" = "#0077B6")) +
  scale_fill_manual(values = c("Fenotipo Hipoinflamatorio (67%)" = "#D9381E", "Fenotipo Hiperinflamatorio (33%)" = "#0077B6")) +
  labs(
    title = "Dinámica Temporal Previa a la Baja por Fenotipo",
    x = "Ventana temporal previa a la baja",
    y = "Nivel relativo en la cartera (Percentil)",
    color = "Perfil de Cliente:", fill = "Perfil de Cliente:"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold", size = 15, hjust = 0, color = "#0D1B2A"),
    legend.position = "bottom",
    legend.title = element_text(face = "bold", size = 11),
    legend.text = element_text(size = 11),
    strip.text = element_text(face = "bold", size = 12, color = "#0D1B2A"),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_line(color = "gray92"),
    panel.grid.major.y = element_line(color = "gray92"),
    axis.text.x = element_blank(),
    axis.ticks.x = element_blank(),
    plot.margin = margin(15, 15, 15, 15)
  )

ruta_guardado <- "/Users/veronicaestermonzon/Library/Mobile Documents/com~apple~CloudDocs/MDM/4. DM Economia y Finanzas/Primera competencia/Video Miranda Wintour/plots/evolucion_temporal_por_cluster.png"
dir.create(dirname(ruta_guardado), recursive = TRUE, showWarnings = FALSE)
ggsave(ruta_guardado, g8, width = 13, height = 5.5, dpi = 300)
message(">>> GUARDADO LISTO: ", ruta_guardado)

# ============================================================
# CIERRE DEL LOG
# ============================================================

sink(type = "message")
sink()
close(log_con)
