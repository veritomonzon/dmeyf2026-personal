# Experimentos Colaborativos — DMEyF 2026

> **Tema #15:** Ponderación temporal del entrenamiento (*sample weighting / time decay*) frente al peso uniforme.  
> **Comisión:** Jueves — Maestría en Data Mining (UBA).  
> **Equipo — Grupo B (2B, postura antagónica):** Fray Campos - Verónica Ester Monzón  

---

## 1. Enlaces y Recursos Oficiales

* **Planilla de inscripción y temas:** [Planilla Colaborativa de Grupos y Temas](https://docs.google.com/spreadsheets/d/1Q03J0AfgDxS2wo79ZUlon8Q32_jfAhyx-f1e0r6sXws/edit?gid=1184961627#gid=1184961627).
* **Plantilla de presentación:** [Plantilla de Experimentos (Google Slides)](https://docs.google.com/presentation/d/1olT1H-tF8dMHq6sG0GRnNGZd9HSu7Yvz/edit?slide=id.p1#slide=id.p1).
* **PDF oficial de la cursada:** [DMEyF 2026 PDF](https://storage.googleapis.com/open-courses/dmeyf2026-9c6f/DMEyF_2026.pdf) — pp. 12 (rúbrica general) y pp. 45–52 (consignas de diseño experimental, preinscripción y exposiciones).
* **Documento de trabajo:** [Ponderación temporal (Google Docs)](https://docs.google.com/document/d/13Nkwsfk4xz29yy1ei74yHat9oJ8LUulc_AmNnZ4VskA/edit?usp=sharing)
* **GitHub colaborativo:** [germandasr/DMEyF_Exp_Colaborativos](https://github.com/germandasr/DMEyF_Exp_Colaborativos) (baseline compartido en `BASELINE_FINAL.ipynb`).
* **Bitácora de la cátedra:** `experimentos_colaborativos_bitacora_2026.pptx`.

---

## 2. Cronograma e Hitos

| Fecha | Instancia | Formato / Requisitos |
| :--- | :--- | :--- |
| **Jue 29-oct-2026** | **Inscripción y selección de tema** | Registro de pareja y tema antagónico en la planilla compartida. |
| **Jue 05-nov-2026** | **Presentación Preliminar (Hito 1)** | Presencial (Cero+Infinito). **3 minutos por grupo**. Solo el diseño metodológico, en el Google Slides compartido: título, hipótesis, bibliografía, sesgos, diseño y limitaciones. Sin contar el baseline. |
| **Jue 03-dic-2026** | **Presentación Definitiva (Hito 2)** | Exposición plenaria (10 min). Hallazgos consolidados, curvas de ganancia y código reproducible en repositorio público. |

---

## 3. Hipótesis Antagónica

* **Hipótesis B:** en el workflow baseline (FE con lags y delta lags de orden 1 y 2), ponderar los meses del entrenamiento por recencia **no mejora la ganancia más allá de un margen δ** respecto de $w = 1$. Si la mejora, la ventaja no se debe al orden temporal: un placebo con los mismos pesos permutados entre meses rinde igual.

**Hipótesis operativas** (unidad de análisis: semilla primigenia; outcome: ganancia máxima del ensamble en 202106; $\Delta_s = G_{T1,s} - G_{T0,s}$)

| | Contraste | Marco | B se sostiene si… |
| :--- | :--- | :--- | :--- |
| **H1 (primaria)** | T1 (decaimiento, $w = 0.5^{\Delta t/12}$) vs. T0 ($w = 1$) | No superioridad, unilateral | Se rechaza $H_0: \Delta \geq \delta$ a favor de $\Delta < \delta$. |
| **H2 (secundaria)** | T1 vs. T2 (placebo) | Equivalencia, TOST $\pm\delta$ | T1 y T2 quedan dentro de $\pm\delta$. Es decisiva si H1 no se confirma. |
| **Exploratoria** | T3 (ventana dura) vs. T1 | Descriptiva | — |

*Refutación:* B se refuta si T1 supera a T0 en más de δ **y** supera al placebo T2. *Jerarquía:* H1 se testea primero y H2 después (secuencia fija), así que no hace falta corregir por multiplicidad.

**Objetivos**
1. **Primario:** estimar la diferencia de ganancia en 202106 entre ponderar por recencia (T1) y no ponderar (T0), y testear la no superioridad de T1 con margen δ.
2. **Secundario:** separar el efecto de la recencia del efecto de tener pesos en sí (T1 vs. placebo T2).
3. **Exploratorio:** comparar ponderar con seleccionar meses (T1 vs. ventana dura T3).
4. **Aplicado:** decidir si la ponderación entra al workflow de la Segunda Competencia.


---

## 4. Fundamentos Teóricos y Bibliografía

1. **Koren, Y. (2009).** *Collaborative filtering with temporal dynamics.* Proceedings of the 15th ACM SIGKDD, 447–456. DOI: [10.1145/1557019.1557072](https://doi.org/10.1145/1557019.1557072). Versión de divulgación: Communications of the ACM, 53(4), 2010.  
   *Probó pesos con decaimiento exponencial en sistemas de recomendación (Netflix Prize): "prediction quality improves as we moderate that time decay, reaching best quality when there is no decay at all", aunque los usuarios sí cambian con los años. Explica que las preferencias viejas persisten y que bajarles el peso "loses too much signal along with the lost noise". Propone modelar la dinámica temporal dentro del modelo, algo análogo a nuestros lags y deltas (inferencia nuestra). Dominio distinto del churn.*
2. **Klinkenberg, R. (2004).** *Learning drifting concepts: Example selection vs. example weighting.* Intelligent Data Analysis, 8(3), 281–300. DOI: [10.3233/IDA-2004-8305](https://doi.org/10.3233/IDA-2004-8305).  
   *Con concept drift simulado sobre texto y SVM, la selección de ejemplos (ventana adaptativa o selección por lotes) funciona mejor que la ponderación gradual por antigüedad. El autor concluye que una representación continua de la importancia de cada ejemplo "no aporta información útil adicional". Límites: dominio de texto, drift simulado y otro algoritmo.*
3. **Kagerbauer, S. M., Ulm, B., Podtschaske, A. H., et al. (2024).** *Susceptibility of AutoML mortality prediction algorithms to model drift caused by the COVID pandemic.* BMC Medical Informatics and Decision Making, 24, 34. DOI: [10.1186/s12911-024-02428-z](https://doi.org/10.1186/s12911-024-02428-z).  
   *Modelos de mortalidad posoperatoria (entre ellos GBM y XGBoost) entrenados con 2014–2019 y evaluados en la primera ola de COVID. Probaron darle menos peso a los datos viejos y entrenar solo con los últimos 6 meses: "did not have an impact on the robustness of the models". Límites: su "peso" multiplicaba las variables, no las filas, y el COVID estaba en el testeo, no en el entrenamiento.*

### Fuentes complementarias (papers, blogs y documentación)

* **Shimodaira, H. (2000).** *Improving predictive inference under covariate shift by weighting the log-likelihood function.* Journal of Statistical Planning and Inference, 90(2), 227–244. DOI: [10.1016/S0378-3758(00)00115-4](https://doi.org/10.1016/S0378-3758(00)00115-4). *Ponderar mejora bajo covariate shift solo si el modelo está mal especificado; con un modelo bien especificado, la estimación sin pesos es asintóticamente óptima. Sus pesos son cocientes de densidades, no pesos por antigüedad: el traslado es inferencia nuestra.*
* **Gogolashvili, D., Zecchin, M., Kanagawa, M., & Kountouris, M. (2023).** *When is importance weighting correction needed for covariate shift adaptation?* arXiv:2303.04020. *La corrección por pesos puede no ser necesaria con modelos no paramétricos bien especificados (a favor de B), pero sí con modelos mal especificados (a favor de A).*
* **Byrd, J., & Lipton, Z. C. (2019).** *What is the effect of importance weighting in deep learning?* ICML, PMLR 97. *En redes sobreparametrizadas el efecto del peso se diluye con el entrenamiento. Evidencia indirecta para B, en deep learning y no en GBDT.*
* **Yao, H., Choi, C., Lee, Y., Koh, P. W., & Finn, C. (2022).** *Wild-Time: A benchmark of in-the-wild distribution shift over time.* NeurIPS Datasets and Benchmarks. arXiv:2211.14238. *Con 13 métodos, el desempeño cae en promedio un 20% fuera de distribución y los métodos existentes no logran cerrar esa brecha.*
* **Tsymbal, A. (2004).** [*The problem of concept drift: definitions and related work*](https://ar5iv.labs.arxiv.org/html/1010.4784). *La estrategia adecuada depende del tipo de drift: para drift súbito se prefieren las ventanas. No hay un ganador universal.*
* **Documentación de LightGBM — [Parameters](https://lightgbm.readthedocs.io/en/latest/Parameters.html)** e **[issue #5553](https://github.com/microsoft/LightGBM/issues/5553).** *`min_sum_hessian_in_leaf` es la suma mínima de hessianos por hoja y actúa como regularización. Según un colaborador de LightGBM, "the weights are used when computing the gradients and hessians": cambiar los pesos cambia la regularización efectiva. Por eso la BO se vuelve a correr en cada tratamiento y los pesos se normalizan a media 1.*
* **Kish (1965), vía [PracTools – Design effects](https://stat.ethz.ch/CRAN/web/packages/PracTools/vignettes/Design-effects.html).** *$deff = 1 + CV^2(w)$ y $ESS = n / deff = (\sum w)^2 / \sum w^2$: los pesos desiguales reducen el tamaño muestral efectivo.*
* **Lakens, D. (2017).** *Equivalence tests: A practical primer for t tests, correlations, and meta-analyses.* Social Psychological and Personality Science, 8(4), 355–362. DOI: [10.1177/1948550617697177](https://doi.org/10.1177/1948550617697177). *TOST: para afirmar equivalencia hay que rechazar que el efecto supere un margen $\pm\delta$ fijado de antemano; "no significativo" no es "equivalente".*
* **Demšar, J. (2006).** *Statistical comparisons of classifiers over multiple data sets.* Journal of Machine Learning Research, 7, 1–30. *Wilcoxon de rangos con signo para comparar dos clasificadores sobre unidades pareadas; acá, las semillas primigenias.*
* *A favor de A:*
  * **Liu, Z., Godahewa, R., Bandara, K., & Bergmeir, C. (2023).** [*Handling concept drift in global time series forecasting*](https://ar5iv.labs.arxiv.org/html/2304.01512). *Con LightGBM, el peso exponencial a lo reciente bajó el error entre 6 y 10% con drift súbito o incremental; con drift gradual la mejora fue menor al 1% y algunas variantes empeoraron. Solo datos simulados.*
  * **Jain, N., & Shenoy, P.** [*Instance-conditional timescales of decay for non-stationary learning*](https://arxiv.org/html/2212.05908v2) (arXiv:2212.05908) y [blog de Google Research (2024)](https://research.google/blog/learning-the-importance-of-training-data-under-concept-drift/). *Mejoras de hasta 15% con pesos **aprendidos** por instancia y antigüedad. Reportan superar a un decaimiento de escala única, como nuestro T1.*
  * [Kaggle M5 — discusión sobre pesos temporales](https://www.kaggle.com/c/m5-forecasting-accuracy/discussion/144067). *Opinión de competidores; contenido no verificado.*

> **Nota:** no encontramos evidencia empírica directa sobre ponderación temporal en churn bancario con gradient boosting, ni antecedentes de un placebo con pesos permutados entre meses. Este experimento aporta esa evidencia.

---

## 5. Sesgos y Preconceptos de los Integrantes

* **Verónica Ester Monzón:** Mi creencia previa va en contra de nuestra hipótesis: intuyo que la cuarentena de 2020 fue un shock aberrante y que darle menos peso va a ayudar. A la vez, desconfío de cualquier intervención que se evalúe sin un grupo control adecuado: si dos tratamientos difieren en más de una cosa, no sé a cuál atribuirle el efecto. Por eso incluimos un placebo.
* **Fray Campos:** *(A completar.)*

---

## 6. Diseño Experimental (*Ceteris Paribus* Estricto)

**Se mantiene fijo, igual que el baseline:** data quality, clase ternaria de los notebooks de la cátedra, FE histórico (lags y delta lags de orden 1 y 2; 762 columnas), parámetros fijos y bordes de búsqueda de LightGBM, BO de **10 evaluaciones en total** (`mlr3mbo`, solo diseño inicial y sin iteraciones bayesianas, según la cátedra en el issue #1 del repo), métrica de la BO = AUC en validación, undersampling 0,1, training_pct 70, 10 semillas en el entrenamiento final y meses de cada rol (tabla abajo). La decisión entre tratamientos se toma por ganancia en el testeo (BAJA+2 = +1.072.500; resto = −27.500).

**Código:** T0, T1, T2 y T3 corren con el mismo código del baseline *(a definir con Fray: baseline del repo compartido, actualizado a todos los meses, o `baseline.R`)*.

**Única intervención:** el vector `weight` de `lgb.Dataset`. Los pesos se aplican en el training de la BO y en el entrenamiento final. La validación de la BO y el testeo se evalúan sin pesos, para que todos los tratamientos se midan con la misma vara.

**Workflow completo por tratamiento:** siguiendo la bitácora de la cátedra, cada tratamiento corre el workflow entero —**incluida la BO**— en lugar de reusar los hiperparámetros del baseline. Los pesos cambian el gradiente y el hessiano de cada fila, así que el óptimo de hiperparámetros también puede cambiar.

**Semillas primigenias:** se usan las mismas **10 semillas primigenias** en todos los tratamientos (o el máximo que permita el cómputo, con un mínimo de 6), tomadas de las semillas de ambos integrantes. Cada primigenia corre su workflow completo (BO + entrenamiento final de 10 semillas), y eso da un vector de ganancias por tratamiento.

**Normalización:** en la BO y en cada semilla del entrenamiento final, después del undersampling, los pesos se reescalan a media 1 sobre las filas de entrenamiento, para que la masa total de hessianos sea comparable con la de $w = 1$.

### Meses por rol

| Rol | Meses | Control |
| :--- | :--- | :--- |
| Entrenamiento y BO | 201901 a 202104 | La BO usa un 70/30 aleatorio dentro de estos meses. |
| Gap | 202105 | Replica la estructura de producción (202107 no tiene la clase completa). |
| Testeo | 202106 | Tiene clase conocida y queda fuera del entrenamiento y de la BO. |
| Producción (competencia 2) | 202108 | Se vuelve a correr el workflow ganador entero. |

*Lags:* los lags de orden 1 y 2 de 202106 usan atributos (no la clase) de 202105 y 202104. No introducen información de la clase del mes de testeo.

### Tratamientos ($\Delta t$ = meses de antigüedad respecto de 202104)

| Tratamiento | Pesos | Qué aísla |
| :--- | :--- | :--- |
| **T0 — Baseline** | $w = 1$ | Referencia. |
| **T1 — Decaimiento temporal** | $w = 0.5^{\Delta t / 12}$ (vida media de 12 meses) | Efecto de ponderar por recencia. |
| **T2 — Placebo** | Los pesos mensuales de T1 permutados al azar entre meses; una permutación distinta por cada semilla primigenia, renormalizada a media 1 | Misma dispersión de pesos (ESS aproximadamente igual) sin orden temporal. Si T1 ≈ T2, la diferencia con T0 no se debe a la recencia. |
| **T3 — Ventana dura con igual ESS** | $w = 1$ en los últimos $k$ meses y 0 en el resto, con $k$ tal que el ESS se aproxime al de T1 | Seleccionar frente a ponderar (Klinkenberg, 2004). |

*Grupo A:* no respondió al 02-nov. T1 es un esquema propio del Grupo B, lo que además asegura que los diseños sean disjuntos.

*Costo:* cada tratamiento son hasta 10 workflows completos (uno por semilla primigenia). En total, hasta 40.

### Fuera del recorte (Futuros)

Quedan como extensiones si los resultados no son concluyentes:
* **Dosis-respuesta:** vida media de 6, 12 y 24 meses. Si la recencia importa, la ganancia debería variar de forma monótona; una curva plana apoya a B.
* **Dirección invertida:** más peso a los meses viejos (control negativo).
* **Sin normalizar:** los pesos de T1 sin reescalar, para medir el efecto sobre la regularización.
* **Réplicas en otros meses de testeo:** 202105 y 202104, con los meses de entrenamiento desplazados (walk-forward).

---

## 7. Protocolo de Validación y Métricas de Éxito

* **Métrica primaria:** ganancia máxima del **ensamble** de 10 semillas en 202106 y cantidad de envíos en la que se alcanza, como pide la diapositiva del baseline. Hay un valor por semilla primigenia.
* **Ensamble vs. media (bitácora de la cátedra):** la ganancia del ensamble no es lo mismo que la media de las ganancias de cada semilla. Se decide por el ensamble; la media por semilla se reporta como descriptiva.
* **Robustez:** ganancia en cortes fijos de envíos alrededor del máximo, para no depender de un único punto de la curva.
* **Comparación pareada:** para cada semilla primigenia $s$, $\Delta_s = G_{T_i,s} - G_{T0,s}$, con pruebas de Wilcoxon de rangos con signo (Demšar, 2006). Las dos comparaciones principales se testean en secuencia fija: H1 (T1 vs. T0) primero y H2 (T1 vs. T2) después, así que no hace falta corregir por multiplicidad.
* **No superioridad y equivalencia (Lakens, 2017):** H1 se contrasta con un Wilcoxon unilateral sobre $\Delta_s - \delta$ ($H_0: \Delta \geq \delta$). H2 se contrasta con TOST dentro de $\pm\delta$. El margen $\delta$ es el desvío estándar de la ganancia de T0 entre semillas primigenias; se fija después de correr T0 y antes de correr T1–T3, y se registra con fecha *(a confirmar con Fray)*.
* **Lectura de resultados:**

  | | T1 > T0 | T1 ≈ T0 o T1 < T0 |
  | :--- | :--- | :--- |
  | **T1 > T2** (el orden temporal importa) | Gana A: la recencia mejora la ganancia. | Caso no esperado: se discute. |
  | **T1 ≈ T2** (el orden no importa) | Gana B: ayudan los pesos, no la recencia. | Gana B: ponderar no mejora. |

  Si no se rechaza $H_0$ en H1 y T1 tampoco supera a T0 en más de $\delta$, la conclusión es "inconcluso", no "son iguales".

* **Control de bordes de la BO:** en cada workflow se revisa si el mejor trial toca algún borde del rango de búsqueda. Si lo toca, se informa y se discute.
* **Diagnósticos:** ESS de cada vector de pesos, proporción ponderada de positivos (BAJA+1 y BAJA+2) en el training, hiperparámetros elegidos por la BO en cada tratamiento e importancia de variables (lags y deltas frente a variables del mes).

---

## 8. Limitaciones Reconocidas

1. **Sin walk-forward:** la conclusión descansa en un solo mes de testeo (202106). Repetir los 30–40 workflows en otros meses multiplica el costo, así que las réplicas quedan como Futuros.
2. **Pocas unidades pareadas:** con 10 semillas primigenias (o menos, si el cómputo no alcanza) el contraste de no superioridad, aunque es unilateral, tiene poca potencia. Si $\delta$ es chico, el resultado más probable es "inconcluso".
3. **Elección de $\delta$:** basar el margen en la variabilidad entre semillas es una decisión nuestra. Otro criterio, por ejemplo uno económico, podría cambiar la conclusión.
4. **BO corta:** 10 evaluaciones sin iteraciones bayesianas se parecen más a una búsqueda al azar, así que parte de las diferencias entre tratamientos podría ser ruido de la búsqueda. Si algún hiperparámetro queda contra un borde, la comparación puede estar midiendo los límites del rango.
5. **Normalización y undersampling:** la normalización iguala la masa total de hessianos, pero no su distribución entre hojas. Además, los pesos se combinan con el undersampling 0,1, que ya reescala implícitamente la clase mayoritaria.
6. **Los pesos cambian también la proporción de positivos:** como la tasa de bajas varía entre meses, reponderar los meses cambia la prevalencia efectiva de la clase positiva en el training. Se reporta para cada tratamiento.
7. **Placebo aproximado:** como los meses tienen distinta cantidad de clientes, permutar los pesos entre meses no conserva exactamente el ESS. Con pocas primigenias, las permutaciones tampoco cubren todas las combinaciones posibles.
8. **Ventana dura con ESS aproximado:** como $k$ es un número entero de meses, el ESS de T3 solo se puede igualar aproximadamente al de T1.
9. **Esquemas de pesos limitados:** solo se prueba un decaimiento fijo por antigüedad. Los pesos aprendidos por instancia (Jain y Shenoy) quedan fuera del alcance.
10. **Interacción con los lags sin testear:** la idea de que los lags y deltas vuelven redundantes a los pesos no se prueba directamente, porque requeriría modificar el FE y romper el *ceteris paribus*.
11. **Sin coordinación con el Grupo A:** al 02-nov no conocemos su diseño. Si su esquema de pesos difiere mucho de T1, los resultados de ambos grupos no son directamente comparables.
12. **Costo computacional:** hasta 40 workflows completos con BO; según lo informado en Zulip, el baseline usa cerca de 40 GB de RAM y 12 vCPU *(a confirmar en nuestra VM)*. Si el cómputo no alcanza, primero se reduce T3 y después el número de primigenias, y se informa.

---
