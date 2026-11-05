## ----setup, include = FALSE---------------------------------------------------
knitr::opts_chunk$set(
  collapse  = TRUE,
  comment   = "#>",
  eval      = FALSE,  # Stan/brms chunks are too slow for automated builds
  fig.width = 7,
  fig.height = 4.5
)

## ----libraries----------------------------------------------------------------
# library(ErrorTracer)
# library(glmnet)      # for elastic net (Suggests)
# library(ggplot2)
# 
# # Load the bundled simulated dataset
# data(et_sim)

## ----demo-settings------------------------------------------------------------
# # Use small MCMC settings for this tutorial.
# # In a real analysis: CHAINS = 4, ITER = 2000 (or more).
# CHAINS <- 2L
# ITER   <- 1000L
# SEED   <- 42L

## ----data-setup, include = FALSE, eval = TRUE---------------------------------
library(ErrorTracer)
data(et_sim)

## ----data-overview, eval = TRUE-----------------------------------------------
str(et_sim, max.level = 2)

## ----head-train, eval = TRUE--------------------------------------------------
head(et_sim$train[, 1:6])

## ----true-params, eval = TRUE-------------------------------------------------
# True coefficients — known because the data are simulated
et_sim$true_params

## ----forecast-predictors, eval = TRUE-----------------------------------------
# Forecast predictors sit above the training range in Tmean (warming trend)
head(et_sim$forecast[et_sim$forecast$cluster_id == "A", 1:5])

## ----plot-training-data, fig.cap="Simulated allele-frequency change over the training period."----
# ggplot(et_sim$train, aes(x = year, y = z_diff, colour = cluster_id)) +
#   geom_line() +
#   geom_point(size = 2) +
#   labs(
#     x       = "Year",
#     y       = expression(italic(z)[diff]),
#     colour  = "Cluster"
#   ) +
#   et_theme()

## ----plot-predictors, fig.cap="Standardised climate predictors over the training and forecast periods."----
# # Climate predictors over the full period — warming trend visible in Tmean
# all_years <- rbind(
#   transform(et_sim$train[et_sim$train$cluster_id == "A",
#                           c("year", "Tmean", "PPT", "SWE")],
#             period = "Training"),
#   transform(et_sim$forecast[et_sim$forecast$cluster_id == "A",
#                              c("year", "Tmean", "PPT", "SWE")],
#             period = "Forecast")
# )
# 
# all_long <- reshape(all_years, direction = "long",
#                     varying = c("Tmean", "PPT", "SWE"),
#                     v.names = "value", timevar = "predictor",
#                     times   = c("Tmean", "PPT", "SWE"))
# 
# ggplot(all_long, aes(x = year, y = value,
#                      colour = period, group = period)) +
#   geom_line() +
#   geom_point(size = 1.8) +
#   facet_wrap(~ predictor, ncol = 3) +
#   labs(
#     x      = "Year", y = "Standardised value", colour = "Period"
#   ) +
#   et_theme()

## ----enet-fit-----------------------------------------------------------------
# train_A <- et_sim$train[et_sim$train$cluster_id == "A", ]
# 
# x_train <- as.matrix(train_A[, c("Tmean", "PPT", "SWE")])
# y_train <- train_A$z_diff
# 
# set.seed(42)
# cv_fit_A <- glmnet::cv.glmnet(
#   x     = x_train,
#   y     = y_train,
#   alpha = 0.5          # 0 = ridge, 1 = lasso, 0.5 = elastic net
# )
# 
# # Coefficient estimates at lambda.min
# coef(cv_fit_A, s = "lambda.min")
# # 4 x 1 sparse Matrix of class "dgCMatrix"
# #             lambda.min
# # (Intercept)  0.0453
# # Tmean        0.4983
# # PPT         -0.2722
# # SWE          0.1683

## ----enet-plot, fig.cap="Cross-validated elastic net for cluster A."----------
# plot(cv_fit_A)

