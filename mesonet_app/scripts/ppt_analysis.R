library(magrittr)

arrange_ppt_data <- function() {
  "./data/new_error_analysis.csv" %>%
    readr::read_csv(col_types = readr::cols()) %>%
    dplyr::filter(
      date <= lubridate::as_date("2018-07-25"), # for some reason mesonet data is missing on the 26th of July
      variable == "ppt",
      !is.na(floor_value),
      lubridate::month(date) >= 4 & lubridate::month(date) <= 10
    ) %>%
    dplyr::mutate(
      mes_value = dplyr::if_else(
        dataset == "gridmet",
        floor_value,
        ceiling_value
      ),
      bias = dplyr::if_else(
        dataset == "gridmet",
        floor_diff,
        ceiling_diff
      ),
      mes_ppt = dplyr::if_else(
        mes_value == 0,
        0, 1
      ),
      grd_ppt = dplyr::if_else(
        value == 0,
        0, 1
      ),
      grd_correct = dplyr::if_else(
        mes_ppt == grd_ppt,
        1, 0
      )
    ) %>%
    calc_mae() %>%
    dplyr::select(-floor_value, -ceiling_value, -floor_diff, -ceiling_diff) %>%
    dplyr::group_by(date, dataset) %>%
    dplyr::mutate(percent_correct = sum(grd_correct) / dplyr::n()) %>%
    dplyr::ungroup()
}

binary_plot <- function() {
  library(ggplot2)

  arrange_ppt_data() %>%
    dplyr::filter(
      !is.na(mes_value),
      dataset != "mesonet_ceiling" & dataset != "mesonet_floor"
    ) %>%
    dplyr::select(date, dataset, percent_correct) %>%
    dplyr::mutate(percent_correct = percent_correct * 100) %>%
    dplyr::distinct() %>%
    ggplot(aes(x = percent_correct, color = dataset)) +
    stat_ecdf(size = 1) +
    viz_ppt() +
    labs(
      x = "Percent Correct", y = "Density", color = "Dataset",
      title = "Distribution of Accuracy of Gridded Datasets Relative to Mesonet"
    )
}


# mes_tf = T or F
ppt_den_plot <- function(mes_tf) {
  library(ggplot2)

  if (mes_tf) {
    val1 <- -20
    val2 <- 20
  } else {
    val1 <- 0
    val2 <- 10
  }

  if (mes_tf) {
    word <- "Recorded Precipitation"
  } else {
    word <- "Didn't Record Precipitation"
  }

  p_title <- paste("Distribution of Bias on Days Mesonet", word)

  arrange_ppt_data() %>%
    dplyr::filter(
      !is.na(mes_value),
      mes_ppt == mes_tf,
      dataset != "mesonet_ceiling" & dataset != "mesonet_floor"
    ) %>%
    dplyr::mutate(ppt_bin = dplyr::ntile(bias, 100)) %>%
    ggplot(aes(x = bias, color = dataset)) +
    geom_density(size = 1) +
    viz_ppt() +
    xlim(val1, val2) +
    labs(
      x = "Median Bias", y = "Density",
      color = "Dataset", title = p_title
    )
}

bias_time_plot <- function(dataset1, dataset2) {
  library(ggplot2)

  plot_title <- paste(dataset1, "and", dataset2, "Bias Across Non-Winter Months") %>%
    tools::toTitleCase()

  arrange_ppt_data() %>%
    dplyr::filter(dataset == dataset1 | dataset == dataset2) %>%
    dplyr::filter(date <= lowest_date(.)) %>%
    dplyr::filter(!is.na(mes_value)) %>%
    dplyr::group_by(date, dataset) %>%
    dplyr::mutate(
      median = median(bias),
      bias25 = quantile(bias, .25),
      bias75 = quantile(bias, .75)
    ) %>%
    ggplot(aes(x = date, y = median, color = dataset)) +
    geom_line(size = 1) +
    geom_ribbon(aes(ymin = bias25, ymax = bias75), linetype = 1, alpha = 0.2) +
    viz_ppt() +
    labs(x = "Date", y = "Bias (mm)", title = plot_title)
}

mae_time_plot <- function(dataset1, dataset2) {
  library(ggplot2)

  plot_title <- paste(dataset1, "and", dataset2, "Absolute Error Across Non-Winter Months") %>%
    tools::toTitleCase()

  arrange_ppt_data() %>%
    dplyr::select(date, dataset, mae, mae25, mae75) %>%
    dplyr::distinct() %>%
    dplyr::filter(dataset == dataset1 | dataset == dataset2) %>%
    dplyr::filter(date <= lowest_date(.)) %>%
    ggplot(aes(x = date, y = mae, color = dataset)) +
    geom_line(size = 1) +
    geom_ribbon(aes(ymin = mae25, ymax = mae75), linetype = 1, alpha = 0.2) +
    viz_ppt() +
    labs(x = "Date", y = "Absolute Error (mm)", color = "Dataset", title = plot_title)
}

