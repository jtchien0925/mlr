getLearnerTable = function() {
  ids = as.character(methods("makeRLearner"))
  ids = ids[!stri_detect_fixed(ids, "__mlrmocklearners__")]
  ids = stri_replace_first_fixed(ids, "makeRLearner.", "")
  slots = c("cl", "name", "short.name", "package", "properties", "note")
  ee = asNamespace("mlr")
  tab = rbindlist(lapply(ids, function(id) {
    fun = getS3method("makeRLearner", id)
    row = lapply(as.list(functionBody(fun)[[2L]])[slots], eval, envir = ee)
    data.table(
      id = row$cl,
      name = row$name,
      short.name = row$short.name,
      package = list(stri_replace_first_regex(row$package, "^[!_]", "")),
      properties = list(row$properties),
      note = row$note %??% ""
    )
  }))

  # set learner type (classif, regr, surv, ...)
  tab$type = vcapply(stri_split_fixed(tab$id, ".", n = 2L), head, 1L)

  # check if all requirements are installed
  pkgs = unique(unlist(tab$package))
  pkgs = pkgs[vlapply(pkgs, function(x) length(find.package(x, quiet = TRUE)) > 0L)]
  tab$installed = vlapply(tab$package, function(x) all(x %in% pkgs))

  return(tab)
}

filterLearnerTable = function(tab = getLearnerTable(), types = character(0L), properties = character(0L), check.packages = TRUE) {
  contains = function(lhs, rhs) all(lhs %in% rhs)

  if (check.packages)
    tab = tab[tab$installed]

  if (length(types) > 0L && !isScalarNA(types))
    tab = tab[tab$type %in% types]

  if (length(properties) > 0L) {
    i = vlapply(tab$properties, contains, lhs = properties)
    tab = tab[i]
  }

  return(tab)
}

#' @title Find matching learning algorithms.
#'
#' @description
#' Returns learning algorithms which have specific characteristics, e.g.
#' whether they support missing values, case weights, etc.
#'
#' Note that the packages of all learners are loaded during the search if you create them.
#' This can be a lot. If you do not create them we only inspect properties of the S3 classes.
#' This will be a lot faster.
#'
#' Note that for general cost-sensitive learning, mlr currently supports mainly
#' \dQuote{wrapper} approaches like \code{\link{CostSensWeightedPairsWrapper}},
#' which are not listed, as they are not basic R learning algorithms.
#' The same applies for many multilabel methods, see, e.g., \code{\link{makeMultilabelBinaryRelevanceWrapper}}.
#'
#' @template arg_task_or_type
#' @param properties [\code{character}]\cr
#'   Set of required properties to filter for. Default is \code{character(0)}.
#' @param quiet [\code{logical(1)}]\cr
#'   Construct learners quietly to check their properties, shows no package startup messages.
#'   Turn off if you suspect errors.
#'   Default is \code{TRUE}.
#' @param warn.missing.packages [\code{logical(1)}]\cr
#'   If some learner cannot be constructed because its package is missing,
#'   should a warning be shown?
#'   Default is \code{TRUE}.
#' @param check.packages [\code{logical(1)}]\cr
#'   Check if required packages are installed. Calls
#'   \code{find.package()}. If \code{create} is \code{TRUE}, this is done implicitly and the value of this parameter is ignored.
#'   If \code{create} is \code{FALSE} and \code{check.packages} is \code{TRUE} the returned table only contains learners whose dependencies are installed.
#'   Default is \code{TRUE}. If set to \code{FALSE}, learners that cannot
#'   actually be constructed because of missing packages may be returned.
#' @param create [\code{logical(1)}]\cr
#'   Instantiate objects (or return info table)?
#'   Packages are loaded if and only if this option is \code{TRUE}.
#'   Default is \code{FALSE}.
#' @return [\code{data.frame} | \code{list} of \code{\link{Learner}}].
#'   Either a descriptive data.frame that allows access to all properties of the learners
#'   or a list of created learner objects (named by ids of listed learners).
#' @examples
#' \dontrun{
#' listLearners("classif", properties = c("multiclass", "prob"))
#' data = iris
#' task = makeClassifTask(data = data, target = "Species")
#' listLearners(task)
#' }
#' @export
listLearners  = function(obj = NA_character_, properties = character(0L),
  quiet = TRUE, warn.missing.packages = TRUE, check.packages = TRUE, create = FALSE) {

  assertSubset(properties, getSupportedLearnerProperties())
  assertFlag(quiet)
  assertFlag(warn.missing.packages)
  assertFlag(check.packages)
  assertFlag(create)
  UseMethod("listLearners")
}


#' @export
#' @rdname listLearners
listLearners.default  = function(obj = NA_character_, properties = character(0L),
  quiet = TRUE, warn.missing.packages = TRUE, check.packages = TRUE, create = FALSE) {

  listLearners.character(obj = NA_character_, properties, quiet, warn.missing.packages, check.packages, create)
}

#' @export
#' @rdname listLearners
listLearners.character  = function(obj = NA_character_, properties = character(0L), quiet = TRUE, warn.missing.packages = TRUE, check.packages = TRUE, create = FALSE) {
  if (!isScalarNA(obj))
    assertSubset(obj, getSupportedTaskTypes())
  tab = getLearnerTable()

  if (warn.missing.packages && !all(tab$installed))
    warningf("The following learners could not be constructed, probably because their packages are not installed:\n%s\nCheck ?learners to see which packages you need or install mlr with all suggestions.", collapse(tab[!tab$installed]$id))

  tab = filterLearnerTable(tab, types = obj, properties = properties, check.packages = check.packages && !create)

  if (create)
    return(lapply(tab$id[tab$installed], makeLearner))

  tab$package = vcapply(tab$package, collapse)
  properties = getSupportedLearnerProperties()
  tab = cbind(tab, rbindlist(lapply(tab$properties, function(x) setNames(as.list(properties %in% x), properties))))
  tab$properties = NULL
  setnames(tab, "id", "class")
  setDF(tab)
  addClasses(tab, "ListLearners")
}

#' @export
#' @rdname listLearners
listLearners.Task = function(obj = NA_character_, properties = character(0L),
  quiet = TRUE, warn.missing.packages = TRUE, check.packages = TRUE, create = FALSE) {

  task = obj
  td = getTaskDescription(task)

  props = character(0L)
  if (td$n.feat["numerics"] > 0L) props = c(props, "numerics")
  if (td$n.feat["factors"] > 0L) props = c(props, "factors")
  if (td$n.feat["ordered"] > 0L) props = c(props, "ordered")
  if (td$has.missings) props = c(props, "missings")
  if (td$type == "classif") {
    if (length(td$class.levels) == 1L) props = c(props, "oneclass")
    if (length(td$class.levels) == 2L) props = c(props, "twoclass")
    if (length(td$class.levels) >= 3L) props = c(props, "multiclass")
  }

  listLearners.character(td$type, union(props, properties), quiet, warn.missing.packages, check.packages, create)
}

#' @export
print.ListLearners = function(x, ...) {
  printHead(as.data.frame(dropNamed(x, drop = "note")), ...)
}