## ----extract-priors-----------------------------------------------------------
# prior_spec_A <- extract_priors(
#   model      = cv_fit_A,
#   lambda     = "lambda.min",
#   multiplier = 2.0,   # prior SD = 2 × |elastic-net coef|
#   min_sd     = 0.10   # floor: avoids spike priors on near-zero coefficients
# )
# 
# print(prior_spec_A)
# # ErrorTracer prior specification
# #   Method      : glmnet
# #   Predictors  : 3
# #   Multiplier  : 2
# #   Min SD      : 0.1
# #   Shrinkage   : zero (prior means at 0; regularizing)
# #   Coefficients:
# #     Tmean                 prior mean =   0.0000  sd =   0.9966  (coef =   0.4983)
# #     PPT                   prior mean =   0.0000  sd =   0.5444  (coef =  -0.2722)
# #     SWE                   prior mean =   0.0000  sd =   0.3365  (coef =   0.1683)

## ----et-fit-------------------------------------------------------------------
# fit_A <- et_fit(
#   formula = z_diff ~ Tmean + PPT + SWE,
#   data    = train_A,
#   priors  = prior_spec_A,
#   chains  = CHAINS,
#   iter    = ITER,
#   warmup  = ITER %/% 2L,
#   cores   = CHAINS,
#   seed    = SEED
# )
# 
# print(fit_A)
# # ErrorTracer model (et_model)
# #   Formula : z_diff ~ Tmean + PPT + SWE
# #   n obs   : 100
# #   Chains  : 2   Iter: 1000   Warmup: 500
# #   Priors  : informed (glmnet, 3 predictors)
# #   Rhat max: 1.014

## ----et-summary---------------------------------------------------------------
# summary(fit_A)
# # === ErrorTracer model summary ===
# #
# # --- Fixed effects ---
# #              Estimate  Est.Error     Q2.5    Q97.5
# # Intercept    0.041      0.104    -0.162    0.246
# # Tmean        0.666      0.113     0.438    0.888
# # PPT         -0.487      0.200    -0.909   -0.123
# # SWE          0.406      0.206     0.023    0.827

## ----et-diagnose--------------------------------------------------------------
# diag_A <- et_diagnose(fit_A, loo = TRUE)
# 
# # Convergence
# diag_A$convergence
# # $rhat_max
# # [1] 1.004         # all chains well below 1.05 threshold
# #
# # $rhat_all_ok
# # [1] TRUE
# #
# # $neff_min
# # [1] 0.275         # lowest effective-sample-size ratio
# #
# # $neff_all_ok
# # [1] TRUE          # all Neff ratios > 0.10
# #
# # $n_divergences
# # [1] 0             # no divergent transitions

## ----loo-results--------------------------------------------------------------
# diag_A$loo[c("elpd_loo", "p_loo", "looic", "n_bad_pareto_k")]
# # $elpd_loo
# # [1] -14.55
# #
# # $p_loo
# # [1] 4.00          # effective parameters ≈ 4 (intercept, 3 betas); sigma
# #                   # is implicit — consistent with a 4-parameter model
# # $looic
# # [1] 29.10
# #
# # $n_bad_pareto_k
# # [1] 0             # no influential observations (Pareto k > 0.7)

## ----et-predict---------------------------------------------------------------
# fcast_A <- et_sim$forecast[et_sim$forecast$cluster_id == "A", ]
# 
# pred_A <- et_predict(
#   model     = fit_A,
#   newdata   = fcast_A,
#   env_noise = et_sim$env_noise,   # Tmean = 0.30, PPT = 0.20, SWE = 0.15, d1..d10 = 0
#   n_draws   = 1000L,
#   ci_levels = c(0.50, 0.80, 0.90, 0.95)
# )
# 
# print(pred_A)
# # ErrorTracer prediction (et_prediction)
# #   Observations  : 15
# #   Draws         : 1000
# #   CI levels     : 0.5, 0.8, 0.9, 0.95
# #   Interval type : predictive
# #   Mean var decomposition (across observations):
# #     Parameter    : 0.0040
# #     Environmental: 0.0264  (MC SE: 0.0014)
# #     Residual     : 0.0870
# #     Total        : 0.1174  (measured predictive variance)
# #     Closure gap  : 0.0001  (Monte Carlo; compare MC SE above)

