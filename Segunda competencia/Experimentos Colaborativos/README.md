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
* **Nuestra presentación (Grupo B):** [experimentos_colaborativos_campos_monzon (Google Slides)](https://docs.google.com/presentation/d/1Ht9rjh2ypUyzs9tYzkwG9omHKbGZOG3W/edit?usp=sharing).


---

## 2. Cronograma e Hitos

| Fecha | Instancia | Formato / Requisitos |
| :--- | :--- | :--- |
| **Jue 29-oct-2026** | **Inscripción y selección de tema** | Registro de pareja y tema antagónico en la planilla compartida. |
| **Jue 05-nov-2026** | **Presentación Preliminar (Hito 1)** | Presencial (Cero+Infinito). **3 minutos por grupo**. Solo el diseño metodológico, en el Google Slides compartido: título, hipótesis, bibliografía, sesgos, diseño y limitaciones. Sin contar el baseline. |
| **Jue 03-dic-2026** | **Presentación Definitiva (Hito 2)** | Exposición plenaria (10-12 min). Hallazgos consolidados, curvas de ganancia y código reproducible en repositorio público. |

---

## 3. Hipótesis Antagónica

* **Grupo A (pro-ponderación):** Nicolás Baranek · Rodrigo Palpa. *(Hipótesis y esquema de pesos a confirmar.)*
* **Hipótesis B:** ponderar los meses del entrenamiento por recencia **no mejora la ganancia más allá de un margen δ** respecto de no ponderar. Si la ponderación de A mejora, no es por la recencia: un placebo con los mismos pesos asignados a meses al azar rinde igual.

**Tipo de estudio:** ensayo clinico cruzado (crossover), no ciego, de **no superioridad**, controlado con placebo, de 3 brazos. 

**Objetivo principal**
Evaluar si la ponderación temporal de los meses del entrenamiento propuesta por el Grupo A aumenta la ganancia máxima del ensamble en 202106 respecto del baseline sin ponderar (sin tratamiento), con un margen de no superioridad δ fijado de antemano, sobre 10 semillas primigenias.

**Objetivos secundarios**
1. Comparar la ganancia de la ponderación del Grupo A con la de un placebo (los mismos pesos asignados a meses al azar), para determinar si un eventual efecto se debe a la recencia.
2. Comparar la ganancia de la ponderación del Grupo A con la de los mismos pesos invertidos (control negativo).
3. Describir, en cada brazo, el tamaño efectivo de la muestra, la proporción ponderada de positivos y los hiperparámetros elegidos por la BO.
4. Analizar la variabilidad de la ganancia entre semillas primigenias en cada brazo, distinguiendo la ganancia del ensamble de la media por semilla.
5. Determinar si la ponderación temporal debe incorporarse al workflow de la Segunda Competencia.

**Hipótesis operativas** (unidad de análisis: semilla primigenia; outcome: ganancia máxima del ensamble en 202106)

| | Comparación | Marco | B se sostiene si… |
| :--- | :--- | :--- | :--- |
| **H1 (primaria)** | Droga A vs. Sin tratamiento | No superioridad | La droga A no supera al baseline en más de δ. |
| **H2 (secundaria)** | Droga A vs. Placebo | Equivalencia (±δ) | Rinden igual dentro de ±δ. |
| **Control negativo** | Droga A vs. Invertidos | Equivalencia (±δ) | Rinden igual dentro de ±δ. |

*Cuándo se refuta B:* si la droga A supera al baseline en más de δ **y** además supera al placebo y a los invertidos; es decir, si ponderar mejora la ganancia y la mejora se debe a la recencia.

*Orden de las pruebas:* H1, después H2 y al final el control negativo, en un orden fijado de antemano (prueba jerárquica, como outcomes primario y secundarios en un ensayo clínico). Por eso cada prueba usa α = 0,05 sin corregir por multiplicidad.

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
* **Documentación de LightGBM — [Parameters](https://lightgbm.readthedocs.io/en/latest/Parameters.html)** e **[issue #5553](https://github.com/microsoft/LightGBM/issues/5553).** *`min_sum_hessian_in_leaf` es la suma mínima de hessianos por hoja y actúa como regularización. Según un colaborador de LightGBM, "the weights are used when computing the gradients and hessians": cambiar los pesos cambia la regularización efectiva. Por eso la BO se vuelve a correr en cada brazo y los pesos se normalizan a media 1.*
* **Kish (1965), vía [PracTools – Design effects](https://stat.ethz.ch/CRAN/web/packages/PracTools/vignettes/Design-effects.html).** *$deff = 1 + CV^2(w)$ y $ESS = n / deff = (\sum w)^2 / \sum w^2$: los pesos desiguales reducen el tamaño muestral efectivo.*
* **Lakens, D. (2017).** *Equivalence tests: A practical primer for t tests, correlations, and meta-analyses.* Social Psychological and Personality Science, 8(4), 355–362. DOI: [10.1177/1948550617697177](https://doi.org/10.1177/1948550617697177). *TOST: para afirmar equivalencia hay que rechazar que el efecto supere un margen $\pm\delta$ fijado de antemano; "no significativo" no es "equivalente".*
* **Demšar, J. (2006).** *Statistical comparisons of classifiers over multiple data sets.* Journal of Machine Learning Research, 7, 1–30. *Wilcoxon de rangos con signo para comparar dos clasificadores sobre unidades pareadas; acá, las semillas primigenias.*
* *A favor de A:*
  * **Liu, Z., Godahewa, R., Bandara, K., & Bergmeir, C. (2023).** [*Handling concept drift in global time series forecasting*](https://ar5iv.labs.arxiv.org/html/2304.01512). *Con LightGBM, el peso exponencial a lo reciente bajó el error entre 6 y 10% con drift súbito o incremental; con drift gradual la mejora fue menor al 1% y algunas variantes empeoraron. Solo datos simulados.*
  * **Jain, N., & Shenoy, P.** [*Instance-conditional timescales of decay for non-stationary learning*](https://arxiv.org/html/2212.05908v2) (arXiv:2212.05908) y [blog de Google Research (2024)](https://research.google/blog/learning-the-importance-of-training-data-under-concept-drift/). *Mejoras de hasta 15% con pesos **aprendidos** por instancia y antigüedad. Reportan superar a un decaimiento de escala única, como un decaimiento fijo.*
  * [Kaggle M5 — discusión sobre pesos temporales](https://www.kaggle.com/c/m5-forecasting-accuracy/discussion/144067). *Opinión de competidores; contenido no verificado.*

> **Nota:** no encontramos evidencia empírica directa sobre ponderación temporal en churn bancario con gradient boosting, ni antecedentes de un placebo con pesos asignados a meses al azar. Este experimento aporta esa evidencia.

---

## 5. Sesgos y Preconceptos de los Integrantes

* **Verónica Ester Monzón:** Mi intuición clínica es que el COVID fue un shock y que conviene restarle peso, en contra de lo que defendemos. Además, mi formación me hace sobrevalorar el placebo: tiendo a no creer un resultado si no se descartó el efecto placebo, aunque la diferencia sea grande.
* **Fray Campos:** El comportamiento humano presenta rezagos frente a shocks, similares a los efectos diferidos de la política monetaria. Mi sesgo apunta a que la ponderación de atributos según shocks puntuales no necesariamente mejora la predicción de comportamientos futuros.

---

## 6. Diseño Experimental (*Ceteris Paribus* Estricto)

**Se mantiene fijo, igual que el baseline:** data quality, clase ternaria de los notebooks de la cátedra, FE histórico (lags y delta lags de orden 1 y 2; 762 columnas), parámetros fijos y bordes de búsqueda de LightGBM, BO de **10 evaluaciones en total** (`mlr3mbo`, solo diseño inicial y sin iteraciones bayesianas, según la cátedra en el issue #1 del repo), métrica de la BO = AUC en validación, undersampling 0,1, training_pct 70, 10 semillas en el entrenamiento final y meses de cada rol (tabla abajo). La comparación entre brazos se hace por ganancia en el testeo (BAJA+2 = +1.072.500; resto = −27.500).

**Código:** los tres brazos corren el baseline del repo compartido ([germandasr/DMEyF_Exp_Colaborativos](https://github.com/germandasr/DMEyF_Exp_Colaborativos)), actualizado a todos los meses. La única diferencia entre brazos es el peso de cada mes: iguales en todo, salvo en la intervención.

**Única intervención:** el vector `weight` de `lgb.Dataset`. Los pesos se aplican en el training de la BO y en el entrenamiento final. La validación de la BO y el testeo se evalúan sin pesos, para que todos los brazos se midan con la misma vara.

**Workflow completo por brazo:** siguiendo la bitácora de la cátedra, cada brazo corre el workflow entero —**incluida la BO**— en lugar de reusar los hiperparámetros del baseline. Los pesos cambian el gradiente y el hessiano de cada fila, así que el óptimo de hiperparámetros también puede cambiar.

**Semillas primigenias:** las mismas **10 semillas primigenias** en los tres brazos, tomadas de las semillas de ambos integrantes (bitácora: "al menos 10 semillas; el mismo vector de semillas para el baseline y para el experimento"). Cada primigenia corre su workflow completo (BO + entrenamiento final de 10 semillas), y eso da un vector de ganancias por brazo.

**Normalización:** en la BO y en cada semilla del entrenamiento final, después del undersampling, los pesos se reescalan a media 1 sobre las filas de entrenamiento, para que la masa total de hessianos sea comparable con la de $w = 1$.

### Meses por rol

| Rol | Meses | Control |
| :--- | :--- | :--- |
| Entrenamiento y BO | 201901 a 202104 | La BO usa un 70/30 aleatorio dentro de estos meses. |
| Gap | 202105 | Replica la estructura de producción (202107 no tiene la clase completa). |
| Testeo | 202106 | Tiene clase conocida y queda fuera del entrenamiento y de la BO. |
| Producción (competencia 2) | 202108 | Se vuelve a correr el workflow ganador entero. |

*Lags:* los lags de orden 1 y 2 de 202106 usan atributos (no la clase) de 202105 y 202104. No introducen información de la clase del mes de testeo.

### Brazos

| Brazo | Pesos | En el ensayo clínico | Qué aísla |
| :--- | :--- | :--- | :--- |
| **Sin tratamiento** | $w = 1$ (baseline del repo compartido) | Control sin tratamiento | Referencia. |
| **Placebo** | Los pesos de A, asignados a meses al azar; una asignación distinta por semilla primigenia, renormalizada a media 1 | La misma pastilla, sin el principio activo | El efecto de tener pesos, sin el orden temporal. |
| **Invertidos** | Los pesos de A al revés: más peso a los meses viejos | Control negativo: la droga "al revés" | Si la recencia importa, debería rendir peor que la droga. |
| *Droga A (la corre el Grupo A)* | *El esquema de pesos de A* | *La droga* | — |

*Dependencia del Grupo A:* el placebo y los invertidos se construyen con los pesos de A, y la comparación usa los resultados de su droga. Para comparar de a pares, la droga tiene que correr con el mismo baseline y las mismas 10 semillas primigenias *(a coordinar con el Grupo A al inicio, como prevé la consigna)*.

*Costo:* cada brazo son 10 workflows completos (uno por semilla primigenia). En total, 30 workflows del Grupo B.

### Fuera del recorte (Futuros)

Quedan como extensiones si los resultados no son concluyentes:
* **Sin normalizar:** los pesos de A sin reescalar, para medir el efecto sobre la regularización.
* **Réplicas en otros meses de testeo:** 202105 y 202104, con los meses de entrenamiento desplazados (walk-forward).

---

## 7. Protocolo de Validación y Métricas de Éxito

* **Métrica primaria:** ganancia máxima del **ensamble** de 10 semillas en 202106 y cantidad de envíos en la que se alcanza, como pide la diapositiva del baseline. Hay un valor por semilla primigenia.
* **Ensamble vs. media (bitácora de la cátedra):** la ganancia del ensamble no es lo mismo que la media de las ganancias de cada semilla. Se decide por el ensamble; la media por semilla se reporta como descriptiva.
* **Robustez:** ganancia en cortes fijos de envíos alrededor del máximo, para no depender de un único punto de la curva.
* **Comparación pareada:** para cada semilla primigenia $s$, $\Delta_s = G_{A,s} - G_{\text{brazo},s}$, donde $G_{A,s}$ es la ganancia de la droga A y $G_{\text{brazo},s}$ la del brazo de B con la misma primigenia. Se usan pruebas de Wilcoxon de rangos con signo (Demšar, 2006). Las tres comparaciones se testean en el orden fijo de la sección 3 (H1 → H2 → control negativo), así que no hace falta corregir por multiplicidad.
* **No superioridad y equivalencia (Lakens, 2017):**
  * **Margen δ:** es la diferencia mínima de ganancia que consideramos relevante. Si la droga A gana por menos que δ, la diferencia puede deberse solo al cambio de semilla. Se calcula como el desvío estándar de la ganancia del brazo Sin tratamiento entre las 10 semillas primigenias, es decir, cuánto varía la ganancia solo por la semilla. Se fija después de correr ese brazo y antes de correr el placebo y los invertidos, y se registra con fecha, para no elegirlo mirando los resultados *(a confirmar con Fray)*.
  * **H1 (no superioridad):** busca mostrar que la droga A no supera al baseline por más de δ. Se usa un Wilcoxon unilateral sobre las diferencias menos el margen ($\Delta_s - \delta$; $H_0: \Delta \geq \delta$). Es unilateral porque a B le alcanza con que A no sea mejor; si A rinde peor, B también se sostiene.
  * **H2 y control negativo (equivalencia):** buscan mostrar que la droga A y el brazo de B rinden igual, es decir, que la diferencia queda dentro de la banda de $-\delta$ a $+\delta$. Se usa TOST (*two one-sided tests*): una prueba muestra que A no es peor por más de δ y otra que no es mejor por más de δ. Si las dos son significativas, se declaran equivalentes.
  * **Inconcluso no es lo mismo que iguales:** si ninguna prueba es significativa, la conclusión es "inconcluso". No encontrar diferencia no prueba que no exista, igual que en un ensayo clínico con pocos pacientes.

* **Lectura de resultados:**

  | | A supera al Sin tratamiento por más de δ | A no supera al Sin tratamiento por más de δ |
  | :--- | :--- | :--- |
  | **A supera al Placebo y a los Invertidos** (el orden temporal importa) | Gana A: la recencia mejora la ganancia. | Caso no esperado: se discute. |
  | **A ≈ Placebo o A ≈ Invertidos** (el orden temporal no importa) | Gana B: ayudan los pesos, no la recencia. | Gana B: ponderar no mejora. |

* **Control de bordes de la BO:** en cada workflow se revisa si el mejor trial toca algún borde del rango de búsqueda. Si lo toca, se amplía ese rango, se vuelve a correr la BO y se documenta el cambio, como pide la bitácora de la cátedra. El rango ampliado se aplica a los tres brazos, para que sigan difiriendo solo en los pesos *(y se le informa al Grupo A, para que la droga use el mismo rango si considera)*.

* **Diagnósticos:** en cada brazo se reportan el tamaño efectivo de la muestra (ESS de Kish: cuántas filas "valen" realmente una vez aplicados los pesos), la proporción ponderada de positivos (BAJA+1 y BAJA+2) en el training, los hiperparámetros elegidos por la BO y la importancia de variables (lags y deltas frente a variables del mes).

---

## 8. Limitaciones Reconocidas

## 8. Limitaciones Reconocidas

1. **Sin walk-forward:** la conclusión descansa en un solo mes de testeo (202106). Repetir los 30 workflows en otros meses multiplica el costo, así que las réplicas quedan como Futuros.
2. **Pocas unidades pareadas:** con 10 semillas primigenias, el contraste de no superioridad tiene poca potencia aunque sea unilateral. Si $\delta$ es chico, el resultado más probable es "inconcluso".
3. **Elección de $\delta$:** basar el margen en la variabilidad entre semillas es una decisión nuestra. Otro criterio, por ejemplo uno económico, podría cambiar la conclusión.
4. **BO corta:** 10 evaluaciones sin iteraciones bayesianas se parecen más a una búsqueda al azar, así que parte de las diferencias entre brazos podría ser ruido de la búsqueda y no efecto de los pesos.
5. **Normalización y undersampling:** la normalización iguala la masa total de hessianos, pero no su distribución entre hojas. Además, los pesos se combinan con el undersampling 0,1, que ya reescala implícitamente la clase mayoritaria.
6. **Los pesos cambian también la proporción de positivos:** como la tasa de bajas varía entre meses, reponderar los meses cambia la prevalencia efectiva de la clase positiva en el training. Se reporta para cada brazo.
7. **Placebo aproximado:** como los meses tienen distinta cantidad de clientes, asignar los pesos de A a meses al azar no conserva exactamente el ESS. Con 10 primigenias, las asignaciones al azar tampoco cubren todas las combinaciones posibles.
8. **Un solo esquema de pesos:** se evalúa únicamente el esquema que propone el Grupo A. Otras formas de ponderar, y los pesos aprendidos por instancia (Jain y Shenoy), quedan fuera del alcance.
9. **Interacción con los lags sin testear:** la idea de que los lags y deltas vuelven redundantes a los pesos no se prueba directamente, porque requeriría modificar el FE y romper el *ceteris paribus*.
10. **Dependencia del Grupo A:** el placebo, los invertidos y las comparaciones dependen de los pesos y los resultados de la droga A. Si A no corre con el mismo baseline, las mismas 10 semillas primigenias y los mismos rangos de la BO, la comparación pareada no es válida.
11. **Costo computacional:** 30 workflows completos con BO del lado del Grupo B, más los de la droga A. Según lo informado en Zulip, el baseline usa cerca de 40 GB de RAM y 12 vCPU *(a confirmar en nuestra VM)*.
12. **No ciego:** sabemos qué brazo corre cada workflow. Se mitiga fijando δ y el orden de las pruebas antes de ver los resultados.

---
