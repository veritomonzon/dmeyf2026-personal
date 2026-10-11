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
# Despues de correr: completar resultados en el HISTORIAL.

PARAM <- list(
    experimento = "exp13_M8_receta472",
    modelo = "M8", # sin prestamos personales + lag1/delta1
    etapa = "produccion", # "testeo" = HP + 10 semillas en 202106 | "produccion" = n_semillas_prod en 202108 (usar modo_ht = "ninguno")
    maquina = "Mac", # Mac | VM | PC2 (queda en el registro)
    target = "baja12", # "baja2" = BAJA+2 vs resto | "baja12" = BAJA+1 + BAJA+2 vs CONTINUA
    max_bin = 31L, # 255 = default LightGBM | 31 = discretizacion gruesa (regulariza)
    undersampling = 1.0, # 1.0 = sin undersampling de CONTINUA
    train_bo = c(202103L, 202104L), # BO y testeo: entrena en 03+04 (deja 05 de gap)
    val_bo = 202106L, # BO y testeo: valida / testea en 06
    train_final = c(202103L, 202104L, 202105L, 202106L), # Produccion: entrena en 03..06
    future = 202108L, # Produccion: predice 08
    modo_ht = "ninguno", # reutiliza HT_resultados.csv de exp13
    bo_iteraciones = 50L, # no se usa en modo "fijos"
    excluir_dudosos = TRUE, # modelo auxiliar en el 30% + eliminar CONTINUA con prob30 > umbral
    umbral_dudosos = 0.5,
    hp_dudosos = list(num_iterations = 2180L, num_leaves = 30L, min_sum_hessian_in_leaf = 0.1141634103), # modelo auxiliar (Zulip)
    lgbm_fijos = list(learning_rate = 0.005, feature_fraction = 0.5, feature_fraction_bynode = 0.2, min_data_in_leaf = 0L),
    hp_fijos = list(
        num_leaves = 44L, min_data_in_leaf = 0L, min_sum_hessian_in_leaf = 0.0068328532,
        feature_fraction = 0.5, learning_rate = 0.005, num_iterations = 1920L
    ),
    bo_bordes = list(
        num_iterations = c(64L, 4096L),
        num_leaves = c(16L, 2048L),
        min_sum_hessian_in_leaf = c(1e-06, 0.1)
    ),
    n_semillas_test = 10L, # mismas 10 semillas en todos los modelos (Wilcoxon pareado)
    n_semillas_prod = 50L,
    guardar_submits_individuales = FALSE, # FALSE evita escribir CSVs sueltos por semilla en iCloud
    semillas = c(
        333331L, 444443L, 555557L, 666667L, 121313L,
        111119L, 333337L, 444449L, 888887L, 999983L,
        991313L, 991717L, 981919L, 979717L, 989797L,
        994949L, 995959L, 996161L, 998989L, 987979L
    ),
    corte_final = 11000L, # Corte principal para checkpoints y archivos individuales
    cortes_grilla = c(9000L, 9500L, 10000L, 10500L, 11000L, 11500L, 12000L, 12500L, 13000L, 13500L, 14000L) # Grilla de cortes para el ensamble
)

# Completar automáticamente de 20 al maximo entre n_semillas_test y n_semillas_prod con primos de 6 dígitos reproducibles
n_semillas_total <- max(PARAM$n_semillas_test, PARAM$n_semillas_prod)
if (length(PARAM$semillas) < n_semillas_total) {
    es_primo <- rep(TRUE, 999999L)
    es_primo[1L] <- FALSE
    for (i in 2L:999L) {
        if (es_primo[i]) es_primo[seq.int(i * i, 999999L, by = i)] <- FALSE
    }
    primos_extra <- setdiff(which(es_primo & seq_along(es_primo) >= 100000L), PARAM$semillas)
    set.seed(PARAM$semillas[1L])
    PARAM$semillas <- c(PARAM$semillas, sample(primos_extra, n_semillas_total - length(PARAM$semillas)))
    rm(es_primo, primos_extra, i)
}

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
# exp03c_baja12_bin31 | Mac | baja12 | max_bin 31  | fijos champion exp01 x 5 sem | 12 min
#   CV 202106: gan_c11000 489.720.000 +- 3.336.465 | gan_max 494.439.000 +- 1.471.520
#   vs exp03b: +17,8 M en c11000, mejora en las 5 semillas (t apareado p ~ 0,006)
#   Public: 10 sem 102,84 +- 1,75 (c11000) -> SUBMIT FINAL
#   Public 09-oct: champion it004 c11000 (1 archivo, modelo unico) 103,18
#     ID 1542-1791541200393478 | nombre "exp03c-it004-ens10-c11000-final" (no es el ensamble)
# exp03d_baja12_bin31_c12000 | Mac | = exp03c, modo ninguno, corte 12.000 | 4 min
#   Public: 10 sem 101,14 +- 2,70 (vs exp03c c11000 102,84 +- 1,75) -> se mantiene corte 11.000
# exp04a_baja12_bin31_busqueda | Mac | baja12 | max_bin 31 | busqueda 200 iters | 7,6 h
#   Rangos: leaves {8..64}, min_data {400..2000}, ff [0.15, 0.50], lr [0.010, 0.035], iters {450..1000}
#   (exp01/exp02 usaron: leaves {16..128}, min_data {100..800}, ff [0.15, 0.40], lr [0.015, 0.035], iters {550..850})
#   champion it104: leaves 31, min_data 2000, ff 0.4063, lr 0.0307, iters 550
#   CV 202106: $514.470.000 (corte 10.132) -> max de 200 corridas de 1 semilla, optimista
#   Public 09-oct: champion it104 c11000 (1 archivo, modelo unico) 101,37
#     ID 1542-1791541156021276 | enviado por error con nombre "exp03c-it004-ens10-c11000-final"
#   vs exp03c (103,18 / 10 sem 102,84 +- 1,75): no mejora -> se descarta, se mantiene exp03c
#   Top 11.000 comparte 9.962 clientes con exp03c (Spearman probs 0,94)
# exp05_clase8_bo3hp_100sem | Mac | baja12 | max_bin 31 | BO mlrMBO 3 HPs (50 iters) + 100 sem | 12,5 h
#   Flujo: BO train 202103+202104 (gap 202105), val 202106 (ganancia suavizada +-250)
#   Produccion: train 202103..202106, ensamble promedio 100 semillas sobre 202108
#   Fijos: lr 0.01, ff 0.5, min_data 0 | Bordes: iters {64..4096}, leaves {16..2048}, hessian [1e-6, 0.1]
#   champion it31: iters 685, leaves 849, hessian 0.0913 (cerca del borde 0.1)
#   Val 202106 (1 semilla): suavizada $408.838.822 en 11.660 | c11000 $403.700.000 | meseta ~9.700-14.500
#   Public: ens20sem c11000 99,50 | SUBMIT ENTREGA SEGURA: ens100sem c11500
# --- FLUJO VIGENTE (09-oct): testeo en 202106 con 10 semillas, fijos lr 0.005 / ff 0.5 / ff_bynode 0.2 ---
# exp06_M1_lagsdeltas | Mac | M1 | testeo 202106: ensamble 407,4 M (12.527 env) | semillas 408,1 +- 5,7 | c11000 404,8 M | 7,9 h
# exp07_M2_ranking_negocio | Mac | M2: ranking cero fijo + flags/totalizadores/ratios, sin lags | testeo 202106: ensamble 440,6 M (14.512 env) | semillas 426,1 +- 5,4 | c11000 413,9 M | 3,2 h
#   Produccion 50 sem (1,1 h) | Public ens50sem c13500 90,86 -> entrega segura hasta el envio de M8
# exp08_M3_ranking_lags    | PC2 | M3: ranking cero fijo -> lags/deltas sobre rankeados         | testeo 202106: ensamble 385,0 M (12.311 env) | semillas 385,1 +- 4,9 | c11000 379,5 M
# exp09_M4_lags_negocio    | VM  | M4: M1 + flags/totalizadores/ratios (= FE de exp05)          | testeo 202106: ensamble 417,3 M (13.502 env) | semillas 413,9 +- 3,4 | c11000 404,8 M
# exp10_M5_lags_ranking    | VM  | M5: lags/deltas -> ranking cero fijo sobre todo              | testeo 202106: ensamble 405,9 M (10.327 env) | semillas 404,9 +- 3,1 | c11000 403,7 M
# exp11_M1_hp_gustavo      | PC2 | M1 + HP fijos: leaves 44, hessian 0.00683, iters 1920, lr 0.005, ff 0.5, sin bynode | testeo 202106: ensamble 378,6 M (14.380 env) | semillas 379,0 +- 4,4 | c11000 368,5 M
#   En comparacion_modelos.R figura como M6. Diagnostico: con el FE de M1, estos HP no alcanzan
# exp12_M7_lags_tend_zero  | ?   | M7: M1 + flags _zero + tend3/avg3 (En Limpio 1.3 y 1.4)    | NO SE CORRIO
# exp13_M8_receta472M | Mac | M8: sin prestamos + lag1/delta1 + exclusion dudosos (prob30 > 0.5) + HP (leaves 44, hessian 0.00683, iters 1920, ff_bynode 0.2), sin undersampling | testeo 202106: ensamble 468,0 M (12.829 env) | semillas 463,4 +- 2,5 | 0,39 h
#   comp02_M1_a_M8: mejor modelo, supera a M2 en las 10 semillas (Wilcoxon, p Holm 0,042); ningun ensamble de a pares lo mejora
#   Produccion 50 sem (1,9 h, 195 dudosos excluidos) | Public ens50sem c13000 93,78 -> SUBMIT FINAL (11-oct)

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
library(DiceKriging)
library(mlrMBO)
library(Rcpp)

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

archivo_rds_fe <- file.path(dir_base, sprintf("fe_%s.rds", PARAM$modelo)) # un cache por variante de preprocesamiento

