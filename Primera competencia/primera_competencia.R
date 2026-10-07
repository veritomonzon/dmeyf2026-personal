# ============================================================
# HOUSEKEEPING
# ============================================================
rm(list = ls())
gc()
options(scipen = 999)

# ============================================================
# CONFIGURACION DEL EXPERIMENTO
# ============================================================
# Unico bloque que se modifica entre corridas (Mac o VM).
# Antes de correr: actualizar PARAM y agregar la linea al HISTORIAL.
# Despues de correr: completar resultados en el HISTORIAL y commitear.

PARAM <- list(
    experimento = "exp03c_baja12_bin31",
    target = "baja12", # "baja2" = BAJA+2 vs resto | "baja12" = BAJA+1 + BAJA+2 vs CONTINUA
    max_bin = 31L, # 255 = default LightGBM | 31 = frugal (Clase 06)
    modo_ht = "fijos", # "busqueda" = random search | "fijos" = hp fijos x semillas | "ninguno" = reusar HT_resultados.csv
    n_iteraciones = 450L, # solo modo_ht = "busqueda"
    n_semillas_cv = 5L, # solo modo_ht = "fijos" (toma las primeras de PARAM$semillas)
    hp_fijos = list( # solo modo_ht = "fijos" (champion exp01, iter 135)
        num_leaves = 16L, min_data_in_leaf = 800L, feature_fraction = 0.2704,
        learning_rate = 0.0172, num_iterations = 550L
    ),
    semillas = c(
        333331L, 444443L, 555557L, 666667L, 121313L,
        533129L, 600011L, 700001L, 800011L, 900001L
    ),
    corte_final = 11000L # NA = envios_optimos de CV | o fijar, ej. 11000L
)

# ------------------------------------------------------------
# HISTORIAL DE EXPERIMENTOS (registro, no se ejecuta)
# ------------------------------------------------------------
# exp01_mac_154iter   | Mac | baja2 | max_bin 255 | busqueda (154 iters)
#   champion it135: leaves 16, min_data 800, ff 0.2704, lr 0.0172, iters 550
#   CV 202106: $476.822.500 (corte 10.221)
#   Public: 10 sem 91,03 +- 2,09 | ensamble10 89,24 | semilla unica c11000 91,41
# exp02_vm_276iter    | VM  | baja2 | max_bin 255 | busqueda (276 iters)
#   champion it122: leaves 96, min_data 800, ff 0.2330, lr 0.0156, iters 550
#   CV 202106: $475.392.500 (corte 11.513)
#   Public: 10 sem 90,57 +- 3,82 | ensamble10 89,84
# exp03a_baja2_bin255 | Mac | baja2  | max_bin 255 | fijos champion exp01 x 5 sem | 13 min
#   CV 202106: gan_c11000 463.320.000 +- 2.847.279 | gan_max 468.138.000 +- 6.007.583
#   La semilla 333331 dio 478,7 M: el 476,8 M de exp01 estaba inflado por la semilla
# exp03b_baja2_bin31  | Mac | baja2  | max_bin 31  | fijos champion exp01 x 5 sem | 13 min
#   CV 202106: gan_c11000 471.900.000 +- 5.159.457 | gan_max 477.873.000 +- 4.906.088
#   vs exp03a: +8,6 M en c11000, mejora en las 5 semillas (t apareado p ~ 0,008); sin ganancia de velocidad
#   Public: 10 sem 96,14 +- 3,65 (c11000) vs exp01 91,03 +- 2,09 (c10221)
# exp03c_baja12_bin31 | Mac | baja12 | max_bin 31  | fijos champion exp01 x 5 sem | PENDIENTE

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

dir_base <- if (dir.exists("~/data")) "~/data" else "Primera competencia"
dir_exp <- file.path(dir_base, "exp", PARAM$experimento)

while (sink.number() > 0) sink()
closeAllConnections()