## ----ci-table-----------------------------------------------------------------
# # 90% credible intervals by forecast year
# ci90 <- pred_A$credible_intervals[pred_A$credible_intervals$ci_level == 0.90, ]
# ci90$year <- fcast_A$year
# head(ci90[, c("year", "lower", "median", "upper", "width")])
# #    year      lower     median     upper    width
# # 31 2020 -0.9124320 -0.3710932 0.2328418 1.145274
# # 32 2021 -0.4276259  0.1268306 0.6656614 1.093287
# # 33 2022 -0.7306874 -0.1616093 0.4136616 1.144349
# # 34 2023 -0.2588986  0.2843572 0.8218421 1.080741
# # 35 2024 -0.4706744  0.1134329 0.6489682 1.119643
# # 36 2025 -0.3844870  0.1803172 0.7336616 1.118149

## ----decompose----------------------------------------------------------------
# decomp_A <- decompose_uncertainty(pred_A)
# head(decomp_A)
# #   obs_id total_var param_var env_var v_env_mcse residual_var closure_gap
# # 1      1    0.1241    0.0061  0.0279     0.0054       0.0894      0.0007
# # 2      2    0.1218    0.0049  0.0262     0.0053       0.0894      0.0013
# # ...

## ----plot-decomp, fig.cap="Variance decomposition for cluster A over the 2020-2034 forecast window."----
# et_plot_decomposition(decomp_A, proportional = TRUE)

## ----shelf-life---------------------------------------------------------------
# # Derive response scale from training data (arcsin-sqrt scale — unbounded)
# pr_A <- range(train_A$z_diff)   # c(-1.73, 1.57) => width ~ 3.30
# 
# sl_A <- shelf_life(
#   predictions              = pred_A,
#   response_scale           = pr_A,
#   ci_level                 = 0.90,
#   threshold                = 1.0,        # uninformative when CI width >= response scale
#   time_col                 = "year",
#   min_run                  = 2L,         # require >= 2 consecutive exceedances
#   projection_alpha         = 0.05,       # require significantly positive slope to project
#   min_slope_for_projection = 1e-4,       # minimum slope magnitude to project
#   max_extrapolation_factor = 10          # cap: project <= last_year + 10 * window_width
# )
# 
# print(sl_A)

## ----shelf-life-table---------------------------------------------------------
# head(as.data.frame(sl_A))

## ----plot-shelf-life, fig.cap="Shelf life for cluster A: 90% CI width divided by the training range, on the arcsin-square-root scale."----
# et_plot_shelf_life(sl_A, show_ratio = TRUE)

## ----calibrate----------------------------------------------------------------
# valid_A <- et_sim$validation[et_sim$validation$cluster_id == "A", ]
# 
# cal_A <- et_calibrate(
#   predictions  = pred_A,
#   observed     = valid_A,
#   response_col = "z_diff",
#   ci_levels    = c(0.50, 0.80, 0.90, 0.95)
# )
# 
# print(cal_A)
# #   ci_level nominal observed_coverage n_obs calibration_error
# # 1     0.50    0.50              0.60     5              0.10
# # 2     0.80    0.80              0.80     5              0.00
# # 3     0.90    0.90              1.00     5              0.10
# # 4     0.95    0.95              1.00     5              0.05

## ----plot-calibration, fig.cap="Posterior predictive calibration for cluster A."----
# et_plot_calibration(cal_A)

## ----plot-forecast, fig.cap="Forecast for cluster A. Shaded ribbons are the 50, 80, 90 and 95% credible intervals."----
# et_plot_forecast(
#   predictions  = pred_A,
#   observed     = valid_A,
#   response_col = "z_diff",
#   time_col     = "year"
# )

## ----plot-prior-posterior, fig.cap="How 20 observations update the elastic-net prior, cluster A."----
# et_plot_prior_posterior(fit_A, max_preds = 3L)

## ----plot-coefficients, fig.cap="Bayesian 95% credible intervals (blue) against the elastic-net coefficients (red crosses), cluster A."----
# et_plot_coefficients(fit_A)

## ----parameter-recovery-------------------------------------------------------
# post    <- brms::fixef(fit_A$fit)
# true_A  <- et_sim$true_params$A
# 
# post_df <- data.frame(
#   parameter  = c("Intercept", "Tmean", "PPT", "SWE"),
#   true_value = c(true_A["intercept"], true_A["Tmean"],
#                  true_A["PPT"],       true_A["SWE"]),
#   post_mean  = post[, "Estimate"],
#   lower_95   = post[, "Q2.5"],
#   upper_95   = post[, "Q97.5"]
# )
# post_df$covered <- with(post_df,
#                         true_value >= lower_95 & true_value <= upper_95)
# 
# post_df[, c("parameter", "true_value", "post_mean", "lower_95", "upper_95", "covered")]
# #   parameter true_value post_mean lower_95 upper_95 covered
# # 1 Intercept       0.00     0.041   -0.162    0.246    TRUE
# # 2     Tmean       0.50     0.666    0.438    0.888    TRUE
# # 3       PPT      -0.30    -0.487   -0.909   -0.123    TRUE
# # 4       SWE       0.20     0.406    0.023    0.827    TRUE

