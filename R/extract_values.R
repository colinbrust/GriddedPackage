# rasters is the list of rasters from the makeImages function

# this function takes a list of rasters, extracts their values to points,
# and returns a list of data frames

extract_values <- function(rastList, ptFile) {

  # library(raster)
  # library(tibble)
   library(magrittr)
  # library(stringr)
  # library(sf)
  # library(velox)

  # A function that uses a grid of points to extract values from an underlying
  # raster image.
  pt_extract <- function(rastImg) {


    sourceName <- stringr::str_replace(basename(raster::filename(rastImg)), ".tif","")

    reproj <- sf::st_transform(ptFile, raster::projection(rastImg))

    vx <- velox::velox(rastImg)

    print(paste(sourceName, "is processing."))

    vx$extract_points(sp = reproj) %>%
      tibble::as_tibble() %>%
      magrittr::set_colnames(c(sourceName))

  }

  lapply(rastList,pt_extract)


}
