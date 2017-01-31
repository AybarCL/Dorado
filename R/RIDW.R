#' Regression IDW Optimizing inverse distance weighting power
#' @author Cesar Aybar <aybar1994@gmail.com>
#' @description This function use gstat packages for interpolate spatial point data (see \code{\link[sp]{SpatialPointsDataFrame}} )
#' and RasterLayer data  (see \code{\link[raster]})
#' @seealso \link[gstat]{idw}
#' @param gauge Is an object of SpatialPointsDataFrame class.
#' @param newdata Is An object of RasterLayer.
#' @param idpR Is vector numeric of the power coeficient to evaluate.
#' @param formula that defines the dependent variable as a linear model
#' of independent variables; suppose the dependent variable has
#' name 'z', for Regression Inverse Distance Weigthing (RIDW) use the formula
#' 'z~x+y+....', you do not need define
#' @details R_IDW use crossvalidation Leave-p-out cross-validation (LpO CV) and force brute (optimize MSE)
#'  for estimate the best idp power coeficient.
#' @return a List that contains: \code{Interpol} is the RIDW result in Raster,
#'  \code{params} being \code{bestp} is the best distance weighting power,
#'  \code{MSE} is the Residual Mean squared error of the residuals and
#'   finally \code{linear_Model} is  the adjusted linear Model.
#' @examples
#'  library(raster)
#'  data(Titicaca)
#'  x <- RIDW(gauge = Titicaca$rain,cov = stack(Titicaca$cov),formula = rain~prec+dem)
#'  plot(x$Interpol)
#' @importFrom automap autofitVariogram
#' @importFrom raster extract projection writeRaster
#' @importFrom sp coordinates
#' @importFrom gstat krige.cv idw
#' @export
#'
RIDW <- function(gauge, cov, formula, idpR = seq(0.8, 3.5, 0.1)) {
  ext <- raster::extract(cov, gauge, cellnumber = F, sp = T)
  station <- gauge
  linear <- na.omit(ext@data) %>% tbl_df %>% mutate_all(as.character) %>%
    mutate_all(as.numeric)
  names <- colnames(linear)
  lapply(1:ncol(linear), function(i) assign(names[i], linear[[i]], envir = .GlobalEnv))
  llm <- lm(formula)
  station$residuals <- llm$residuals

  # Define Grid -------------------------------------------------------------

  point <- rasterToPoints(cov) %>% data.frame
  coordinates(point) <- ~x + y
  projection(point) <- projection(cov)

  # Estimate Best Parameter -------------------------------------------------

  idpRange <- idpR
  mse <- rep(NA, length(idpRange))
  for (i in 1:length(idpRange)) {
    mse[i] <- mean(krige.cv(residuals ~ 1, station, nfold = nrow(station),
                            nmax = Inf, set = list(idp = idpRange[i]), verbose = F)$residual^2)
  }
  poss <- which(mse %in% min(mse))
  bestparam <- idpRange[poss]
  residual.best <- krige.cv(residuals ~ 1, station, nfold = nrow(station),
                            nmax = Inf, set = list(idp = idpRange[poss]), verbose = F)$residual

  # Interpolation ----------------------------------------------------------

  idwError <- idw(residuals ~ 1, station, point, idp = bestparam)
  idwError <- idwError["var1.pred"]
  gridded(idwError) <- TRUE
  mapa <- raster(idwError)
  namesF <- unlist(strsplit(as.character(formula), " "))
  max_k <- floor(length(namesF)/2) + 1
  name_cov = namesF[!namesF %in% c("~", "+", "-", "*", "/")][2:max_k]
  cov <- cov[[name_cov]]

  OBSp <- sum(stack(mapply(function(i) cov[[i]] * llm$coefficients[i + 1],
                           1:nlayers(cov)))) + llm$coefficients[1]
  Ridw <- OBSp + mapa
  Ridw[Ridw < 0] <- 0
  # Save Data ---------------------------------------------------------------
  list(Interpol = Ridw, params = list(bestp = bestparam, MSE = mean(residual.best^2),
                                      linear_Model = llm))
}