## ----grouped-priors-----------------------------------------------------------
# # Build one et_prior_spec per cluster from individual elastic nets
# prior_list <- lapply(c("A", "B"), function(cl) {
#   df <- et_sim$train[et_sim$train$cluster_id == cl, ]
#   x  <- as.matrix(df[, c("Tmean", "PPT", "SWE")])
#   set.seed(42)
#   suppressWarnings(cv <- glmnet::cv.glmnet(x, df$z_diff, alpha = 0.5))
#   extract_priors(cv, multiplier = 2.0, min_sd = 0.10)
# })
# names(prior_list) <- c("A", "B")

## ----grouped-fit--------------------------------------------------------------
# # One brms model per cluster, returned as et_model_list
# fit_all <- et_fit(
#   formula  = z_diff ~ Tmean + PPT + SWE,
#   data     = et_sim$train,
#   priors   = prior_list,       # named list: one et_prior_spec per cluster
#   grouping = "cluster_id",
#   chains   = CHAINS,
#   iter     = ITER,
#   warmup   = ITER %/% 2L,
#   cores    = CHAINS,
#   seed     = SEED
# )
# 
# print(fit_all)
# # ErrorTracer grouped model list (et_model_list)
# #   Grouping : cluster_id
# #   Formula  : z_diff ~ Tmean + PPT + SWE
# #   Groups   : 2
# #   Fitted   : 2 / 2
# 
# summary(fit_all)
# # --- Per-group Rhat max ---
# #   A                     Rhat max = 1.004
# #   B                     Rhat max = 1.007

## ----grouped-diagnose---------------------------------------------------------
# diag_all <- et_diagnose(fit_all, loo = TRUE)
# diag_all$summary
# #   group rhat_ok neff_ok n_divergences elpd_loo n_bad_pareto_k
# # 1     A    TRUE    TRUE             0   -14.55              0
# # 2     B    TRUE    TRUE             0   -17.15              1

## ----grouped-predict----------------------------------------------------------
# pred_all <- et_predict(
#   model     = fit_all,
#   newdata   = et_sim$forecast,
#   env_noise = et_sim$env_noise,
#   n_draws   = 1000L,
#   ci_levels = c(0.50, 0.80, 0.90, 0.95)
# )
# 
# print(pred_all)
# # ErrorTracer grouped predictions (et_prediction_list)
# #   Grouping : cluster_id
# #   Groups   : 2 / 2 predicted

## ----grouped-decompose--------------------------------------------------------
# decomp_all <- decompose_uncertainty(pred_all)
# head(decomp_all)

## ----grouped-shelf-life-------------------------------------------------------
# # Use the pooled training range across both clusters (arcsin-sqrt scale)
# pr_all <- range(et_sim$train$z_diff)   # c(-1.73, 1.57) => width ~ 3.30
# 
# sl_all <- shelf_life(
#   pred_all,
#   response_scale           = pr_all,
#   ci_level                 = 0.90,
#   threshold                = 1.0,
#   time_col                 = "year",
#   max_extrapolation_factor = 10
# )
# 
# print(sl_all)

## ----plot-grouped-shelf-life, fig.cap="Shelf life for both clusters: 90% CI width divided by the plausible range."----
# et_plot_shelf_life(sl_all, show_ratio = TRUE) +
#   labs(
#     colour   = "Cluster"
#   )

## ----grouped-calibrate, fig.cap="Posterior predictive calibration for both clusters."----
# cal_all <- et_calibrate(
#   pred_all,
#   observed     = et_sim$validation,
#   response_col = "z_diff",
#   ci_levels    = c(0.50, 0.80, 0.90, 0.95)
# )
# 
# et_plot_calibration(cal_all)

## ----grouped-coef-plot, fig.cap="Bayesian 95% credible intervals (blue) against the elastic-net coefficients (red crosses), both clusters."----
# # Forest plot for all groups in a single faceted figure
# et_plot_coefficients(fit_all)