intensity_plot <- function() {

  library(ggplot2)

  # this is a logged sequence of values to (hopefully) capture the whole
  # range of variability in precip
  bins <- c(
    -0.0000001, 1, 1.630689, 2.659148, 4.336244,
    7.071068, 11.530715, 18.803015, 30.661878, 50.000000
  )
  bins2 <- seq(0, 50, 2)

  arrange_ppt_data() %>%
    dplyr::filter(
      !is.na(mes_value),
      dataset != "mesonet_floor" &
        dataset != "mesonet_ceiling",
      mes_value <= 50
    ) %>% # filter out values higher than 50 to get rid of anomalies
    dplyr::group_by(dataset) %>%
    dplyr::mutate(binned = dplyr::ntile(mes_value, 30)) %>%
    # dplyr::mutate(binned = cut(mes_value, bins2, include.lowest = T)) %>%
    dplyr::ungroup() %>%
    dplyr::group_by(dataset, binned) %>%
    dplyr::summarize(
      real_ppt = mean(mes_value),
      mod_ppt = mean(bias)
    ) %>%
    ggplot(aes(x = real_ppt, y = mod_ppt, color = dataset)) +
    geom_line(size = .5) +
    viz_ppt() +
    labs(
      x = "Recorded Mesonet Precipitation (mm)",
      y = "Dataset Bias (mm)",
      color = "Dataset",
      title = "Recorded Mesonet Precipitation vs Gridded ppt Bias"
    )
}

# type = "ab" or "bias"
ppt_boxes <- function(dataset1, dataset2, type, test) {
  if (type == "ab") {
    plot_title <- "Median, 5th, and 95th Percentile of\nAbsolute Error Across Timeseries"
    ylab <- "Mean Absolute Error (mm)"
  } else {
    plot_title <- "Median, 5th, and 95th Percentile of\nBias Across Timeseries"
    ylab <- "Mean Bias (mm)"
  }


  dat <- arrange_ppt_data() %>%
    dplyr::filter(dataset == dataset1 | dataset == dataset2)

  test_fun <- switch(test,
    "t" = match.fun("t.test"),
    "ks" = match.fun("ks.test"),
    "mw" = match.fun("wilcox.test")
  )

  p_result <- dat %>%
    split(.$dataset) %>%
    {
      test_fun(.[[1]][[type]], .[[2]][[type]])
    } %>%
    {
      .$p.value
    }

  type <- rlang::sym(type)

  dat %>%
    dplyr::select(date, dataset, !!type) %>%
    dplyr::group_by(dataset) %>%
    dplyr::summarise(
      med = mean(!!type),
      fifth = quantile(!!type, .05),
      ninetyfifth = quantile(!!type, .95)
    ) %>%
    ggplot(aes(x = dataset, y = med, color = dataset)) +
    geom_errorbar(aes(ymin = fifth, ymax = ninetyfifth), width = 0.3, size = 1) +
    geom_point(size = 2) +
    viz_ppt() +
    labs(
      x = "Dataset", y = ylab,
      title = plot_title,
      subtitle = paste(
        "P-Value of ", formatC(p_result, format = "e", digits = 3),
        "Between Datasets"
      )
    ) +
    theme(legend.position = "none")
}


lowest_date <- function(dat) {
  dat %>%
    dplyr::group_by(dataset) %>%
    dplyr::summarise(max_date = max(date)) %>%
    {
      min(.$max_date)
    }
}

viz_ppt <- function() {
  myColors <- c("#E9724C", "#6d976d", "#255F85", "#F9DBBD")
  names(myColors) <- c("prism", "daymet", "gridmet", "chirps")

  return(list(
    scale_colour_manual(values = myColors),

    theme_minimal(),

    theme(
      plot.title = element_text(hjust = 0.5, colour = "gray15", face = "bold"),
      plot.subtitle = element_text(hjust = 0.5, colour = "gray20", face = "bold"),
      axis.title.x = element_text(colour = "gray26", face = "bold"),
      axis.title.y = element_text(colour = "gray26", face = "bold"),
      legend.title = element_text(
        hjust = 0.5, colour = "gray15", face = "bold",
        size = 10
      ),
      legend.text = element_text(colour = "gray26", face = "bold", size = 10),
      plot.margin = unit(c(1, 1, 1, 1), "cm")
    )
  ))
}

calc_mae <- function(dat) {
  dat %>%
    dplyr::filter(!is.na(bias)) %>%
    dplyr::mutate(ab = abs(bias)) %>%
    dplyr::group_by(date, dataset) %>%
    dplyr::mutate(
      mae = median(ab),
      mae25 = quantile(ab, 0.25),
      mae75 = quantile(ab, 0.75)
    ) %>%
    dplyr::ungroup()
}

## temperature density plot


## x axis precip, y axis bias
## same with temperature - daily temperature range