if (!file.exists(archivo_rds_fe)) {
    archivo_dataset <- file.path(dir_base, "competencia_01.csv.gz")
    if (!file.exists(archivo_dataset)) stop("No se encuentra competencia_01.csv.gz en ", dir_base)
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
    # 4. ETL: DATA QUALITY
    # ============================================================

    cat("\n--- DATA QUALITY ---\n")
    # ccajas_depositos esta rota en 202105 (todo cero): NA antes de lags y deltas
    n_corregidos <- dataset[foto_mes == 202105, sum(ccajas_depositos == 0, na.rm = TRUE)]
    dataset[foto_mes == 202105, ccajas_depositos := NA_real_]
    cat(sprintf("ccajas_depositos en 202105: %d registros recodificados a NA\n", n_corregidos))

    # ============================================================
    # 5. FUNCIONES DE PREPROCESAMIENTO
    # ============================================================

    division_segura <- function(num, den, epsilon = 1.0) {
        res <- num / pmax(den, epsilon)
        res[is.infinite(res)] <- NA_real_
        res
    }

    # Flags de tenencia, totalizadores Visa+Master y ratios intra-mes (M2, M4)
    agregar_variables_negocio <- function(dt) {
        dt[, flag_visa := as.integer(!is.na(Visa_status))]
        dt[, flag_master := as.integer(!is.na(Master_status))]
        dt[, flag_tarjetas := as.integer(flag_visa == 1L | flag_master == 1L)]
        dt[, flag_payroll := as.integer(fcoalesce(mpayroll, 0) > 0)]
        dt[, tarjetas_mconsumototal := fcoalesce(Visa_mconsumototal, 0) + fcoalesce(Master_mconsumototal, 0)]
        dt[, tarjetas_msaldototal := fcoalesce(Visa_msaldototal, 0) + fcoalesce(Master_msaldototal, 0)]
        dt[, tarjetas_mlimitecompra := fcoalesce(Visa_mlimitecompra, 0) + fcoalesce(Master_mlimitecompra, 0)]
        dt[, tarjetas_cconsumos := fcoalesce(Visa_cconsumos, 0L) + fcoalesce(Master_cconsumos, 0L)]
        dt[, tarjetas_madelantopesos := fcoalesce(Visa_madelantopesos, 0) + fcoalesce(Master_madelantopesos, 0)]
        dt[, ratio_tarjeta_utilizacion := division_segura(tarjetas_msaldototal, tarjetas_mlimitecompra)]
        dt[, ratio_tarjeta_consumo_limite := division_segura(tarjetas_mconsumototal, tarjetas_mlimitecompra)]
        dt[, ratio_consumo_sobre_saldo := division_segura(tarjetas_mconsumototal, mcuentas_saldo)]
        dt[, ratio_payroll_sobre_saldo := division_segura(mpayroll, mcuentas_saldo)]
        invisible(dt)
    }

    # Ratios longitudinales de retencion: mes actual vs lag 1 (M4, requiere lags)
    agregar_ratios_longitudinales <- function(dt) {
        dt[, ratio_retencion_saldo_mcuentas := fifelse(
            mcuentas_saldo_lag1 > 0 & mcuentas_saldo >= 0,
            division_segura(mcuentas_saldo, mcuentas_saldo_lag1), NA_real_
        )]
        dt[, ratio_retencion_saldo_tarjetas := fifelse(
            tarjetas_msaldototal_lag1 > 0 & tarjetas_msaldototal >= 0,
            division_segura(tarjetas_msaldototal, tarjetas_msaldototal_lag1), NA_real_
        )]
        dt[, ratio_retencion_consumo_tarjetas := fifelse(
            tarjetas_mconsumototal_lag1 > 0 & tarjetas_mconsumototal >= 0,
            division_segura(tarjetas_mconsumototal, tarjetas_mconsumototal_lag1), NA_real_
        )]
        invisible(dt)
    }

    # Lags y deltas de orden 1 y 2 por cliente (M1, M3, M4, M5)
    agregar_lags_deltas <- function(dt, cols) {
        setorder(dt, numero_de_cliente, foto_mes)
        dt[, paste0(cols, "_lag1") := shift(.SD, n = 1L, type = "lag"), by = numero_de_cliente, .SDcols = cols]
        dt[, paste0(cols, "_lag2") := shift(.SD, n = 2L, type = "lag"), by = numero_de_cliente, .SDcols = cols]
        for (v in cols) {
            dt[, paste0(v, "_delta1") := get(v) - get(paste0(v, "_lag1"))]
            dt[, paste0(v, "_delta2") := get(v) - get(paste0(v, "_lag2"))]
        }
        invisible(dt)
    }

    # Ranking de cero fijo por foto_mes (M2, M3, M5): 0 -> 0, NA -> NA, positivos (0, 1], negativos [-1, 0)
    rankear_cero_fijo <- function(dt, cols) {
        for (v in cols) {
            dt[, (v) := as.numeric(get(v))] # evita truncar a entero al asignar el ranking por grupo
            dt[, (v) := {
                x <- get(v)
                r <- x
                pos <- which(x > 0)
                neg <- which(x < 0)
                if (length(pos) > 0) r[pos] <- frank(x[pos], ties.method = "average") / length(pos)
                if (length(neg) > 0) r[neg] <- -frank(-x[neg], ties.method = "average") / length(neg)
                r
            }, by = foto_mes]
        }
        invisible(dt)
    }

    # Flags _zero: 1 si la variable vale 0, NA si es NA, 0 en el resto. No entran al ranking
    agregar_flags_zero <- function(dt, cols) {
        for (v in cols) {
            x <- dt[[v]]
            if (!any(x == 0, na.rm = TRUE)) next # solo variables que alguna vez valen cero
            if (all(x %in% c(0, 1, NA))) next # binarias 0/1: el flag repetiria la variable
            set(dt, j = paste0(v, "_zero"), value = fifelse(is.na(x), NA_integer_, as.integer(x == 0)))
        }
        invisible(dt)
    }

    # Tendencia, minimo, maximo y promedio de los ultimos n meses
    # La tendencia es la pendiente de la recta de cuadrados minimos; fhistC esta escrita en C++ por velocidad
    cppFunction("NumericVector fhistC(NumericVector pcolumna, IntegerVector pdesde )
    {
      double  x[100] ;
      double  y[100] ;

      int n = pcolumna.size();
      NumericVector out( 5*n );

      for(int i = 0; i < n; i++)
      {
        if( pdesde[i]-1 < i )  out[ i + 4*n ]  =  pcolumna[i-1] ;
        else                   out[ i + 4*n ]  =  NA_REAL ;

        int  libre    = 0 ;
        int  xvalor   = 1 ;

        for( int j= pdesde[i]-1;  j<=i; j++ )
        {
           double a = pcolumna[j] ;

           if( !R_IsNA( a ) )
           {
              y[ libre ]= a ;
              x[ libre ]= xvalor ;
              libre++ ;
           }

           xvalor++ ;
        }

        if( libre > 1 )
        {
          double  xsum  = x[0] ;
          double  ysum  = y[0] ;
          double  xysum = xsum * ysum ;
          double  xxsum = xsum * xsum ;
          double  vmin  = y[0] ;
          double  vmax  = y[0] ;

          for( int h=1; h<libre; h++)
          {
            xsum  += x[h] ;
            ysum  += y[h] ;
            xysum += x[h]*y[h] ;
            xxsum += x[h]*x[h] ;

            if( y[h] < vmin )  vmin = y[h] ;
            if( y[h] > vmax )  vmax = y[h] ;
          }

          out[ i ]  =  (libre*xysum - xsum*ysum)/(libre*xxsum -xsum*xsum) ;
          out[ i + n ]    =  vmin ;
          out[ i + 2*n ]  =  vmax ;
          out[ i + 3*n ]  =  ysum / libre ;
        }
        else
        {
          out[ i       ]  =  NA_REAL ;
          out[ i + n   ]  =  NA_REAL ;
          out[ i + 2*n ]  =  NA_REAL ;
          out[ i + 3*n ]  =  NA_REAL ;
        }
      }

      return  out;
    }")

    TendenciaYmuchomas <- function(dataset, cols, ventana = 6, tendencia = TRUE,
                                   minimo = TRUE, maximo = TRUE, promedio = TRUE,
                                   ratioavg = FALSE, ratiomax = FALSE) {
        gc(verbose = FALSE)
        ventana_regresion <- ventana
        last <- nrow(dataset)

        # vector_desde: fila donde empieza la ventana de cada registro (se corta al cambiar de cliente)
        vector_ids <- dataset[, numero_de_cliente]
        vector_desde <- seq(-ventana_regresion + 2, nrow(dataset) - ventana_regresion + 1)
        vector_desde[1:ventana_regresion] <- 1
        for (i in 2:last) {
            if (vector_ids[i - 1] != vector_ids[i]) vector_desde[i] <- i
        }
        for (i in 2:last) {
            if (vector_desde[i] < vector_desde[i - 1]) vector_desde[i] <- vector_desde[i - 1]
        }

        for (campo in cols) {
            nueva_col <- fhistC(dataset[, get(campo)], vector_desde)
            if (tendencia) dataset[, paste0(campo, "_tend", ventana) := nueva_col[(0 * last + 1):(1 * last)]]
            if (minimo) dataset[, paste0(campo, "_min", ventana) := nueva_col[(1 * last + 1):(2 * last)]]
            if (maximo) dataset[, paste0(campo, "_max", ventana) := nueva_col[(2 * last + 1):(3 * last)]]
            if (promedio) dataset[, paste0(campo, "_avg", ventana) := nueva_col[(3 * last + 1):(4 * last)]]
            if (ratioavg) dataset[, paste0(campo, "_ratioavg", ventana) := get(campo) / nueva_col[(3 * last + 1):(4 * last)]]
            if (ratiomax) dataset[, paste0(campo, "_ratiomax", ventana) := get(campo) / nueva_col[(2 * last + 1):(3 * last)]]
        }
    }

    # ============================================================
    # 6. PREPROCESAMIENTO SEGUN MODELO (M1 A M5)
    # ============================================================

    cat("\n--- PREPROCESAMIENTO", PARAM$modelo, "---\n")
    tiempo_fe_inicio <- Sys.time()

    cols_excluir <- c("numero_de_cliente", "foto_mes", "clase_ternaria")
    cols_originales <- setdiff(names(dataset)[sapply(dataset, is.numeric)], cols_excluir)

    if (PARAM$modelo == "M1") { # originales + lags/deltas
        agregar_lags_deltas(dataset, cols_originales)
    }

    if (PARAM$modelo == "M2") { # ranking cero fijo + variables de negocio, sin lags
        agregar_variables_negocio(dataset)
        cols_rank <- setdiff(
            names(dataset)[sapply(dataset, is.numeric)],
            c(cols_excluir, grep("^flag_", names(dataset), value = TRUE))
        )
        rankear_cero_fijo(dataset, cols_rank)
    }

    if (PARAM$modelo == "M3") { # primero ranking, despues historia sobre los rankeados
        rankear_cero_fijo(dataset, cols_originales)
        agregar_lags_deltas(dataset, cols_originales)
    }

    if (PARAM$modelo == "M4") { # M1 + variables de negocio (= preprocesamiento de exp05)
        agregar_variables_negocio(dataset)
        cols_m4 <- setdiff(names(dataset)[sapply(dataset, is.numeric)], cols_excluir)
        agregar_lags_deltas(dataset, cols_m4)
        agregar_ratios_longitudinales(dataset)
    }

    if (PARAM$modelo == "M5") { # primero historia, despues ranking sobre todo
        agregar_lags_deltas(dataset, cols_originales)
        cols_rank <- setdiff(names(dataset)[sapply(dataset, is.numeric)], cols_excluir)
        rankear_cero_fijo(dataset, cols_rank)
    }

    if (PARAM$modelo == "M7") { # M1 + flags _zero + tendencia y promedio de 3 meses
        agregar_flags_zero(dataset, cols_originales) # sobre originales, antes de crear la historia
        agregar_lags_deltas(dataset, cols_originales)
        setorderv(dataset, c("numero_de_cliente", "foto_mes")) # fhistC necesita filas ordenadas por cliente y mes
        TendenciaYmuchomas(dataset,
            cols = cols_originales, ventana = 3,
            tendencia = TRUE, minimo = FALSE, maximo = FALSE, promedio = TRUE,
            ratioavg = FALSE, ratiomax = FALSE
        )
    }

    if (PARAM$modelo == "M8") { # sin prestamos personales + lag1 y delta1
        cols_prestamos <- c("cprestamos_personales", "mprestamos_personales")
        dataset[, (cols_prestamos) := NULL]
        cols_m8 <- setdiff(cols_originales, cols_prestamos)
        setorder(dataset, numero_de_cliente, foto_mes)
        dataset[, paste0(cols_m8, "_lag1") := shift(.SD, n = 1L, type = "lag"), by = numero_de_cliente, .SDcols = cols_m8]
        for (v in cols_m8) set(dataset, j = paste0(v, "_delta1"), value = dataset[[v]] - dataset[[paste0(v, "_lag1")]])
    }


    cat("Tiempo de preprocesamiento:", round(difftime(Sys.time(), tiempo_fe_inicio, units = "mins"), 2), "minutos\n")
    cat("Dimensiones finales:", nrow(dataset), "filas x", ncol(dataset), "columnas\n")
    cat("Memoria RAM del dataset:", round(as.numeric(object.size(dataset)) / (1024^3), 2), "GB\n")
    cat("\n--- FIN PREPROCESAMIENTO ---\n\n")

    # ============================================================
    # 6. PARTICIONES TEMPORALES Y FUNCIÓN GANANCIA
    # ============================================================

    cat("\n--- PREPARACIÓN DE PARTICIONES TEMPORALES ---\n")

    # 1. Definición de campos predictores (excluyendo identificadores y metas)
    cols_excluir_modelo <- c("numero_de_cliente", "foto_mes", "clase_ternaria", "clase01", "target_binario")
    campos_buenos <- setdiff(names(dataset), cols_excluir_modelo)
    cat("Cantidad de features predictoras finales:", length(campos_buenos), "\n")

    # 2. Partición Histórica con Clase Completa (202103, 202104, 202105, 202106)
    meses_hist <- sort(unique(c(PARAM$train_bo, PARAM$val_bo, PARAM$train_final)))
    cat("Guardando meses históricos con clase completa:", paste(meses_hist, collapse = ", "), "\n")
    df_train <- dataset[
        foto_mes %in% meses_hist,
        c("numero_de_cliente", "foto_mes", "clase_ternaria", campos_buenos),
        with = FALSE
    ]
    df_train[, clase01 := fifelse(clase_ternaria == "BAJA+2", 1L, 0L)]

    # 3. Partición Futuro / Scoring (foto_mes == 202108)
    cat("Generando partición de evaluación futura (", PARAM$future, ")...\n", sep = "")
    df_future <- dataset[
        foto_mes == PARAM$future,
        c("numero_de_cliente", "foto_mes", campos_buenos),
        with = FALSE
    ]

    # 4. Liberación de memoria eliminando el dataset completo (incluyendo 202107)
    cat("Liberando memoria RAM del dataset crudo...\n")
    rm(dataset)
    invisible(gc())

    cat("Distribución de clase_ternaria por mes en df_train:\n")
    print(dcast(df_train, foto_mes ~ clase_ternaria, fun.aggregate = length, value.var = "numero_de_cliente"))

    # Guardar para no volver a correr el FE en próximas corridas de Opción 1
    cat("\nGuardando particiones en:", archivo_rds_fe, "\n")
    saveRDS(
        list(df_train = df_train, df_future = df_future, campos_buenos = campos_buenos),
        file = archivo_rds_fe
    )
} else {
    cat("\n--- CARGANDO PARTICIONES DESDE DISCO (.RDS) ---\n")
    objs <- readRDS(archivo_rds_fe)
    df_train <- objs$df_train
    df_future <- objs$df_future
    campos_buenos <- objs$campos_buenos
    rm(objs)
    invisible(gc())
    cat("Particiones cargadas en memoria en segundos.\n")
}

if (!exists("tiempo_fe_inicio")) tiempo_fe_inicio <- Sys.time()

# ============================================================
# TARGET DE ENTRENAMIENTO Y FUNCIONES DE EVALUACIÓN EN 202106
# ============================================================
# La ganancia se evalúa SIEMPRE con BAJA+2 real (clase01);
# LightGBM entrena con target_binario (POS = {BAJA+1, BAJA+2} si target == "baja12").
df_train[, clase01 := fifelse(clase_ternaria == "BAJA+2", 1L, 0L)]
df_train[, target_binario := if (PARAM$target == "baja12") {
    as.integer(clase_ternaria %in% c("BAJA+1", "BAJA+2"))
} else {
    clase01
}]

cat("Resumen de particiones activas:\n")
cat("  - Train BO (", paste(PARAM$train_bo, collapse = "+"), "): ",
    nrow(df_train[foto_mes %in% PARAM$train_bo]), " filas | POS = ",
    sum(df_train[foto_mes %in% PARAM$train_bo, target_binario]), "\n",
    sep = ""
)
cat("  - Val BO   (", PARAM$val_bo, "): ",
    nrow(df_train[foto_mes == PARAM$val_bo]), " filas | BAJA+2 reales = ",
    sum(df_train[foto_mes == PARAM$val_bo, clase01]), "\n",
    sep = ""
)
cat("  - Train Final Producción (", paste(PARAM$train_final, collapse = "+"), "): ",
    nrow(df_train[foto_mes %in% PARAM$train_final]), " filas | POS = ",
    sum(df_train[foto_mes %in% PARAM$train_final, target_binario]), "\n",
    sep = ""
)
cat("  - Future Scoring (", PARAM$future, "): ", nrow(df_future), " filas\n", sep = "")

# Función de evaluación integral sobre el mes de validación (202106):
# Devuelve ganancia suavizada (ventana centrada de 501 envíos = +-250),
# ganancia máxima cruda, corte óptimo, ganancia en corte fijo (11.000) y AUC.
evaluar_validacion <- function(probs, target_baja2_real, corte_fijo = PARAM$corte_final) {
    dt_eval <- data.table(p = probs, y = target_baja2_real)
    setorder(dt_eval, -p)

    dt_eval[, ganancia_acum := cumsum(fifelse(y == 1L, 1072500, -27500))]
    dt_eval[, ganancia_suave := frollmean(ganancia_acum, n = 501L, align = "center", na.rm = TRUE)]

    idx_suave <- which.max(dt_eval$ganancia_suave)
    gan_suave_max <- dt_eval$ganancia_suave[idx_suave]
    envios_opt_suave <- idx_suave
    prob_corte_suave <- dt_eval$p[idx_suave]

    idx_crudo <- which.max(dt_eval$ganancia_acum)
    gan_cruda_max <- dt_eval$ganancia_acum[idx_crudo]

    gan_corte_fijo <- dt_eval$ganancia_acum[corte_fijo]

    # Cálculo rápido de AUC por Mann-Whitney (rangos)
    r <- frank(dt_eval$p, ties.method = "average")
    n_pos <- as.numeric(sum(dt_eval$y == 1L))
    n_neg <- as.numeric(sum(dt_eval$y == 0L))
    auc_val <- (sum(r[dt_eval$y == 1L]) - n_pos * (n_pos + 1) / 2) / (n_pos * n_neg)

    return(list(
        ganancia_suavizada = gan_suave_max,
        ganancia_max       = gan_cruda_max,
        envios_optimos     = envios_opt_suave,
        prob_corte         = prob_corte_suave,
        gan_c11000         = gan_corte_fijo,
        auc                = auc_val
    ))
}

cat("Particiones temporales y función de ganancia suavizada listas.\n")

# ============================================================
# 7. OPTIMIZACIÓN BAYESIANA DE HIPERPARÁMETROS (3 HPs)
# ============================================================
# Desarrollo: Entrena en 202103 + 202104 (gap = 202105) y valida en 202106
# Maximiza Ganancia Suavizada (ventana centrada de 501 envíos = +-250)

archivo_ht <- file.path(dir_exp, "HT_resultados.csv")
archivo_bo <- file.path(dir_exp, "bayesiana.RDATA")
archivo_log <- file.path(dir_exp, "BO_log.txt")
archivo_pred_val <- file.path(dir_exp, "predicciones_val_202106_champion.csv")

idx_bo_val <- which(df_train$foto_mes == PARAM$val_bo)
target_val_baja2 <- df_train$clase01[idx_bo_val]
clase_ternaria_val <- df_train$clase_ternaria[idx_bo_val]

# Exclusion de registros dudosos: un modelo auxiliar entrenado en el 30% de los meses de entrenamiento
# puntua el 70% restante; se eliminan los CONTINUA con prob30 > umbral_dudosos y el modelo final entrena
# solo con ese 70% (aplicando PARAM$undersampling; 1.0 = sin undersampling). La particion es fija
# (primera semilla) para que todas las semillas usen los mismos datos.

filtrar_dudosos <- function(idx) {
    dt_idx <- data.table(idx = idx, clase = df_train$clase_ternaria[idx], mes = df_train$foto_mes[idx])
    set.seed(PARAM$semillas[1], kind = "L'Ecuyer-CMRG")
    dt_idx[, fold := sample(rep(c(rep(1L, 7L), rep(2L, 3L)), length.out = .N)), by = .(mes, clase)] # 70 / 30 estratificado
    dt_idx[, azar := runif(.N)]
    dt_idx[, en_muestra := clase != "CONTINUA" | azar <= PARAM$undersampling]

    idx30 <- dt_idx[fold == 2L & en_muestra == TRUE, idx]
    dtrain30 <- lgb.Dataset(
        data = data.matrix(df_train[idx30, campos_buenos, with = FALSE]),
        label = df_train$target_binario[idx30],
        params = list(max_bin = PARAM$max_bin, feature_pre_filter = FALSE)
    )
    param30 <- list(
        objective = "binary", metric = "none", boosting = "gbdt", boost_from_average = TRUE,
        feature_pre_filter = FALSE, force_row_wise = TRUE, verbosity = -100L, max_depth = -1L,
        min_gain_to_split = 0.0, lambda_l1 = 0.0, lambda_l2 = 0.0, max_bin = PARAM$max_bin,
        min_data_in_leaf = 0L, feature_fraction = 0.5, learning_rate = 0.005,
        num_leaves = as.integer(PARAM$hp_dudosos$num_leaves),
        min_sum_hessian_in_leaf = as.numeric(PARAM$hp_dudosos$min_sum_hessian_in_leaf),
        seed = PARAM$semillas[1], num_threads = parallel::detectCores()
    )
    modelo30 <- lgb.train(params = param30, data = dtrain30, nrounds = as.integer(PARAM$hp_dudosos$num_iterations), verbose = -100)

    idx70 <- dt_idx[fold == 1L, idx]
    prob30 <- predict(modelo30, data.matrix(df_train[idx70, campos_buenos, with = FALSE]))
    dudoso <- df_train$clase_ternaria[idx70] == "CONTINUA" & prob30 > PARAM$umbral_dudosos
    cat(sprintf(
        "Exclusion de dudosos (%s): %d CONTINUA eliminados de %d registros del 70%%\n",
        paste(sort(unique(dt_idx$mes)), collapse = "+"), sum(dudoso), length(idx70)
    ))

    idx70 <- idx70[!dudoso]
    idx70[dt_idx[match(idx70, idx), en_muestra]] # undersampling de CONTINUA sobre el 70% filtrado
}

correr_ht <- PARAM$modo_ht != "ninguno"

if (correr_ht) {
    cat("\n--- INICIO DE OPTIMIZACIÓN DE HIPERPARÁMETROS (MODO:", PARAM$modo_ht, ") ---\n")
    tiempo_ht_inicio <- Sys.time()

    # 1. Filtrar mes(es) de entrenamiento de la BO (202103 + 202104) y eventual undersampling
    set.seed(PARAM$semillas[1])
    idx_bo_train <- which(
        df_train$foto_mes %in% PARAM$train_bo &
            (df_train$clase_ternaria %in% c("BAJA+1", "BAJA+2") | runif(nrow(df_train)) <= PARAM$undersampling)
    )
    if (isTRUE(PARAM$excluir_dudosos)) idx_bo_train <- filtrar_dudosos(which(df_train$foto_mes %in% PARAM$train_bo))

    cat(sprintf(
        "Construyendo dtrain_bo (%s: %d filas) y mat_val_bo (%s: %d filas)...\n",
        paste(PARAM$train_bo, collapse = "+"), length(idx_bo_train),
        PARAM$val_bo, length(idx_bo_val)
    ))

    dtrain_bo <- lgb.Dataset(
        data = data.matrix(df_train[idx_bo_train, ..campos_buenos]),
        label = df_train$target_binario[idx_bo_train],
        params = list(max_bin = PARAM$max_bin, feature_pre_filter = FALSE),
        free_raw_data = FALSE
    )
    # Pre-construir el lgb.Dataset en C++ una sola vez antes de arrancar la BO
    lgb.Dataset.construct(dtrain_bo)

    mat_val_bo <- data.matrix(df_train[idx_bo_val, ..campos_buenos])

    # 2. Inicializar archivo incremental HT_resultados.csv
    GLOBAL_iteracion <- 0L
    GLOBAL_mejor_gan <- -Inf

    if (file.exists(archivo_ht)) {
        tb_prev <- fread(archivo_ht)
        if (nrow(tb_prev) > 0) {
            GLOBAL_iteracion <- nrow(tb_prev)
            GLOBAL_mejor_gan <- max(tb_prev$ganancia_suavizada, na.rm = TRUE)
        }
        rm(tb_prev)
    } else {
        tb_encabezado <- data.table(
            iteracion               = integer(),
            ganancia_suavizada      = numeric(),
            ganancia_max            = numeric(),
            gan_c11000              = numeric(),
            auc                     = numeric(),
            envios_optimos          = integer(),
            prob_corte              = numeric(),
            semilla                 = integer(),
            num_iterations          = integer(),
            num_leaves              = integer(),
            min_sum_hessian_in_leaf = numeric(),
            min_data_in_leaf        = integer(),
            feature_fraction        = numeric(),
            learning_rate           = numeric(),
            tiempo_seg              = numeric()
        )
        fwrite(tb_encabezado, file = archivo_ht)
    }

    # 3. Función objetivo para evaluar un set de hiperparámetros en 202106
    EstimarGanancia_lightgbm <- function(x) {
        t_iter_inicio <- Sys.time()
        GLOBAL_iteracion <<- GLOBAL_iteracion + 1L

        p_num_iterations <- as.integer(x$num_iterations)
        p_num_leaves <- as.integer(x$num_leaves)
        p_min_sum_hessian_in_leaf <- as.numeric(x$min_sum_hessian_in_leaf)
        p_min_data_in_leaf <- as.integer(PARAM$lgbm_fijos$min_data_in_leaf)
        p_feature_fraction <- as.numeric(PARAM$lgbm_fijos$feature_fraction)
        p_learning_rate <- as.numeric(PARAM$lgbm_fijos$learning_rate)
        p_semilla <- if (!is.null(x$seed)) as.integer(x$seed) else PARAM$semillas[1]

        param_lgb <- list(
            objective               = "binary",
            metric                  = "none",
            boosting                = "gbdt",
            first_metric_only       = TRUE,
            boost_from_average      = TRUE,
            feature_pre_filter      = FALSE,
            force_row_wise          = TRUE,
            verbosity               = -100L,
            max_depth               = -1L,
            min_gain_to_split       = 0.0,
            lambda_l1               = 0.0,
            lambda_l2               = 0.0,
            max_bin                 = PARAM$max_bin,
            learning_rate           = p_learning_rate,
            feature_fraction        = p_feature_fraction,
            feature_fraction_bynode = as.numeric(PARAM$lgbm_fijos$feature_fraction_bynode),
            min_data_in_leaf        = p_min_data_in_leaf,
            num_leaves              = p_num_leaves,
            min_sum_hessian_in_leaf = p_min_sum_hessian_in_leaf,
            seed                    = p_semilla,
            num_threads             = parallel::detectCores()
        )

        modelo_bo <- lgb.train(
            params  = param_lgb,
            data    = dtrain_bo,
            nrounds = p_num_iterations,
            verbose = -100
        )

        pred_val <- predict(modelo_bo, mat_val_bo)
        rm(modelo_bo)
        invisible(gc(full = FALSE, verbose = FALSE))

        res_eval <- evaluar_validacion(pred_val, target_val_baja2, PARAM$corte_final)
        duracion_seg <- round(as.numeric(difftime(Sys.time(), t_iter_inicio, units = "secs")), 1)

        fila_resultado <- data.table(
            iteracion               = GLOBAL_iteracion,
            ganancia_suavizada      = round(res_eval$ganancia_suavizada),
            ganancia_max            = res_eval$ganancia_max,
            gan_c11000              = res_eval$gan_c11000,
            auc                     = round(res_eval$auc, 6),
            envios_optimos          = res_eval$envios_optimos,
            prob_corte              = round(res_eval$prob_corte, 5),
            semilla                 = p_semilla,
            num_iterations          = p_num_iterations,
            num_leaves              = p_num_leaves,
            min_sum_hessian_in_leaf = p_min_sum_hessian_in_leaf,
            min_data_in_leaf        = p_min_data_in_leaf,
            feature_fraction        = p_feature_fraction,
            learning_rate           = p_learning_rate,
            tiempo_seg              = duracion_seg
        )
        fwrite(fila_resultado, file = archivo_ht, append = TRUE)

        if (res_eval$ganancia_suavizada > GLOBAL_mejor_gan) {
            GLOBAL_mejor_gan <<- res_eval$ganancia_suavizada
            marca_nuevo_max <- "--> NUEVO MÁXIMO!"
            fwrite(
                data.table(
                    numero_de_cliente = df_train$numero_de_cliente[idx_bo_val],
                    clase_ternaria    = clase_ternaria_val,
                    clase01           = target_val_baja2,
                    prob              = pred_val
                ),
                file = archivo_pred_val
            )
        } else {
            marca_nuevo_max <- ""
        }

        cat(sprintf(
            "[BO %03d/%d - %4.0fs] GanSuave: $ %s | GanC11000: $ %s | AUC: %.4f | Envíos: %5d | Iters: %4d | Leaves: %4d | Hessian: %.6f %s\n",
            GLOBAL_iteracion, PARAM$bo_iteraciones, duracion_seg,
            format(round(res_eval$ganancia_suavizada), big.mark = ".", scientific = FALSE),
            format(res_eval$gan_c11000, big.mark = ".", scientific = FALSE),
            res_eval$auc, res_eval$envios_optimos,
            p_num_iterations, p_num_leaves, p_min_sum_hessian_in_leaf, marca_nuevo_max
        ))

        return(res_eval$ganancia_suavizada)
    }

    if (PARAM$modo_ht == "bayesiana") {
        configureMlr(show.learner.output = FALSE)

        hs_bo <- makeParamSet(
            makeIntegerParam("num_iterations",
                lower = as.integer(PARAM$bo_bordes$num_iterations[1]),
                upper = as.integer(PARAM$bo_bordes$num_iterations[2])
            ),
            makeIntegerParam("num_leaves",
                lower = as.integer(PARAM$bo_bordes$num_leaves[1]),
                upper = as.integer(PARAM$bo_bordes$num_leaves[2])
            ),
            makeNumericParam("min_sum_hessian_in_leaf",
                lower = as.numeric(PARAM$bo_bordes$min_sum_hessian_in_leaf[1]),
                upper = as.numeric(PARAM$bo_bordes$min_sum_hessian_in_leaf[2])
            )
        )

        obj_fun <- makeSingleObjectiveFunction(
            fn                   = EstimarGanancia_lightgbm,
            minimize             = FALSE,
            noisy                = TRUE,
            par.set              = hs_bo,
            has.simple.signature = FALSE
        )

        # Con k=3 HPs, mlrMBO corre 4*k = 12 puntos de initdesign y luego iters_infill iteraciones Kriging
        iters_infill <- max(10L, as.integer(PARAM$bo_iteraciones) - 12L)

        ctrl <- makeMBOControl(save.on.disk.at.time = 600, save.file.path = archivo_bo)
        ctrl <- setMBOControlTermination(ctrl, iters = iters_infill)
        ctrl <- setMBOControlInfill(ctrl, crit = makeMBOInfillCritEI())

        surr_km <- makeLearner(
            "regr.km",
            predict.type = "se",
            covtype      = "matern3_2",
            control      = list(trace = FALSE)
        )

        set.seed(PARAM$semillas[1])
        if (!file.exists(archivo_bo)) {
            bayesiana_salida <- mbo(obj_fun, learner = surr_km, control = ctrl)
        } else {
            cat("Retomando Optimización Bayesiana desde:", archivo_bo, "\n")
            bayesiana_salida <- mboContinue(archivo_bo)
        }

        tb_bayesiana <- as.data.table(bayesiana_salida$opt.path)
        tb_bayesiana[, iter := .I]
        setorder(tb_bayesiana, -y)
        fwrite(tb_bayesiana, file = archivo_log, sep = "\t")
    } else if (PARAM$modo_ht == "fijos") {
        for (sem in PARAM$semillas[1:min(5L, length(PARAM$semillas))]) {
            EstimarGanancia_lightgbm(c(PARAM$hp_fijos, list(seed = sem)))
        }
    }

    # Liberar memoria de objetos exclusivos de la BO antes de Producción
    rm(dtrain_bo, mat_val_bo)
    invisible(gc())

    tiempo_ht_fin <- Sys.time()
    cat("\n--- OPTIMIZACIÓN FINALIZADA ---\n")
    cat("Tiempo total de búsqueda:", round(difftime(tiempo_ht_fin, tiempo_ht_inicio, units = "hours"), 2), "horas\n")
} else {
    cat("\nSalteando BO: se utilizan las iteraciones ya guardadas en", archivo_ht, "\n")
}

# ============================================================
# 7.1 TABLA DE CONTINGENCIA (VP/FP/FN/VN) Y GRÁFICOS DE VALIDACIÓN (202106)
# ============================================================

tb_resultados_ht <- fread(archivo_ht)

if (file.exists(archivo_pred_val)) {
    cat("\n--- AUDITORÍA DE CLASIFICACIÓN Y TABLA DE CONTINGENCIA EN VALIDACIÓN (", PARAM$val_bo, ") ---\n", sep = "")
    dt_val_champ <- fread(archivo_pred_val)
    setorder(dt_val_champ, -prob)
    dt_val_champ[, envio := .I]
    dt_val_champ[, ganancia_acum := cumsum(fifelse(clase01 == 1L, 1072500, -27500))]
    dt_val_champ[, ganancia_suave := frollmean(ganancia_acum, n = 501L, align = "center", na.rm = TRUE)]

    corte_opt_suave <- which.max(dt_val_champ$ganancia_suave)
    cortes_auditoria <- unique(c(PARAM$corte_final, corte_opt_suave))

    for (c_eval in cortes_auditoria) {
        etiqueta_corte <- if (c_eval == PARAM$corte_final) "CORTE FIJO" else "CORTE ÓPTIMO SUAVIZADO"
        dt_val_champ[, pred_pos := fifelse(envio <= c_eval, 1L, 0L)]

        VP <- sum(dt_val_champ$pred_pos == 1L & dt_val_champ$clase01 == 1L)
        FP <- sum(dt_val_champ$pred_pos == 1L & dt_val_champ$clase01 == 0L)
        FN <- sum(dt_val_champ$pred_pos == 0L & dt_val_champ$clase01 == 1L)
        VN <- sum(dt_val_champ$pred_pos == 0L & dt_val_champ$clase01 == 0L)

        sensibilidad <- VP / (VP + FN)
        especificidad <- VN / (VN + FP)
        vpp_precision <- VP / (VP + FP)
        vpn <- VN / (VN + FN)
        prevalencia <- (VP + FN) / nrow(dt_val_champ)
        lift_corte <- vpp_precision / prevalencia
        gan_neta <- VP * 1072500 - FP * 27500

        cat(sprintf("\n>>> %s: %d ENVÍOS (Prob. corte = %.5f) <<<\n", etiqueta_corte, c_eval, dt_val_champ$prob[c_eval]))
        cat("1. Matriz de Confusión Binaria (Target Real = BAJA+2):\n")
        mat_conf <- matrix(
            c(VP, FP, FN, VN),
            nrow = 2, byrow = TRUE,
            dimnames = list(
                "Predicho" = c("Enviar Estímulo (1)", "No Enviar (0)"),
                "Real_BAJA2" = c("BAJA+2 (Positivo)", "No BAJA+2 (Negativo)")
            )
        )
        print(mat_conf)

        cat("\n2. Desglose por Clase Ternaria Real:\n")
        print(table(
            Predicho = ifelse(dt_val_champ$pred_pos == 1L, "1_Enviar", "0_No_Enviar"),
            Clase_Ternaria = dt_val_champ$clase_ternaria
        ))

        cat(sprintf(
            "\n3. Métricas Epidemiológicas / Negocio en %d envíos:\n   - VP (BAJA+2 capturados): %d de %d (Sensibilidad / Recall = %.2f%%)\n   - FP (Envíos sin BAJA+2): %d (Especificidad = %.2f%%)\n   - VPP (Precisión en el corte): %.2f%% (Prevalencia basal = %.2f%% -> Lift = %.2fx)\n   - VPN: %.4f%%\n   - Ganancia Neta Cruda: $ %s | Ganancia Suavizada (+-250): $ %s\n",
            c_eval, VP, VP + FN, sensibilidad * 100,
            FP, especificidad * 100,
            vpp_precision * 100, prevalencia * 100, lift_corte,
            vpn * 100,
            format(gan_neta, big.mark = ".", scientific = FALSE),
            format(round(dt_val_champ$ganancia_suave[c_eval]), big.mark = ".", scientific = FALSE)
        ))
    }

    # Gráfico 1: Curva de Ganancia Acumulada (Cruda vs Suavizada) en 202106 (0 a 25.000 envíos)
    dt_curva <- dt_val_champ[envio <= 25000L]
    p_curva_gan <- ggplot(dt_curva, aes(x = envio)) +
        geom_line(aes(y = ganancia_acum / 1e6, color = "Ganancia Cruda"), alpha = 0.45, linewidth = 0.6) +
        geom_line(aes(y = ganancia_suave / 1e6, color = "Ganancia Suavizada (+-250)"), linewidth = 1.1, na.rm = TRUE) +
        geom_vline(xintercept = PARAM$corte_final, linetype = "dashed", color = "firebrick", linewidth = 0.8) +
        geom_vline(xintercept = corte_opt_suave, linetype = "dotted", color = "darkgreen", linewidth = 0.8) +
        scale_color_manual(values = c("Ganancia Cruda" = "steelblue", "Ganancia Suavizada (+-250)" = "navy")) +
        labs(
            title = paste0("Curva de Ganancia en Validación (", PARAM$val_bo, ") - Modelo Champion BO"),
            subtitle = sprintf(
                "Max Suavizada: $ %s M (en %d envíos) | Corte %d: $ %s M",
                format(round(max(dt_curva$ganancia_suave, na.rm = TRUE) / 1e6, 2), nsmall = 2),
                corte_opt_suave, PARAM$corte_final,
                format(round(dt_val_champ$ganancia_acum[PARAM$corte_final] / 1e6, 2), nsmall = 2)
            ),
            x = "Cantidad de Envíos (ordenados por probabilidad descendente)",
            y = "Ganancia Acumulada (Millones ARS)",
            color = "Curva"
        ) +
        theme_minimal(base_size = 11) +
        theme(legend.position = "top")

    ggsave(file.path(dir_exp, "plots/bo_curva_ganancia_202106.png"), p_curva_gan, width = 10, height = 6, dpi = 300)
    cat("\nGráfico de curva de ganancia guardado en:", file.path(dir_exp, "plots/bo_curva_ganancia_202106.png"), "\n")
    rm(dt_val_champ, dt_curva)
}

if (nrow(tb_resultados_ht) > 1) {
    tb_resultados_ht[, mejor_acum := cummax(ganancia_suavizada)]
    tb_resultados_ht[, etapa_bo := fifelse(iteracion <= 12L, "1_InitDesign (Azar)", "2_Kriging (Inteligente)")]

    # Gráfico 2: Evolución de las iteraciones de la Optimización Bayesiana
    p_bo_evol <- ggplot(tb_resultados_ht, aes(x = iteracion)) +
        geom_vline(xintercept = 12.5, linetype = "dashed", color = "gray40") +
        geom_point(aes(y = ganancia_suavizada / 1e6, color = etapa_bo), size = 2.5, alpha = 0.85) +
        geom_line(aes(y = mejor_acum / 1e6), color = "firebrick", linewidth = 1.0) +
        labs(
            title = sprintf("Convergencia de la Optimización Bayesiana - %s (%d iteraciones)", PARAM$modelo, PARAM$bo_iteraciones),
            subtitle = "Puntos: Ganancia Suavizada por iteración | Línea roja: Máximo acumulado",
            x = "Iteración de la BO (1-12 = InitDesign, 13-50 = Kriging EI)",
            y = "Ganancia Suavizada en 202106 (Millones ARS)",
            color = "Fase BO"
        ) +
        theme_minimal(base_size = 11) +
        theme(legend.position = "top")

    ggsave(file.path(dir_exp, "plots/bo_evolucion_iteraciones.png"), p_bo_evol, width = 10, height = 6, dpi = 300)

    # Gráfico 3: Paisaje de los 3 Hiperparámetros explorados
    p_bo_hp <- ggplot(tb_resultados_ht, aes(
        x = num_leaves,
        y = log10(min_sum_hessian_in_leaf),
        color = ganancia_suavizada / 1e6,
        size = num_iterations
    )) +
        geom_point(alpha = 0.8) +
        scale_color_viridis_c(option = "plasma", name = "Ganancia Suave (M)") +
        labs(
            title = "Espacio de Hiperparámetros Explorado (3 HPs)",
            x = "num_leaves",
            y = "log10(min_sum_hessian_in_leaf)",
            size = "num_iterations"
        ) +
        theme_minimal(base_size = 11)

    ggsave(file.path(dir_exp, "plots/bo_paisaje_hiperparametros.png"), p_bo_hp, width = 9, height = 6, dpi = 300)
    cat("Gráficos diagnósticos de la BO guardados en:", file.path(dir_exp, "plots"), "\n")
}

# ============================================================
# 7.2 TESTEO EN JUNIO: 10 SEMILLAS CON LOS MEJORES HP
# ============================================================
# Entrena en train_bo (202103+202104) con los mejores HP de la BO y las MISMAS 10 semillas
# en todos los modelos, y predice val_bo (202106). La decision entre modelos se toma con
# esta ganancia (no con el publico). Insumo de comparacion_modelos.R.

if (PARAM$etapa == "testeo") {
    cat("\n--- TESTEO EN JUNIO (", PARAM$modelo, "): ", PARAM$n_semillas_test, " SEMILLAS ---\n", sep = "")

    mejor_hp <- tb_resultados_ht[which.max(ganancia_suavizada)]
    semillas_test <- PARAM$semillas[seq_len(PARAM$n_semillas_test)]
    cat(sprintf(
        "HP (iter %d): num_iterations=%d | num_leaves=%d | min_sum_hessian=%.6f\n",
        mejor_hp$iteracion, mejor_hp$num_iterations, mejor_hp$num_leaves, mejor_hp$min_sum_hessian_in_leaf
    ))

    armar_param_lgb <- function(hp, semilla) {
        list(
            objective = "binary", metric = "none", boosting = "gbdt",
            first_metric_only = TRUE, boost_from_average = TRUE, feature_pre_filter = FALSE,
            force_row_wise = TRUE, verbosity = -100L, max_depth = -1L, min_gain_to_split = 0.0,
            lambda_l1 = 0.0, lambda_l2 = 0.0, max_bin = PARAM$max_bin,
            learning_rate = as.numeric(PARAM$lgbm_fijos$learning_rate),
            feature_fraction = as.numeric(PARAM$lgbm_fijos$feature_fraction),
            feature_fraction_bynode = as.numeric(PARAM$lgbm_fijos$feature_fraction_bynode),
            min_data_in_leaf = as.integer(PARAM$lgbm_fijos$min_data_in_leaf),
            num_leaves = as.integer(hp$num_leaves),
            min_sum_hessian_in_leaf = as.numeric(hp$min_sum_hessian_in_leaf),
            seed = as.integer(semilla),
            num_threads = parallel::detectCores()
        )
    }

    curva_suave <- function(prob, y) {
        ord <- order(prob, decreasing = TRUE)
        gan <- cumsum(fifelse(y[ord] == 1L, 1072500, -27500))
        data.table(envio = seq_along(gan), gan_acum = gan, gan_suave = frollmean(gan, n = 501L, align = "center"))
    }

    idx_test_train <- which(df_train$foto_mes %in% PARAM$train_bo)
    if (isTRUE(PARAM$excluir_dudosos)) idx_test_train <- filtrar_dudosos(idx_test_train)
    idx_test_val <- which(df_train$foto_mes == PARAM$val_bo)

    dtrain_test <- lgb.Dataset(
        data = data.matrix(df_train[idx_test_train, ..campos_buenos]),
        label = df_train$target_binario[idx_test_train],
        params = list(max_bin = PARAM$max_bin, feature_pre_filter = FALSE),
        free_raw_data = FALSE
    )
    mat_test <- data.matrix(df_train[idx_test_val, ..campos_buenos])
    clase01_test <- df_train$clase01[idx_test_val]

    tb_pred_test <- data.table(numero_de_cliente = df_train$numero_de_cliente[idx_test_val], clase01 = clase01_test)
    tb_gan_test <- data.table()
    curvas_test <- list()

    for (idx_s in seq_along(semillas_test)) {
        t0 <- Sys.time()
        modelo_t <- lgb.train(
            params = armar_param_lgb(mejor_hp, semillas_test[idx_s]),
            data = dtrain_test,
            nrounds = as.integer(mejor_hp$num_iterations),
            verbose = -100
        )
        pred_t <- predict(modelo_t, mat_test)
        set(tb_pred_test, j = sprintf("prob_s%02d", idx_s), value = pred_t)

        res_t <- evaluar_validacion(pred_t, clase01_test, PARAM$corte_final)
        tb_gan_test <- rbind(tb_gan_test, data.table(
            semilla = as.character(semillas_test[idx_s]), gan_suave_max = res_t$ganancia_suavizada,
            envios_optimos = res_t$envios_optimos, gan_c11000 = res_t$gan_c11000, auc = res_t$auc
        ))
        curvas_test[[idx_s]] <- curva_suave(pred_t, clase01_test)[envio <= 25000L, .(semilla = semillas_test[idx_s], envio, gan_suave)]

        cat(sprintf(
            "[Test %02d/%d - %d] %4.0fs | GanSuave: $ %s | Envios: %5d | GanC11000: $ %s\n",
            idx_s, length(semillas_test), semillas_test[idx_s],
            as.numeric(difftime(Sys.time(), t0, units = "secs")),
            format(round(res_t$ganancia_suavizada), big.mark = "."), res_t$envios_optimos,
            format(res_t$gan_c11000, big.mark = ".")
        ))
        rm(modelo_t)
        invisible(gc(verbose = FALSE))
    }

    # Ensamble = promedio de probabilidades de las 10 semillas
    cols_prob <- grep("^prob_s[0-9]+$", names(tb_pred_test), value = TRUE)
    prob_ens_test <- rowMeans(tb_pred_test[, ..cols_prob])
    res_ens <- evaluar_validacion(prob_ens_test, clase01_test, PARAM$corte_final)
    curva_ens <- curva_suave(prob_ens_test, clase01_test)

    cat(sprintf(
        "\nResumen testeo %s: semillas media $ %s M (DE %s M) | ENSAMBLE $ %s M en %d envios | AUC %.4f\n",
        PARAM$modelo,
        round(mean(tb_gan_test$gan_suave_max) / 1e6, 2), round(sd(tb_gan_test$gan_suave_max) / 1e6, 2),
        round(res_ens$ganancia_suavizada / 1e6, 2), res_ens$envios_optimos, res_ens$auc
    ))
    cat("\nGanancia del ensamble en la grilla de cortes (millones):\n")
    print(data.table(corte = PARAM$cortes_grilla, ganancia_M = round(curva_ens$gan_acum[PARAM$cortes_grilla] / 1e6, 2)))

    # Grafico: 10 curvas por semilla (gris) + ensamble (firebrick)
    p_test <- ggplot() +
        geom_line(
            data = rbindlist(curvas_test), aes(x = envio, y = gan_suave / 1e6, group = semilla),
            color = "gray60", linewidth = 0.4, na.rm = TRUE
        ) +
        geom_line(
            data = curva_ens[envio <= 25000L], aes(x = envio, y = gan_suave / 1e6),
            color = "firebrick", linewidth = 1.1, na.rm = TRUE
        ) +
        geom_vline(xintercept = res_ens$envios_optimos, linetype = "dashed", color = "firebrick") +
        labs(
            title = sprintf("%s - Testeo en %d: 10 semillas (gris) + ensamble (rojo)", PARAM$modelo, PARAM$val_bo),
            subtitle = sprintf("Ensamble: $ %s M en %d envios", round(res_ens$ganancia_suavizada / 1e6, 2), res_ens$envios_optimos),
            x = "Envios", y = "Ganancia suavizada (millones ARS)"
        ) +
        theme_minimal(base_size = 11)
    ggsave(file.path(dir_exp, "plots/test_curvas_ganancia_202106.png"), p_test, width = 10, height = 6, dpi = 150)
    cat("\n![Curvas de ganancia testeo junio](../plots/test_curvas_ganancia_202106.png)\n\n")

    # Insumo de comparacion_modelos.R
    saveRDS(
        list(
            predicciones = tb_pred_test[, c("numero_de_cliente", "clase01", cols_prob), with = FALSE],
            semillas = semillas_test, modelo = PARAM$modelo, experimento = PARAM$experimento, hp = mejor_hp
        ),
        file.path(dir_exp, sprintf("probabilidades_test_%d_%dsem.rds", PARAM$val_bo, PARAM$n_semillas_test))
    )

    # Registro para el Google Sheet (una fila por semilla + una del ensamble)
    tb_registro <- rbind(
        tb_gan_test,
        data.table(
            semilla = sprintf("ensamble%d", PARAM$n_semillas_test), gan_suave_max = res_ens$ganancia_suavizada,
            envios_optimos = res_ens$envios_optimos, gan_c11000 = res_ens$gan_c11000, auc = res_ens$auc
        )
    )
    tb_registro <- cbind(
        data.table(
            fecha = format(Sys.time(), "%Y-%m-%d %H:%M"), maquina = PARAM$maquina,
            experimento = PARAM$experimento, modelo = PARAM$modelo, tipo_validacion = "test_202106_oot",
            train_meses = paste(PARAM$train_bo, collapse = "+"), test_mes = PARAM$val_bo, n_features = length(campos_buenos),
            num_iterations = mejor_hp$num_iterations, num_leaves = mejor_hp$num_leaves,
            min_sum_hessian = mejor_hp$min_sum_hessian_in_leaf, learning_rate = PARAM$lgbm_fijos$learning_rate,
            ff = PARAM$lgbm_fijos$feature_fraction, ff_bynode = PARAM$lgbm_fijos$feature_fraction_bynode
        ),
        tb_registro
    )
    archivo_registro <- file.path(dir_base, "registro_modelos.csv")
    fwrite(tb_registro, archivo_registro, append = file.exists(archivo_registro))
    cat("Registro agregado en:", archivo_registro, "\n")

    rm(dtrain_test, mat_test, tb_pred_test)
    invisible(gc())
}

# ==============================================================================
# 8. PRODUCCIÓN FINAL: ENTRENAMIENTO EN 4 MESES (202103..202106)
#    + IMPORTANCIA DE VARIABLES + ENSAMBLE DE n_semillas_prod SEMILLAS SOBRE 202108
# ==============================================================================

if (PARAM$etapa == "produccion") {
    n_sem_total <- PARAM$n_semillas_prod

    # 1. Seleccionar el Champion por Ganancia Suavizada en 202106
    idx_mejor <- which.max(tb_resultados_ht$ganancia_suavizada)
    mejor_registro <- tb_resultados_ht[idx_mejor]

    cat("\n======================================================\n")
    cat("PREPARANDO PRODUCCIÓN FINAL\n")
    cat(sprintf(
        "Champion BO: Iter %d | Gan. Suavizada: $ %s | Corte BO: %d envíos\n",
        mejor_registro$iteracion,
        format(round(mejor_registro$ganancia_suavizada, 0), big.mark = ".", decimal.mark = ","),
        mejor_registro$envios_optimos
    ))
    cat(sprintf(
        "HPs Champion: num_iterations=%d | num_leaves=%d | min_sum_hessian=%.6f (log10=%.3f)\n",
        mejor_registro$num_iterations,
        mejor_registro$num_leaves,
        mejor_registro$min_sum_hessian_in_leaf,
        log10(mejor_registro$min_sum_hessian_in_leaf)
    ))
    cat(sprintf(
        "Semillas a entrenar: %d (Primeras 5: %s ...)\n",
        n_sem_total, paste(PARAM$semillas[1:5], collapse = ", ")
    ))
    cat("======================================================\n")

    # 2. Construir Dataset Final de Entrenamiento con los 4 meses con clase completa
    #    (202103, 202104, 202105, 202106) y Matriz Futura (202108)
    idx_prod <- which(df_train$foto_mes %in% PARAM$train_final)
    if (isTRUE(PARAM$excluir_dudosos)) idx_prod <- filtrar_dudosos(idx_prod) # mismo filtro sobre 202103..202106
    df_train_prod <- df_train[idx_prod]
    cat(sprintf(
        "\nEntrenando Producción sobre meses: %s (%d filas totales | %d POS [%s] | %d BAJA+2 reales)\n",
        paste(PARAM$train_final, collapse = ", "),
        nrow(df_train_prod),
        sum(df_train_prod$target_binario == 1L),
        PARAM$target,
        sum(df_train_prod$clase01 == 1L)
    ))

    dtrain_final <- lgb.Dataset(
        data = data.matrix(df_train_prod[, ..campos_buenos]),
        label = df_train_prod$target_binario,
        params = list(max_bin = PARAM$max_bin, feature_pre_filter = FALSE),
        free_raw_data = FALSE
    )
    lgb.Dataset.construct(dtrain_final)

    mat_future <- data.matrix(df_future[, ..campos_buenos])
    clientes_future <- df_future$numero_de_cliente
    fotos_future <- df_future$foto_mes

    # Liberar memoria antes del loop de 100 entrenamientos
    rm(df_train, df_train_prod)
    gc(verbose = FALSE)

    # 3. Directorios de salida
    dir_plots <- file.path(dir_exp, "plots")
    dir_submits_ens <- file.path(dir_exp, "submits")
    dir_submits_chk <- file.path(dir_exp, "submits_checkpoints")
    dir.create(dir_plots, showWarnings = FALSE, recursive = TRUE)
    dir.create(dir_submits_ens, showWarnings = FALSE, recursive = TRUE)
    dir.create(dir_submits_chk, showWarnings = FALSE, recursive = TRUE)

    if (isTRUE(PARAM$guardar_submits_individuales)) {
        dir_submits_sem <- file.path(dir_exp, "submits_semillas")
        dir.create(dir_submits_sem, showWarnings = FALSE, recursive = TRUE)
    }

    # 4. Matriz de probabilidades (filas = clientes 202108, columnas = 100 semillas)
    mat_probs_semillas <- matrix(
        NA_real_,
        nrow = length(clientes_future),
        ncol = n_sem_total
    )
    colnames(mat_probs_semillas) <- sprintf("prob_s%03d", seq_len(n_sem_total))

    # Registro de convergencia del Top 11.000 a medida que agregamos semillas
    tb_convergencia <- data.table()
    top_clientes_prev <- integer(0)

    cat("\n======================================================\n")
    cat(sprintf(
        "ENTRENANDO ENSAMBLE DE %d SEMILLAS SOBRE 4 MESES (CORTE BASE = %d)\n",
        n_sem_total, PARAM$corte_final
    ))
    cat("======================================================\n")

    t0_loop_sem <- Sys.time()

    for (idx_s in seq_len(n_sem_total)) {
        sem_actual <- PARAM$semillas[idx_s]
        t0_sem <- Sys.time()

        param_sem <- list(
            objective               = "binary",
            metric                  = "none",
            boosting                = "gbdt",
            first_metric_only       = TRUE,
            boost_from_average      = TRUE,
            feature_pre_filter      = FALSE,
            force_row_wise          = TRUE,
            verbosity               = -100L,
            max_depth               = -1L,
            min_gain_to_split       = 0.0,
            lambda_l1               = 0.0,
            lambda_l2               = 0.0,
            max_bin                 = PARAM$max_bin,
            learning_rate           = as.numeric(PARAM$lgbm_fijos$learning_rate),
            feature_fraction        = as.numeric(PARAM$lgbm_fijos$feature_fraction),
            feature_fraction_bynode = as.numeric(PARAM$lgbm_fijos$feature_fraction_bynode),
            min_data_in_leaf        = as.integer(PARAM$lgbm_fijos$min_data_in_leaf),
            num_leaves              = as.integer(mejor_registro$num_leaves),
            min_sum_hessian_in_leaf = as.numeric(mejor_registro$min_sum_hessian_in_leaf),
            seed                    = as.integer(sem_actual),
            num_threads             = parallel::detectCores()
        )

        modelo_s <- lgb.train(
            params  = param_sem,
            data    = dtrain_final,
            nrounds = as.integer(mejor_registro$num_iterations),
            verbose = -100
        )

        # En la Semilla 1 extraemos Importancia de Variables (evita entrenar 2 veces)
        if (idx_s == 1L) {
            tb_imp <- as.data.table(lgb.importance(modelo_s))
            fwrite(tb_imp, file.path(dir_exp, "feature_importance_top30.csv"))

            cat("\nTop 20 Variables más importantes (Gain) en Producción (4 meses):\n")
            print(tb_imp[1:min(20L, nrow(tb_imp)), .(Feature, Gain, Cover, Frequency)])

            tb_imp_top30 <- tb_imp[1:min(30L, nrow(tb_imp))]
            tb_imp_top30[, Feature := factor(Feature, levels = rev(Feature))]

            p_imp <- ggplot(tb_imp_top30, aes(x = Feature, y = Gain)) +
                geom_col(fill = "steelblue") +
                coord_flip() +
                labs(
                    title = paste0("Top 30 Feature Importance (Gain) - ", PARAM$experimento),
                    subtitle = sprintf(
                        "Champion 4 meses (%s) | iter=%d, leaves=%d, hessian=%.5f",
                        paste(PARAM$train_final, collapse = "+"),
                        mejor_registro$num_iterations,
                        mejor_registro$num_leaves,
                        mejor_registro$min_sum_hessian_in_leaf
                    ),
                    x = "Variable", y = "Gain"
                ) +
                theme_minimal(base_size = 11)

            ggsave(file.path(dir_plots, "feature_importance_top30.png"),
                plot = p_imp, width = 10, height = 8, dpi = 150
            )
        }

        # Predicción sobre 202108
        pred_s <- predict(modelo_s, mat_future)
        mat_probs_semillas[, idx_s] <- pred_s

        # Opcional: guardar submit individual de cada semilla
        if (isTRUE(PARAM$guardar_submits_individuales)) {
            tb_sub_s <- data.table(numero_de_cliente = clientes_future, prob = pred_s)
            setorder(tb_sub_s, -prob)

            arch_sem <- file.path(
                dir_submits_sem,
                sprintf(
                    "submit_%s_s%03d_%d_c%d.csv",
                    PARAM$experimento, idx_s, sem_actual, PARAM$corte_final
                )
            )
            fwrite(tb_sub_s[1:PARAM$corte_final, .(numero_de_cliente)], arch_sem, col.names = FALSE)
            rm(tb_sub_s)
        }

        # Medir estabilidad del corte 11.000 acumulado hasta idx_s semillas
        prob_acum <- rowMeans(mat_probs_semillas[, 1:idx_s, drop = FALSE])
        ord_acum <- order(prob_acum, decreasing = TRUE)
        top_clientes_actual <- clientes_future[ord_acum[1:PARAM$corte_final]]

        cambios_vs_prev <- if (idx_s == 1L) NA_integer_ else length(setdiff(top_clientes_actual, top_clientes_prev))
        top_clientes_prev <- top_clientes_actual

        tb_convergencia <- rbind(tb_convergencia, data.table(
            n_semillas          = idx_s,
            semilla             = sem_actual,
            cambios_en_top11000 = cambios_vs_prev,
            prob_corte_11000    = prob_acum[ord_acum[PARAM$corte_final]]
        ))

        dur_sem <- round(as.numeric(difftime(Sys.time(), t0_sem, units = "secs")), 1)
        trans_min <- round(as.numeric(difftime(Sys.time(), t0_loop_sem, units = "mins")), 1)
        eta_min <- round((trans_min / idx_s) * (n_sem_total - idx_s), 1)

        cat(sprintf(
            "Semilla %03d/%03d (%d) | %4.1fs | Cambios Top %d: %4s | Trans: %4.1fm | ETA: %4.1fm\n",
            idx_s, n_sem_total, sem_actual, dur_sem, PARAM$corte_final,
            ifelse(is.na(cambios_vs_prev), "-", as.character(cambios_vs_prev)),
            trans_min, eta_min
        ))

        # Checkpoint cada 20 semillas (guarda submit parcial en corte 11000)
        if (idx_s %% 20L == 0L || idx_s == n_sem_total) {
            tb_chk <- data.table(numero_de_cliente = clientes_future, prob = prob_acum)
            setorder(tb_chk, -prob)

            arch_chk <- file.path(
                dir_submits_chk,
                sprintf(
                    "submit_%s_ensamble_parcial_%03dsem_c%d.csv",
                    PARAM$experimento, idx_s, PARAM$corte_final
                )
            )
            fwrite(tb_chk[1:PARAM$corte_final, .(numero_de_cliente)], arch_chk, col.names = FALSE)

            cat(sprintf(
                "  [CHECKPOINT %03d SEMILLAS] Submit parcial guardado: %s\n",
                idx_s, basename(arch_chk)
            ))
            rm(tb_chk)
        }

        rm(modelo_s)
        gc(verbose = FALSE)
    }

    fwrite(tb_convergencia, file.path(dir_exp, "convergencia_semillas_top11000.csv"))

    # 5. Promediar probabilidades de las 100 semillas (Ensamble Final)
    prob_ensamble <- rowMeans(mat_probs_semillas)
    sd_ensamble <- apply(mat_probs_semillas, 1, sd)

    # Tabla de probabilidades por semilla (ID | 202108 | prob_s001..prob_sNNN | prob_promedio | prob_sd)
    tb_tabla_sem <- data.table(
        numero_de_cliente = clientes_future,
        foto_mes          = fotos_future
    )
    tb_tabla_sem <- cbind(tb_tabla_sem, as.data.table(mat_probs_semillas))
    tb_tabla_sem[, prob_promedio := prob_ensamble]
    tb_tabla_sem[, prob_sd := sd_ensamble]
    setorder(tb_tabla_sem, -prob_promedio)

    # Guardar en RDS comprimido (rápido y liviano para iCloud) + tabla resumen en CSV
    saveRDS(tb_tabla_sem, file.path(dir_exp, sprintf("probabilidades_%dsemillas_202108.rds", n_sem_total)))

    tb_pred_ensamble <- tb_tabla_sem[, .(
        numero_de_cliente,
        foto_mes,
        prob    = prob_promedio,
        prob_sd = prob_sd
    )]
    fwrite(tb_pred_ensamble, file.path(dir_exp, "probabilidades_ensamble_202108.csv"))

    cat("\n======================================================\n")
    cat(sprintf("EXPORTANDO CORTES DEL ENSAMBLE FINAL (%d SEMILLAS)\n", n_sem_total))
    cat("======================================================\n")

    for (corte in PARAM$cortes_grilla) {
        # tb_pred_ensamble ya viene ordenado por prob descendente (tb_tabla_sem)
        arch_ens <- file.path(
            dir_submits_ens,
            sprintf("submit_%s_ensamble%dsem_c%d.csv", PARAM$experimento, n_sem_total, corte)
        )
        # Formato de entrega: solo los IDs a estimular, sin encabezado
        fwrite(tb_pred_ensamble[1:corte, .(numero_de_cliente)], arch_ens, col.names = FALSE)


        prob_umbral <- tb_pred_ensamble[corte, prob]
        cat(sprintf(
            "  -> Corte %5d envíos (p_corte = %.5f): %s\n",
            corte, prob_umbral, basename(arch_ens)
        ))
    }

    # 6. Gráficos diagnósticos de Producción (Curva de Probabilidad + Convergencia de las 100 Semillas)
    tb_top20k <- copy(tb_pred_ensamble[1:min(20000L, nrow(tb_pred_ensamble))])
    tb_top20k[, ranking_envio := .I]

    p_prod <- ggplot(tb_top20k, aes(x = ranking_envio, y = prob)) +
        geom_ribbon(aes(ymin = pmax(0, prob - prob_sd), ymax = pmin(1, prob + prob_sd)),
            fill = "#9ecae1", alpha = 0.5
        ) +
        geom_line(color = "#08519c", linewidth = 0.9) +
        geom_vline(xintercept = PARAM$corte_final, linetype = "dashed", color = "#cb181d", linewidth = 0.8) +
        geom_vline(xintercept = mejor_registro$envios_optimos, linetype = "dotted", color = "#238b45", linewidth = 0.8) +
        annotate("text",
            x = PARAM$corte_final + 300, y = max(tb_top20k$prob) * 0.90,
            label = sprintf("Corte fijo: %d", PARAM$corte_final), color = "#cb181d", hjust = 0, size = 3.5
        ) +
        annotate("text",
            x = mejor_registro$envios_optimos - 300, y = max(tb_top20k$prob) * 0.78,
            label = sprintf("Corte óptimo BO: %d", mejor_registro$envios_optimos), color = "#238b45", hjust = 1, size = 3.5
        ) +
        scale_x_continuous(breaks = seq(0, 20000, by = 2000)) +
        labs(
            title = sprintf(
                "Curva de Probabilidad del Ensamble (%d Semillas) en 202108 - %s",
                n_sem_total, PARAM$experimento
            ),
            subtitle = sprintf("Línea azul: Probabilidad media | Banda celeste: ±1 DE entre las %d semillas", n_sem_total),
            x = "Cantidad de Envíos (Clientes ordenados por probabilidad decreciente)",
            y = "Probabilidad estimada de POS (BAJA+1 / BAJA+2)"
        ) +
        theme_minimal(base_size = 11)

    ggsave(file.path(dir_plots, "prod_curva_probabilidades_202108.png"),
        plot = p_prod, width = 10, height = 6, dpi = 150
    )

    if (nrow(tb_convergencia) >= 2L) {
        p_conv <- ggplot(
            tb_convergencia[!is.na(cambios_en_top11000)],
            aes(x = n_semillas, y = cambios_en_top11000)
        ) +
            geom_line(color = "#2b8cbe", linewidth = 0.8) +
            geom_point(color = "#08519c", size = 1.8) +
            labs(
                title = sprintf(
                    "Convergencia del Ensamble de %d Semillas (Estabilidad del Corte %d)",
                    n_sem_total, PARAM$corte_final
                ),
                subtitle = "Cantidad de clientes que entran/salen del Top 11.000 al agregar cada nueva semilla",
                x = "Cantidad acumulada de semillas promediadas",
                y = "Clientes que cambian en el Top 11.000 vs (k-1) semillas"
            ) +
            theme_minimal(base_size = 11)

        ggsave(file.path(dir_plots, "prod_convergencia_semillas_202108.png"),
            plot = p_conv, width = 10, height = 5.5, dpi = 150
        )
    }

    cat("\nGráficos de producción guardados en:", dir_plots, "\n")
} # fin etapa produccion

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