## ----gcm-workflow, eval = FALSE-----------------------------------------------
# # Suppose you have GCM ensemble-mean predictors for 2025-2075,
# # standardised using your training-period statistics.
# gcm_years <- 2025:2075
# 
# gcm_df <- data.frame(
#   year  = gcm_years,
#   Tmean = ...,    # standardised GCM ensemble-mean temperature
#   PPT   = ...,    # standardised GCM ensemble-mean precipitation
#   SWE   = ...     # standardised GCM ensemble-mean snowpack
# )
# 
# # GCM ensemble spread (SD across runs) grows roughly linearly with time.
# # Here we model spread as starting at the validation-period noise level
# # and increasing by ~0.01 SD per year for temperature.
# base_year   <- 2025
# tmean_noise <- 0.30 + 0.01 * (gcm_years - base_year)  # 0.30 → 0.80
# ppt_noise   <- 0.20 + 0.005 * (gcm_years - base_year) # 0.20 → 0.45
# swe_noise   <- 0.15 + 0.005 * (gcm_years - base_year) # 0.15 → 0.40
# 
# # Predict over the 50-year GCM window with time-varying noise
# pred_gcm <- et_predict(
#   model     = fit_A,
#   newdata   = gcm_df,
#   env_noise = list(
#     Tmean = tmean_noise,   # per-row vector, length = nrow(gcm_df)
#     PPT   = ppt_noise,
#     SWE   = swe_noise
#   ),
#   ci_levels = c(0.90, 0.95),
#   n_draws   = 1000L
# )
# 
# # Shelf life over the 50-year horizon
# sl_gcm <- shelf_life(
#   pred_gcm,
#   response_scale           = range(train_A$z_diff),
#   time_col                 = "year",
#   max_extrapolation_factor = Inf    # allow projection beyond the 50-yr window
# )
# 
# print(sl_gcm)
# # If the 90% CI stays below the plausible range throughout 2025-2075:
# #   Shelf life : > 2075 (lower bound — all periods informative, no trend)
# # If it crosses (say, around 2058):
# #   Shelf life : ~2058 (observed — threshold first exceeded)

## ----gcm-decompose, eval = FALSE----------------------------------------------
# decomp_gcm <- decompose_uncertainty(pred_gcm)
# # env_var should be small in 2025 and growing toward 2075 as GCM spread
# # accumulates; param_var and residual_var remain roughly constant.
# plot(gcm_years, decomp_gcm$env_var,
#      type = "l", xlab = "Year", ylab = "Environmental variance",
#      main = "Growing GCM ensemble uncertainty propagated into forecast")

## ----lm-priors----------------------------------------------------------------
# lm_fit_A <- lm(z_diff ~ Tmean + PPT + SWE, data = train_A)
# 
# prior_lm_A <- extract_priors(
#   model      = lm_fit_A,
#   multiplier = 2.0,
#   min_sd     = 0.10
# )
# 
# print(prior_lm_A)
# # ErrorTracer prior specification
# #   Method      : lm
# #   Predictors  : 3
# #   Multiplier  : 2
# #   Min SD      : 0.1
# #   Shrinkage   : zero (prior means at 0; regularizing)
# #   Coefficients:
# #     Tmean                 prior mean =   0.0000  sd =   1.0023  (coef =   0.5012)
# #     PPT                   prior mean =   0.0000  sd =   0.5490  (coef =  -0.2745)
# #     SWE                   prior mean =   0.0000  sd =   0.3416  (coef =   0.1708)

## ----back-transform-----------------------------------------------------------
# # Standardisation constants used when generating et_sim
# et_sim$standardization
# # $Tmean
# #      mean        sd
# #  15.74798   1.24258
# #
# # $PPT
# #      mean        sd
# # 108.60625  15.94841
# #
# # $SWE
# #      mean        sd
# #  61.23573  20.64495
# 
# # A Tmean of +1 SD corresponds to:
# unstandardize(z = 1.0,
#               mu = et_sim$standardization$Tmean["mean"],
#               s  = et_sim$standardization$Tmean["sd"])
# # [1] 16.99   ← 1 SD above training mean = 17.0 °C

## ----session-info, eval = TRUE, echo = FALSE----------------------------------
sessionInfo()

