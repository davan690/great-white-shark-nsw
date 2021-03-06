
# parameters --------------------------------------------------------------

# the time resolution of the the corrected tides in hours. For example 1/6 means
# tides will be calculated every (60/6) 10 mins.
resolution_predicted_tides <- 1/4 
# the length of the bins at which data is being aggregated
aggregation_bin <- "1 hour"

# plans -------------------------------------------------------------------

library(drake)
library(dplyr)
library(tools)
library(readr)
library(stringr)
library(TideHarmonics)
library(purrr)

# load functions
functions_folder <- './code'
list_files_with_exts(functions_folder, 'R') %>%
  lapply(source) %>% invisible()

# list raw files with tide data
tide_files <- list_files_with_exts('./data/tides', 'csv')
tide_names <- basename(tide_files) %>% file_path_sans_ext() %>% 
  str_extract("^([A-Z])\\w+")
tide_files <- paste0("'", tide_files, "'")

# make a plan to read the data
tides_read <- drake_plan(
  raw = read_tide(FILE)
) %>%
  evaluate_plan(rules = list(FILE = tide_files), expand = T) %>%
  mutate(target = paste("raw", tide_names, sep = "_"))

# make a plan to fit tide data
tides_fit <- drake_plan(
  model = fit_tide(raw_NAME)
) %>%
  evaluate_plan(rules = list(NAME = tide_names))

# make a plan to compute corrected tide data
tides_pred <- drake_plan(
  fit = predict_tide(model_NAME, raw_NAME, by = resolution_predicted_tides)
) %>%
  evaluate_plan(rules = list(NAME = tide_names))

# plans to gather predictions and metadata

tides_gather_pred <- tides_pred %>%
  gather_plan("predictions", "gather_predictions")

tides_gather_meta <- tides_read %>%
  gather_plan("metadata", "gather_metadata")

# calculate high-low tides & aggregate

processing_tides <- drake_plan(
  hl_tides = high_lows(predictions), 
  aggregated_tides = aggregate_tides(predictions, aggregation_bin)
)

dir.create("./data/processed")

write_data <- drake_plan(
  write_csv(predictions, file_out('./data/processed/predictions.csv')), 
  write_csv(metadata, file_out('./data/processed/metadata.csv')), 
  write_csv(hl_tides, file_out('./data/processed/high_low.csv')),
  write_csv(aggregated_tides, file_out('./data/processed/aggregated_tides.csv')),
  strings_in_dots = "literals"
)

# gather plan
plan <- rbind(tides_read, tides_fit, tides_pred,
              tides_gather_pred, tides_gather_meta, processing_tides,
              write_data)

config <- drake_config(plan)

# run plan
make(plan)