dir.create(file.path(dir_base, "plots"), showWarnings = FALSE) # AED, compartido entre experimentos
dir.create(file.path(dir_exp, "logs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(dir_exp, "plots"), recursive = TRUE, showWarnings = FALSE)

log_con <- file(file.path(dir_exp, "logs/primera_competencia.md"), open = "at")
sink(log_con, append = TRUE, split = TRUE)

cat("--- INICIO DE EJECUCION: PRIMERA COMPETENCIA ---\n")
cat("Fecha y hora:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Entorno:", if (dir_base == "~/data") "VM" else "Mac local", "\n")
cat("Configuracion del experimento:\n")
str(PARAM)
cat("\n")

# ============================================================
# CARGA DE BASE DE DATOS
# ============================================================

archivo_rds_fe <- file.path(dir_base, "fe_particiones_listas.rds")

if (!file.exists(archivo_rds_fe)) {
    archivo_dataset <- if (file.exists(file.path(dir_base, "competencia_01.csv.gz"))) {
        file.path(dir_base, "competencia_01.csv.gz")
    } else {
        file.path(dir_base, "competencia_01_ct.csv.gz")
    }
    cat("--- CARGA DE DATASET OFICIAL ---\n")
    dataset <- fread(archivo_dataset)
    if ("clase_ternaria_alt" %in% names(dataset)) dataset[, clase_ternaria_alt := NULL]

    # ============================================================
    # CHEQUEO ESTRUCTURAL Y DISTRIBUCION DEL TARGET
    # ============================================================
    cat("\n--- DIMENSIONES DE LA BASE ---\n")
    cat("Filas:", nrow(dataset), "- Columnas:", ncol(dataset), "\n")
    cat("\n--- DISTRIBUCION DE TARGET POR FOTO_MES ---\n")
    tabla_target <- dataset[, .N, by = .(foto_mes, clase_ternaria)][order(foto_mes, clase_ternaria)]
    print(tabla_target)
    # Variables numericas para analisis (excluyendo IDs y meses)
    vars_numericas <- setdiff(names(dataset)[sapply(dataset, is.numeric)], c("numero_de_cliente", "foto_mes"))
    meses_presentes <- sort(unique(dataset$foto_mes))

    # ============================================================
    # AED
    # ============================================================

    # EVALUACION Y GRAFICOS DE DATOS FALTANTES (NA'S)

    cat("\n--- METRICAS GLOBALES DE FALTANTES (NANIAR) ---\n")
    cat("Total celdas NA:", n_miss(dataset), "\n")
    cat("Proporcion global de NA:", round(prop_miss(dataset) * 100, 2), "%\n")
    cat("Filas completas sin ningun NA:", sum(complete.cases(dataset)), "de", nrow(dataset), "\n")
    # Resumen de variables con faltantes
    resumen_na <- miss_var_summary(dataset)
    cat("\nTop 20 variables con mayor proporcion de faltantes:\n")
    print(head(as.data.frame(resumen_na), 20))
    # Grafico 1: Porcentaje de faltantes por variable
    cat("\nGenerando grafico de faltantes (gg_miss_var)...\n")
    p_miss_var <- gg_miss_var(dataset[, ..vars_numericas], show_pct = TRUE) +
        labs(title = "Porcentaje de datos faltantes por variable") +
        theme_minimal(base_size = 9)
    ggsave(file.path(dir_base, "plots/aed_gg_miss_var.png"), p_miss_var, width = 11, height = 18)
    # Grafico 2: Mapa de calor de faltantes (vis_miss sobre muestra de 25.000 filas para agilidad)
    set.seed(333331)
    idx_sample <- sample(nrow(dataset), 25000)
    cat("Generando mapa de calor de faltantes (vis_miss sobre muestra)...\n")
    p_vis_miss <- vis_miss(dataset[idx_sample, ..vars_numericas], warn_large_data = FALSE) +
        labs(title = "Mapa de distribucion de datos faltantes (Muestra N=25.000)")
    ggsave(file.path(dir_base, "plots/aed_vis_miss.png"), p_vis_miss, width = 14, height = 9)

    # AED 2: EVALUACION Y SERIE TEMPORAL DE CEROS (0'S)

    cat("\n--- PROPORCION GLOBAL DE CEROS EN VARIABLES NUMERICAS ---\n")
    prop_ceros_global <- sapply(dataset[, ..vars_numericas], function(x) mean(x == 0, na.rm = TRUE))
    prop_ceros_global <- sort(prop_ceros_global[prop_ceros_global > 0], decreasing = TRUE)
    cat("Top 20 variables con mayor porcentaje de ceros:\n")
    print(round(head(prop_ceros_global, 20) * 100, 2))
    cat("\n--- AUDITORIA LONGITUDINAL DE CEROS POR FOTO_MES ---\n")
    # Deteccion de 100% de ceros en un mes especifico (recuperado de tu analisis)
    detectar_todo_cero <- function(variable, mes) {
        x <- dataset[foto_mes == mes, get(variable)]
        x_valido <- x[!is.na(x)]
        length(x_valido) > 0 && all(x_valido == 0)
    }
    combos <- expand.grid(
        variable = vars_numericas,
        foto_mes = meses_presentes,
        stringsAsFactors = FALSE
    )
    combos$todo_cero <- mapply(detectar_todo_cero, combos$variable, combos$foto_mes)
    vars_anomalas_cero <- combos[combos$todo_cero, ]
    if (nrow(vars_anomalas_cero) > 0) {
        cat("\nALERTAS: Variables con 100% ceros en un mes particular (posibles caidas de carga):\n")
        print(vars_anomalas_cero[order(vars_anomalas_cero$foto_mes, vars_anomalas_cero$variable), ])
    } else {
        cat("\nNo se registraron meses con 100% ceros absolutos.\n")
    }
    # AED 3: DISTRIBUCION DE VARIABLES CLAVE (CONTINUA VS BAJA+2)

    cat("\n--- DISTRIBUCION DE VARIABLES DE DOMINIO: CONTINUA VS BAJA+2 ---\n")
    vars_clave <- c(
        "ctrx_quarter", "mpasivos_margen", "mcuentas_saldo", "mcaja_ahorro",
        "cpayroll_trx", "mtarjeta_visa_consumo", "mpayroll", "mcuenta_corriente",
        "cliente_antiguedad", "cliente_edad"
    )
    # Comparacion en percentiles en meses donde se conoce el target (202103 a 202106)
    sub_target <- dataset[foto_mes <= 202106 & clase_ternaria %in% c("CONTINUA", "BAJA+2")]
    cat("Percentiles (P25, P50, P75) comparativos por clase:\n")
    for (v in vars_clave) {
        cat("\nVariable:", v, "\n")
        tabla_p <- sub_target[, .(
            P25 = quantile(get(v), 0.25, na.rm = TRUE),
            Mediana = median(get(v), na.rm = TRUE),
            P75 = quantile(get(v), 0.75, na.rm = TRUE),
            Media = mean(get(v), na.rm = TRUE)
        ), by = clase_ternaria]
        print(tabla_p)
    }
    # Grafico 3: Boxplots faceteados de variables clave
    cat("\nGenerando boxplots comparativos CONTINUA vs BAJA+2...\n")
    df_plot_dist <- melt(
        sub_target[, c("clase_ternaria", vars_clave), with = FALSE],
        id.vars = "clase_ternaria",
        measure.vars = vars_clave,
        variable.name = "variable",
        value.name = "valor"
    )
    p_boxplots <- ggplot(df_plot_dist, aes(x = clase_ternaria, y = valor, fill = clase_ternaria)) +
        geom_boxplot(outlier.size = 0.4, alpha = 0.7) +
        facet_wrap(~variable, scales = "free_y", ncol = 4) +
        labs(
            title = "Distribucion de variables clave segun condicion de abandono (202103-202106)",
            x = "Clase", y = "Valor monetario / transaccional"
        ) +
        theme_minimal() +
        theme(legend.position = "none")
    ggsave(file.path(dir_base, "plots/aed_distribucion_variables_clave.png"), p_boxplots, width = 15, height = 10)

    # AED 4: MATRIZ DE CORRELACION Y MULTICOLINEALIDAD

    cat("\n--- DETECCION DE ALTA CORRELACION (|r| > 0.85) ---\n")
    matriz_cor <- cor(dataset[idx_sample, ..vars_numericas], use = "pairwise.complete.obs")
    pares_altos <- which(abs(matriz_cor) > 0.85 & upper.tri(matriz_cor), arr.ind = TRUE)
    df_correlaciones <- data.frame(
        Variable_1 = rownames(matriz_cor)[pares_altos[, 1]],
        Variable_2 = colnames(matriz_cor)[pares_altos[, 2]],
        Correlacion = round(matriz_cor[pares_altos], 3)
    )
    df_correlaciones <- df_correlaciones[order(-abs(df_correlaciones$Correlacion)), ]
    cat(sprintf("Total pares con correlacion > 0.85: %d\n", nrow(df_correlaciones)))
    print(head(df_correlaciones, 15))
    cat("\n--- FIN DEL AED ---\n\n")

    # GRAFICO DE MATRIZ DE CORRELACION (HEATMAP CLUSTERIZADO)

    cat("\nGenerando grafico de matriz de correlacion (corrplot)...\n")

    # Tomamos las variables con r > 0.85 mas las variables clave de dominio
    vars_matriz <- unique(c(df_correlaciones$Variable_1, df_correlaciones$Variable_2, vars_clave))

    # Matriz sobre la muestra para calculo rapido
    mat_sub <- cor(dataset[idx_sample, ..vars_matriz], use = "pairwise.complete.obs")

    # Guardar figura en alta resolucion
    png(file.path(dir_base, "plots/aed_matriz_correlacion.png"), width = 1200, height = 1200, res = 110)

    corrplot::corrplot(
        mat_sub,
        method = "color",
        type = "upper",
        order = "hclust",
        tl.col = "black",
        tl.cex = 0.75,
        cl.cex = 0.8,
        title = "Matriz de Correlacion: Variables Clave y Colineales (|r| > 0.85)",
        mar = c(0, 0, 2, 0)
    )

    dev.off()

    cat("Grafico guardado en:", file.path(dir_base, "plots/aed_matriz_correlacion.png"), "\n")

    # ============================================================
    # ETL: CALIDAD DE DATOS, FLAGS Y COALESCENCIA DE PRODUCTOS
    # ============================================================

    cat("\n--- INICIO DE ETAPA: ETL Y TRATAMIENTO DE VARIABLES ---\n")

    # 1. Correccion confirmada por el AED en ccajas_depositos
    n_corregidos <- dataset[foto_mes == 202105, sum(ccajas_depositos == 0, na.rm = TRUE)]
    dataset[foto_mes == 202105, ccajas_depositos := NA_real_]
    cat(sprintf("Data Quality: %d registros de ccajas_depositos en 202105 recodificados a NA\n", n_corregidos))

    # 2. Flags binarias de tenencia de producto y acreditacion
    cat("\nGenerando flags de tenencia de producto...\n")
    dataset[, flag_visa := as.integer(!is.na(Visa_status))]
    dataset[, flag_master := as.integer(!is.na(Master_status))]
    dataset[, flag_tarjetas := as.integer(flag_visa == 1L | flag_master == 1L)]
    dataset[, flag_payroll := as.integer(fcoalesce(mpayroll, 0) > 0)]

    # 3. Coalescencia segura y totalizadores de tarjetas (Visa + Master)
    cat("Generando totalizadores consolidados de tarjetas con coalescencia segura...\n")
    dataset[, tarjetas_mconsumototal := fcoalesce(Visa_mconsumototal, 0) + fcoalesce(Master_mconsumototal, 0)]
    dataset[, tarjetas_msaldototal := fcoalesce(Visa_msaldototal, 0) + fcoalesce(Master_msaldototal, 0)]
    dataset[, tarjetas_mlimitecompra := fcoalesce(Visa_mlimitecompra, 0) + fcoalesce(Master_mlimitecompra, 0)]
    dataset[, tarjetas_cconsumos := fcoalesce(Visa_cconsumos, 0L) + fcoalesce(Master_cconsumos, 0L)]
    dataset[, tarjetas_madelantopesos := fcoalesce(Visa_madelantopesos, 0) + fcoalesce(Master_madelantopesos, 0)]

    # 4. Auditoria agregada post-ETL
    cat("\n--- CONTROL AGREGADO DE NUEVAS VARIABLES ---\n")
    cat("Nuevas dimensiones de la base:", nrow(dataset), "filas x", ncol(dataset), "columnas\n\n")

    cat("Frecuencia de tenencia de tarjetas en la cartera:\n")
    print(dataset[, .N, by = .(flag_visa, flag_master, flag_tarjetas)][order(-N)])

    cat("\nFrecuencia de clientes con acreditacion de haberes (flag_payroll):\n")
    print(dataset[, .N, by = .(flag_payroll)])

    cat("\nResumen cuantitativo de totalizadores consolidados de tarjetas:\n")
    print(summary(dataset[, .(tarjetas_mconsumototal, tarjetas_msaldototal, tarjetas_mlimitecompra)]))

    cat("\n--- FIN ETAPA ETL ---\n\n")

    # ============================================================
    # 5. FEATURE ENGINEERING LONGITUDINAL HÍBRIDO (LAGS + RANKS)
    # ============================================================

    cat("\n--- INICIO FEATURE ENGINEERING LONGITUDINAL ---\n")
    tiempo_fe_inicio <- Sys.time()

    # 1. Asegurar orden cronológico estricto por cliente
    setorder(dataset, numero_de_cliente, foto_mes)

    # 2. Selección de variables numéricas para lags nominales
    cols_excluir <- c("numero_de_cliente", "foto_mes", "clase_ternaria", "cliente_antiguedad")
    cols_lags <- setdiff(names(dataset), cols_excluir)
    cols_lags <- cols_lags[vapply(dataset[, ..cols_lags], is.numeric, logical(1))]

    cat("Variables base seleccionadas para lags:", length(cols_lags), "\n")

    # 3. Construcción vectorizada de Rezagos (Lags 1 y 2)
    cat("Calculando lags nominales (orden 1 y 2)...\n")
    cols_lag1 <- paste0(cols_lags, "_lag1")
    cols_lag2 <- paste0(cols_lags, "_lag2")

    dataset[, (cols_lag1) := shift(.SD, n = 1L, type = "lag"), by = numero_de_cliente, .SDcols = cols_lags]
    dataset[, (cols_lag2) := shift(.SD, n = 2L, type = "lag"), by = numero_de_cliente, .SDcols = cols_lags]

    # 4. Construcción de Deltas Nominales (Delta 1 y 2)
    cat("Calculando deltas nominales...\n")
    for (v in cols_lags) {
        dataset[, paste0(v, "_delta1") := get(v) - get(paste0(v, "_lag1"))]
        dataset[, paste0(v, "_delta2") := get(v) - get(paste0(v, "_lag2"))]
    }

    # 5. Función de Rankeo Intra-Mes por Signo
    rankear_por_signo <- function(x) {
        r <- rep(NA_real_, length(x))
        pos <- which(x > 0)
        neg <- which(x < 0)
        ceros <- which(x == 0)
        if (length(pos) > 0) r[pos] <- frank(x[pos], ties.method = "average") / length(pos)
        if (length(neg) > 0) r[neg] <- -(frank(-x[neg], ties.method = "average") / length(neg))
        if (length(ceros) > 0) r[ceros] <- 0
        return(r)
    }

    # 6. Selección y normalización de variables monetarias
    cols_monetarias <- grep("^(m|tarjetas_m|Master_m|Visa_m)", cols_lags, value = TRUE)
    cat("Variables monetarias identificadas para rankeo deflactario:", length(cols_monetarias), "\n")

    cat("Generando ranks intra-mes por signo...\n")
    for (vm in cols_monetarias) {
        dataset[, paste0(vm, "_rk") := rankear_por_signo(get(vm)), by = foto_mes]
    }

    # 7. Deltas sobre variables rankeadas (Salto de Percentiles)
    cat("Calculando deltas percentilares (Delta Rank 1 y 2)...\n")
    cols_rk <- paste0(cols_monetarias, "_rk")
    cols_rk_lag1 <- paste0(cols_rk, "_lag1")
    cols_rk_lag2 <- paste0(cols_rk, "_lag2")

    dataset[, (cols_rk_lag1) := shift(.SD, n = 1L, type = "lag"), by = numero_de_cliente, .SDcols = cols_rk]
    dataset[, (cols_rk_lag2) := shift(.SD, n = 2L, type = "lag"), by = numero_de_cliente, .SDcols = cols_rk]

    for (vrk in cols_rk) {
        dataset[, paste0(vrk, "_delta1") := get(vrk) - get(paste0(vrk, "_lag1"))]
        dataset[, paste0(vrk, "_delta2") := get(vrk) - get(paste0(vrk, "_lag2"))]
    }

    # 8. Limpieza de columnas auxiliares para optimizar RAM
    dataset[, (c(cols_rk_lag1, cols_rk_lag2)) := NULL]

    # ============================================================
    # 5.1 FEATURE ENGINEERING: RATIOS DE NEGOCIO Y RETENCIÓN
    # ============================================================

    cat("\n--- CONSTRUCCIÓN DE RATIOS DE NEGOCIO Y RETENCIÓN ---\n")

    # Función auxiliar de división segura (evita ceros, negativos en denominador e Infinitos)
    division_segura <- function(num, den, epsilon = 1.0) {
        den_ajustado <- pmax(den, epsilon, na.rm = FALSE)
        res <- num / den_ajustado
        res[is.infinite(res)] <- NA_real_
        return(res)
    }

    # 1. Ratios Estructurales de Negocio (Intra-mes)
    cat("Calculando ratios estructurales de tarjetas y liquidez...\n")

    if ("tarjetas_msaldototal" %in% names(dataset) & "tarjetas_mlimitecompra" %in% names(dataset)) {
        dataset[, ratio_tarjeta_utilizacion := division_segura(tarjetas_msaldototal, tarjetas_mlimitecompra)]
        dataset[, ratio_tarjeta_consumo_limite := division_segura(tarjetas_mconsumototal, tarjetas_mlimitecompra)]
    }

    if ("tarjetas_mconsumototal" %in% names(dataset) & "mcuentas_saldo" %in% names(dataset)) {
        dataset[, ratio_consumo_sobre_saldo := division_segura(tarjetas_mconsumototal, mcuentas_saldo)]
    }

    if ("mpayroll" %in% names(dataset) & "mcuentas_saldo" %in% names(dataset)) {
        dataset[, ratio_payroll_sobre_saldo := division_segura(mpayroll, mcuentas_saldo)]
    }

    # 2. Ratios Longitudinales de Retención (Mes actual vs Lag 1)
    cat("Calculando ratios longitudinales de retención (Mes actual vs Lag 1)...\n")

    dataset[, ratio_retencion_saldo_mcuentas := fifelse(
        mcuentas_saldo_lag1 > 0 & mcuentas_saldo >= 0,
        division_segura(mcuentas_saldo, mcuentas_saldo_lag1),
        NA_real_
    )]

    if ("tarjetas_msaldototal_lag1" %in% names(dataset)) {
        dataset[, ratio_retencion_saldo_tarjetas := fifelse(
            tarjetas_msaldototal_lag1 > 0 & tarjetas_msaldototal >= 0,
            division_segura(tarjetas_msaldototal, tarjetas_msaldototal_lag1),
            NA_real_
        )]
    }

    if ("tarjetas_mconsumototal_lag1" %in% names(dataset)) {
        dataset[, ratio_retencion_consumo_tarjetas := fifelse(
            tarjetas_mconsumototal_lag1 > 0 & tarjetas_mconsumototal >= 0,
            division_segura(tarjetas_mconsumototal, tarjetas_mconsumototal_lag1),
            NA_real_
        )]
    }

    tiempo_fe_fin <- Sys.time()
    cat("Tiempo insumido en Feature Engineering:", round(difftime(tiempo_fe_fin, tiempo_fe_inicio, units = "mins"), 2), "minutos\n")

    # 9. Auditoría dimensional y control de memoria
    memoria_gb <- round(as.numeric(object.size(dataset)) / (1024^3), 2)
    cat("\n--- AUDITORÍA POST FEATURE ENGINEERING ---\n")
    cat("Dimensiones finales del dataset:", nrow(dataset), "filas x", ncol(dataset), "columnas\n")
    cat("Memoria RAM ocupada por el dataset:", memoria_gb, "GB\n")

    # Verificación de integridad temporal en mes de entrenamiento (202106) y predicción (202108)
    cat("Registros en 202106 (Train):", nrow(dataset[foto_mes == 202106]), "\n")
    cat("Registros en 202108 (Test/Future):", nrow(dataset[foto_mes == 202108]), "\n")
    cat("Completitud lag1 en 202106:", round(mean(!is.na(dataset[foto_mes == 202106, mcuentas_saldo_lag1])) * 100, 2), "%\n")
    cat("Completitud lag1 en 202108:", round(mean(!is.na(dataset[foto_mes == 202108, mcuentas_saldo_lag1])) * 100, 2), "%\n")
    cat("\n--- FIN ETAPA FEATURE ENGINEERING ---\n\n")

    # ============================================================
    # 6. PARTICIONES, FOLDS ESTRATIFICADOS Y FUNCIÓN GANANCIA
    # ============================================================

    cat("\n--- PREPARACIÓN PARA MODELADO Y VALIDACIÓN CRUZADA ---\n")

    # 1. Definición de campos predictores (excluyendo identificadores y metas)
    cols_excluir_modelo <- c("numero_de_cliente", "foto_mes", "clase_ternaria", "clase01")
    campos_buenos <- setdiff(names(dataset), cols_excluir_modelo)
    cat("Cantidad de features predictoras finales:", length(campos_buenos), "\n")

    # 2. Partición de Entrenamiento (foto_mes == 202106)
    cat("Generando partición de entrenamiento (202106)...\n")
    df_train <- dataset[foto_mes == 202106, c("numero_de_cliente", "foto_mes", "clase_ternaria", campos_buenos), with = FALSE]
    df_train[, clase01 := fifelse(clase_ternaria == "BAJA+2", 1L, 0L)]

    # 3. Partición Futuro / Scoring (foto_mes == 202108)
    cat("Generando partición de evaluación futura (202108)...\n")
    df_future <- dataset[foto_mes == 202108, c("numero_de_cliente", "foto_mes", campos_buenos), with = FALSE]

    # 4. Liberación de memoria eliminando meses históricos ya procesados
    cat("Liberando memoria RAM de meses intermedios...\n")
    rm(dataset)
    invisible(gc())
    cat("Memoria RAM liberada. Columnas listas para entrenamiento.\n")

    # 5. Asignación de 5 Folds Estratificados sobre 202106
    cat("Asignando 5 Folds estratificados con semilla primigenia (333331)...\n")
    set.seed(333331)
    k_folds <- 5L
    df_train[, fold := 0L]

    # Estratificación exacta para balancear BAJA+2 en cada fold
    idx_pos <- which(df_train$clase01 == 1L)
    idx_neg <- which(df_train$clase01 == 0L)

    df_train[idx_pos, fold := sample(rep(1:k_folds, length.out = length(idx_pos)))]
    df_train[idx_neg, fold := sample(rep(1:k_folds, length.out = length(idx_neg)))]

    cat("Distribución de target (clase01) por Fold en 202106:\n")
    print(table(Fold = df_train$fold, Target = df_train$clase01))

    # Guardar para no volver a correr nunca más los 14 minutos de FE
    cat("\nGuardando particiones procesadas en:", archivo_rds_fe, "\n")
    saveRDS(
        list(df_train = df_train, df_future = df_future, campos_buenos = campos_buenos),
        file = archivo_rds_fe
    )
} else {
    cat("\n--- CARGANDO PARTICIONES PRE-PROCESADAS DESDE DISCO (.RDS) ---\n")
    objs <- readRDS(archivo_rds_fe)
    df_train <- objs$df_train
    df_future <- objs$df_future
    campos_buenos <- objs$campos_buenos
    rm(objs)
    invisible(gc())
    cat("Particiones cargadas en memoria en segundos.\n")
}

# Variables y funciones globales (siempre disponibles aunque cargue desde .rds)
if (!exists("tiempo_fe_inicio")) tiempo_fe_inicio <- Sys.time()
k_folds <- 5L

# ============================================================
# TARGET DE ENTRENAMIENTO SEGUN EXPERIMENTO
# ============================================================
# La ganancia se evalua SIEMPRE con BAJA+2 real (target_eval);
# solo cambia la etiqueta con la que aprende LightGBM (target_entreno).
target_eval <- df_train$clase01
target_entreno <- if (PARAM$target == "baja12") {
    as.integer(df_train$clase_ternaria %in% c("BAJA+1", "BAJA+2"))
} else {
    df_train$clase01
}
cat("Target de entrenamiento:", PARAM$target, "- positivos:", sum(target_entreno), "\n")

# 6. Función de Ganancia de Negocio Oficial
# Ganancia = TP * $1.072.500 - FP * $27.500
calcular_ganancia_maxima <- function(probs, target_real) {
    dt_eval <- data.table(p = probs, y = target_real)
    setorder(dt_eval, -p)

    # Ganancia acumulada cliente por cliente
    dt_eval[, ganancia_acum := cumsum(fifelse(y == 1L, 1072500, -27500))]

    idx_max <- which.max(dt_eval$ganancia_acum)
    ganancia_max <- dt_eval$ganancia_acum[idx_max]
    corte_optimo_envios <- idx_max
    prob_corte <- dt_eval$p[idx_max]

    return(list(
        ganancia = ganancia_max,
        envios_optimos = corte_optimo_envios,
        probabilidad_corte = prob_corte
    ))
}

# Ganancia en un corte fijo de envios (comparacion justa entre experimentos:
# el maximo de la curva elige el corte a posteriori y es optimista)
ganancia_en_corte <- function(probs, target_real, corte = 11000L) {
    y_top <- target_real[order(-probs)][1:corte]
    sum(fifelse(y_top == 1L, 1072500, -27500))
}

cat("Estructura de validación cruzada y función de ganancia listas.\n")

# ============================================================
# 7. OPTIMIZACIÓN DE HIPERPARÁMETROS NOCTURNA (5-FOLD CV)
# ============================================================

# 1. Objetos base obligatorios para el Bloque 7 y Bloque 8
cat("\nConstruyendo matriz numérica de entrenamiento...\n")
mat_train <- as.matrix(df_train[, ..campos_buenos])
archivo_ht <- file.path(dir_exp, "HT_resultados.csv")

# Modo de busqueda definido en PARAM (ver CONFIGURACION DEL EXPERIMENTO)
correr_ht_nocturno <- PARAM$modo_ht != "ninguno"

if (correr_ht_nocturno) {
    cat("\n--- INICIO DE OPTIMIZACIÓN DE HIPERPARÁMETROS (HT) ---\n")
    tiempo_ht_inicio <- Sys.time()

    # 2. Pre-construcción de datasets LightGBM para los 5 Folds (Aceleración masiva)
    cat("Pre-construyendo matrices lgb.Dataset para los 5 folds...\n")
    folds_datasets <- vector("list", k_folds)

    for (k in 1:k_folds) {
        idx_tr <- which(df_train$fold != k)
        folds_datasets[[k]] <- lgb.Dataset(
            data = mat_train[idx_tr, ],
            label = target_entreno[idx_tr],
            params = list(max_bin = PARAM$max_bin, feature_pre_filter = FALSE),
            free_raw_data = FALSE
        )
    }
    cat("Datasets de 5 folds pre-cargados en C++ exitosamente.\n")

    # 3. Configuración del archivo de salida incremental
    if (!file.exists(archivo_ht)) {
        tb_encabezado <- data.table(
            iteracion = integer(),
            ganancia_max = numeric(),
            envios_optimos = integer(),
            prob_corte = numeric(),
            semilla = integer(),
            gan_c11000 = numeric(),
            num_leaves = integer(),
            min_data_in_leaf = integer(),
            feature_fraction = numeric(),
            learning_rate = numeric(),
            num_iterations = integer(),
            tiempo_seg = numeric()
        )
        fwrite(tb_encabezado, file = archivo_ht)
    }

    # 4. Parámetros de ejecución nocturna
    n_iteraciones <- if (PARAM$modo_ht == "fijos") PARAM$n_semillas_cv else PARAM$n_iteraciones
    mejor_ganancia_global <- -Inf

    cat(sprintf("Iniciando búsqueda de %d iteraciones. Resultados se grabarán en: %s\n\n", n_iteraciones, archivo_ht))

    # 5. Bucle de Optimización Nocturna
    set.seed(333331)

    for (i in 1:n_iteraciones) {
        t_iter_inicio <- Sys.time()

        # Generación de hiperparámetros candidatos (o fijos x semilla)
        if (PARAM$modo_ht == "fijos") {
            p_num_leaves <- PARAM$hp_fijos$num_leaves
            p_min_data_in_leaf <- PARAM$hp_fijos$min_data_in_leaf
            p_feature_fraction <- PARAM$hp_fijos$feature_fraction
            p_learning_rate <- PARAM$hp_fijos$learning_rate
            p_num_iterations <- PARAM$hp_fijos$num_iterations
            p_semilla <- PARAM$semillas[i]
        } else {
            p_num_leaves <- sample(c(16L, 24L, 31L, 48L, 64L, 96L, 128L), 1)
            p_min_data_in_leaf <- sample(c(100L, 150L, 250L, 400L, 600L, 800L), 1)
            p_feature_fraction <- round(runif(1, 0.15, 0.40), 4)
            p_learning_rate <- round(runif(1, 0.015, 0.035), 4)
            p_num_iterations <- sample(c(550L, 650L, 750L, 850L), 1)
            p_semilla <- NA_integer_
        }

        param_lgb <- list(
            objective = "binary",
            metric = "none",
            boosting = "gbdt",
            learning_rate = p_learning_rate,
            num_leaves = p_num_leaves,
            min_data_in_leaf = p_min_data_in_leaf,
            feature_fraction = p_feature_fraction,
            feature_pre_filter = FALSE,
            verbosity = -1,
            num_threads = parallel::detectCores()
        )
        # La semilla de LightGBM solo se fija en modo "fijos" (en "busqueda" se
        # mantiene el comportamiento de exp01/exp02 para que sigan siendo reproducibles)
        if (!is.na(p_semilla)) param_lgb$seed <- p_semilla

        # Vector para recolectar predicciones Out-of-Fold (OOF) completas
        pred_oof <- rep(0.0, nrow(df_train))

        # Entrenamiento y validación sobre los 5 Folds
        for (k in 1:k_folds) {
            idx_val <- which(df_train$fold == k)

            modelo_k <- lgb.train(
                params = param_lgb,
                data = folds_datasets[[k]],
                nrounds = p_num_iterations,
                verbose = -1
            )

            pred_oof[idx_val] <- predict(modelo_k, mat_train[idx_val, ])
        }

        # Evaluación de la ganancia sobre el 100% de las predicciones OOF de 202106
        res_eval <- calcular_ganancia_maxima(pred_oof, target_eval)
        t_iter_fin <- Sys.time()
        duracion_seg <- round(as.numeric(difftime(t_iter_fin, t_iter_inicio, units = "secs")), 1)

        # Registro inmediato en disco (append seguro a prueba de interrupciones)
        fila_resultado <- data.table(
            iteracion = i,
            ganancia_max = res_eval$ganancia,
            envios_optimos = res_eval$envios_optimos,
            prob_corte = round(res_eval$probabilidad_corte, 5),
            semilla = p_semilla,
            gan_c11000 = ganancia_en_corte(pred_oof, target_eval, 11000L),
            num_leaves = p_num_leaves,
            min_data_in_leaf = p_min_data_in_leaf,
            feature_fraction = p_feature_fraction,
            learning_rate = p_learning_rate,
            num_iterations = p_num_iterations,
            tiempo_seg = duracion_seg
        )
        fwrite(fila_resultado, file = archivo_ht, append = TRUE)

        # Monitoreo en consola y log
        if (res_eval$ganancia > mejor_ganancia_global) {
            mejor_ganancia_global <- res_eval$ganancia
            marca_nuevo_max <- "--> NUEVO MÁXIMO!"
        } else {
            marca_nuevo_max <- ""
        }

        cat(sprintf(
            "[Iter %03d/%d - %3.0fs] Ganancia: $ %s | Envíos: %5d | Leaves: %3d | MinData: %4d | FeatFrac: %.3f | LR: %.4f %s\n",
            i, n_iteraciones, duracion_seg,
            format(res_eval$ganancia, big.mark = ".", scientific = FALSE),
            res_eval$envios_optimos, p_num_leaves, p_min_data_in_leaf,
            p_feature_fraction, p_learning_rate, marca_nuevo_max
        ))
    }

    tiempo_ht_fin <- Sys.time()
    cat("\n--- OPTIMIZACIÓN FINALIZADA ---\n")
    cat("Tiempo total de búsqueda:", round(difftime(tiempo_ht_fin, tiempo_ht_inicio, units = "hours"), 2), "horas\n")

    if (PARAM$modo_ht == "fijos") {
        tb_fijos <- fread(archivo_ht)
        cat("\n--- RESUMEN MULTISEMILLA EN CV (202106) ---\n")
        cat(sprintf(
            "Ganancia c11000 -> media: $ %s | SD: $ %s\n",
            format(round(mean(tb_fijos$gan_c11000)), big.mark = "."),
            format(round(sd(tb_fijos$gan_c11000)), big.mark = ".")
        ))
        cat(sprintf(
            "Ganancia maxima -> media: $ %s | SD: $ %s\n",
            format(round(mean(tb_fijos$ganancia_max)), big.mark = "."),
            format(round(sd(tb_fijos$ganancia_max)), big.mark = ".")
        ))
    }
} else {
    cat("\nSalteando bucle HT nocturno: se utilizan las iteraciones ya guardadas en", archivo_ht, "\n")
}

# ============================================================
# 8. SELECCIÓN DE CHAMPION, REENTRENAMIENTO Y FEATURE IMPORTANCE
# ============================================================

cat("\n--- SELECCIÓN DEL MEJOR MODELO Y REENTRENAMIENTO FINAL ---\n")

# 1. Cargar historial de optimización y seleccionar el mejor set
tb_resultados_ht <- fread(archivo_ht)
idx_mejor <- which.max(tb_resultados_ht$ganancia_max)
mejor_registro <- tb_resultados_ht[idx_mejor]

cat("\n=== HIPERPARÁMETROS GANADORES (CHAMPION) ===\n")
cat("Iteración seleccionada:", mejor_registro$iteracion, "\n")
cat("Ganancia estimada en CV: $", format(mejor_registro$ganancia_max, big.mark = ".", scientific = FALSE), "\n")
cat("Corte óptimo de envíos en CV:", mejor_registro$envios_optimos, "clientes\n")
cat("Probabilidad de corte óptimo:", round(mejor_registro$prob_corte, 5), "\n")
cat("num_leaves:", mejor_registro$num_leaves, "\n")
cat("min_data_in_leaf:", mejor_registro$min_data_in_leaf, "\n")
cat("feature_fraction:", mejor_registro$feature_fraction, "\n")
cat("learning_rate:", mejor_registro$learning_rate, "\n")
cat("num_iterations:", mejor_registro$num_iterations, "\n")

# 2. Configurar hiperparámetros finales
param_champion <- list(
    objective = "binary",
    metric = "none",
    boosting = "gbdt",
    learning_rate = mejor_registro$learning_rate,
    num_leaves = mejor_registro$num_leaves,
    min_data_in_leaf = mejor_registro$min_data_in_leaf,
    feature_fraction = mejor_registro$feature_fraction,
    seed = 333331,
    verbosity = -1,
    num_threads = parallel::detectCores()
)

# 3. Reentrenar con el 100% de los datos de foto_mes == 202106
cat("\nReentrenando modelo definitivo con el 100% de los clientes de 202106...\n")
dtrain_final <- lgb.Dataset(
    data = mat_train,
    label = target_entreno,
    params = list(max_bin = PARAM$max_bin),
    free_raw_data = FALSE
)

modelo_champion <- lgb.train(
    params = param_champion,
    data = dtrain_final,
    nrounds = mejor_registro$num_iterations,
    verbose = -1
)
cat("Modelo Champion entrenado exitosamente.\n")

# 4. Feature Importance y Auditoría de Variables
cat("\nExtrayendo Feature Importance del modelo Champion...\n")
tb_importancia <- lgb.importance(modelo_champion)

cat("\nTop 30 variables más importantes del modelo:\n")
print(head(tb_importancia, 30))

# Guardar gráfico de Feature Importance
graf_importancia <- ggplot(head(tb_importancia, 30), aes(x = reorder(Feature, Gain), y = Gain)) +
    geom_col(fill = "steelblue") +
    coord_flip() +
    labs(
        title = "Top 30 Feature Importance - LightGBM Champion",
        subtitle = paste("Ganancia CV: $", format(mejor_registro$ganancia_max, big.mark = ".")),
        x = "Variables",
        y = "Ganancia Relativa (Gain)"
    ) +
    theme_minimal()

ggsave(file.path(dir_exp, "plots/feature_importance_top30.png"),
    plot = graf_importancia, width = 10, height = 8, dpi = 300
)
cat("Gráfico guardado en:", file.path(dir_exp, "plots/feature_importance_top30.png"), "\n")

# ============================================================
# 9. SCORING SOBRE FOTO_MES 202108 (TEST / FUTURO)
# ============================================================

cat("\n--- SCORING DE LA CARTERA A EVALUAR (202108) ---\n")

cat("Construyendo matriz predictora para agosto 2021...\n")
mat_future <- as.matrix(df_future[, ..campos_buenos])

cat("Generando probabilidades con modelo Champion...\n")
pred_prob_future <- predict(modelo_champion, mat_future)

tb_predicciones <- data.table(
    numero_de_cliente = df_future$numero_de_cliente,
    prob = pred_prob_future
)

# Ordenar de mayor a menor probabilidad de ser BAJA+2
setorder(tb_predicciones, -prob)

cat("Scoring completado. Clientes evaluados:", nrow(tb_predicciones), "\n")
cat("Rango de probabilidades asignadas: [", round(min(tb_predicciones$prob), 5), "a", round(max(tb_predicciones$prob), 5), "]\n")

# ============================================================
# 10. GENERACIÓN DE ARCHIVOS DE SUBMIT PARA EL BOT DE ZULIP
# ============================================================

cat("\n--- GENERACIÓN DE ARCHIVOS PARA EL BOT (@competencia-uno) ---\n")

# Identificador unico: experimento + iteracion champion (evita nombres fijos a mano)
id_modelo <- sprintf("%s_it%03d", PARAM$experimento, mejor_registro$iteracion)
corte_elegido <- if (is.na(PARAM$corte_final)) as.integer(mejor_registro$envios_optimos) else PARAM$corte_final

dir.create(file.path(dir_exp, "submits"), showWarnings = FALSE)

# Abanico de cortes estrategicos alrededor del corte elegido
cortes_envios <- sort(unique(c(9500L, 10000L, 10500L, 11000L, 11500L, 12000L, corte_elegido)))

for (corte in cortes_envios) {
    archivo_submit <- file.path(dir_exp, sprintf("submits/%s_c%05d.csv", id_modelo, corte))

    # Exportación con formato estricto para el bot (solo columna de IDs, sin encabezado)
    fwrite(
        tb_predicciones[1:corte, .(numero_de_cliente)],
        file = archivo_submit,
        col.names = FALSE
    )

    prob_minima_corte <- tb_predicciones$prob[corte]
    cat(sprintf(
        "Archivo generado: %s | Envíos: %5d | Prob mínima: %.5f\n",
        archivo_submit, corte, prob_minima_corte
    ))
}

# ============================================================
# 11. MULTI-SEMILLA PARA EL BOT (MEDIA/SD) Y ENSAMBLE FINAL
# ============================================================

cat("\n--- INICIO DE ENTRENAMIENTO MULTI-SEMILLA ---\n")

# 1. Vector de semillas definido en PARAM (CONFIGURACION DEL EXPERIMENTO)
semillas_evaluacion <- PARAM$semillas

dir.create(file.path(dir_exp, "submits_semillas"), showWarnings = FALSE)

# Acumulador de probabilidades para el ensamble promedio
prob_acumulada <- rep(0.0, nrow(mat_future))

dtrain_full <- lgb.Dataset(
    data = mat_train,
    label = target_entreno,
    params = list(max_bin = PARAM$max_bin),
    free_raw_data = FALSE
)

for (idx_s in seq_along(semillas_evaluacion)) {
    semilla_actual <- semillas_evaluacion[idx_s]

    param_semilla <- list(
        objective = "binary",
        metric = "none",
        boosting = "gbdt",
        learning_rate = mejor_registro$learning_rate,
        num_leaves = mejor_registro$num_leaves,
        min_data_in_leaf = mejor_registro$min_data_in_leaf,
        feature_fraction = mejor_registro$feature_fraction,
        seed = semilla_actual,
        verbosity = -1,
        num_threads = parallel::detectCores()
    )

    modelo_s <- lgb.train(
        params = param_semilla,
        data = dtrain_full,
        nrounds = mejor_registro$num_iterations,
        verbose = -1
    )

    pred_s <- predict(modelo_s, mat_future)
    prob_acumulada <- prob_acumulada + pred_s

    # Ordenar y exportar el archivo individual de esta semilla
    tb_pred_s <- data.table(
        numero_de_cliente = df_future$numero_de_cliente,
        prob = pred_s
    )
    setorder(tb_pred_s, -prob)

    archivo_s <- file.path(
        dir_exp,
        sprintf("submits_semillas/%s_c%05d_s%02d_%d.csv", id_modelo, corte_elegido, idx_s, semilla_actual)
    )

    fwrite(
        tb_pred_s[1:corte_elegido, .(numero_de_cliente)],
        file = archivo_s,
        col.names = FALSE
    )

    cat(sprintf("[Semilla %02d/%d - %d] Exportado: %s\n", idx_s, length(semillas_evaluacion), semilla_actual, archivo_s))
}

# 2. Exportar tambien el Ensamble Promedio de las semillas (1 solo archivo para el domingo)
tb_ensamble <- data.table(
    numero_de_cliente = df_future$numero_de_cliente,
    prob = prob_acumulada / length(semillas_evaluacion)
)
setorder(tb_ensamble, -prob)

archivo_ensamble <- file.path(
    dir_exp,
    sprintf("submits/%s_ensamble%d_c%05d.csv", id_modelo, length(semillas_evaluacion), corte_elegido)
)
fwrite(
    tb_ensamble[1:corte_elegido, .(numero_de_cliente)],
    file = archivo_ensamble,
    col.names = FALSE
)

# Probabilidades del ensamble (permite recortar en cualquier corte sin reentrenar)
fwrite(tb_ensamble, file = file.path(dir_exp, "probabilidades_ensamble_202108.csv"))

cat(sprintf(
    "\nArchivo Ensamble Final (%d semillas promediadas) generado en:\n%s\n",
    length(semillas_evaluacion), archivo_ensamble
))

# ============================================================
# CIERRE FORMAL DEL LOG
# ============================================================

tiempo_total_fin <- Sys.time()
cat("\n--- EJECUCIÓN COMPLETA FINALIZADA CON ÉXITO ---\n")
cat("Hora de finalización:", format(tiempo_total_fin, "%Y-%m-%d %H:%M:%S"), "\n")
cat("Tiempo total de script:", round(difftime(tiempo_total_fin, tiempo_fe_inicio, units = "hours"), 2), "horas\n")

while (sink.number() > 0) sink()
closeAllConnections()
cat("Log cerrado correctamente.\n")
