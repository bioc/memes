#' @export
#' @rdname runAme
runAme.list <- function(input,
                        control = "shuffle",
                        outdir = "auto",
                        method = "fisher",
                        database = NULL,
                        meme_path = NULL,
                        sequences = FALSE,
                        silent = TRUE, ...){
  
  x <- sequence_input_control_list(input, control)
  input <- x$input
  control <- x$control

  res <- purrr::map(input, runAme.default,
             control = control,
             outdir = outdir,
             method = method,
             database = database,
             meme_path = meme_path,
             sequences = sequences,
             silent = silent,
             ...
             )
  return(res)
}

#' @export
#' @rdname runAme
runAme.BStringSetList <- function(input,
                        control = "shuffle",
                        outdir = "auto",
                        method = "fisher",
                        database = NULL,
                        meme_path = NULL,
                        sequences = FALSE,
                        silent = TRUE, ...){
  runAme.list(as.list(input), control, outdir, method, database, meme_path, sequences, silent, ...)
}

#' @export
#' @rdname runAme
runAme.default <- function(input,
       control = "shuffle",
       outdir = "auto",
       method = "fisher",
       database = NULL,
       meme_path = NULL,
       sequences = FALSE, silent = TRUE, ...){

  input <- sequence_input(input)

  if (!all(is.na(control))){
    control <- sequence_input(control)
  }

  # Autodetect outdir path from path names
  # note: this line must run after input&control are parsed to paths
  if (outdir == "auto") {outdir <- outdir_name(input, control)}

  user_flags <- prepareAmeFlags(control, outdir, method, ...)
  database <- search_meme_database_path(database)
  command <- search_meme_path(path = meme_path, util = "ame")

  # format: ame <flags> <input.fa> <db.meme>
  flags <- c(user_flags, input, database)

  ps_out <- processx::run(command, flags, spinner = TRUE, error_on_status = FALSE)

  # Handles printing argument suggestions if process has non-zero exit status
  # help_fun must be anonymous function to delay evaluating ame_help unless it's needed
  ps_out %>%
    process_check_error(help_fun = ~{ame_help(command)},
                        user_flags = cmdfun::cmd_help_parse_flags(user_flags) %>%
                          grep("shuffle", ., invert = TRUE, value = TRUE),
                        flags_fun = ~{gsub("-", "_", .x)},
                        default_help_fun = TRUE)

  print_process_stdout(ps_out, silent = silent)
  print_process_stderr(ps_out, silent = silent)

  # NOTE: sequences.tsv is only created when method == "fisher"
  ame_out <- cmdfun::cmd_file_combn("ame", c("tsv", "html"), outdir)
  if (method == "fisher"){
    ame_seq <- cmdfun::cmd_file_combn("sequences", "tsv", outdir)
    ame_out$sequences <- ame_seq[[1]]
  }

  ame_out %>%
    cmdfun::cmd_error_if_missing()

  import_sequences <- FALSE
  if (method == "fisher" & sequences){
    import_sequences <- ame_out$sequences
  }

  importAme(path = ame_out$tsv, method = method, sequences = import_sequences)
}

#' Returns ame help lines
#'
#' @param command path to ame. output of search_meme_path(util = "ame")
#'
#' @return
#'
#' @noRd
ame_help <- function(command){
  processx::run(command, "--help", error_on_status = FALSE)$stderr
}

prepareAmeFlags <- function(control, outdir, method, ...){

  argsDict <- c("outdir" = "oc")

  flagList <- cmdfun::cmd_args_all() %>%
    cmdfun::cmd_list_interp(argsDict) %>%
    purrr::set_names(~{gsub("_", "-", .x)})

  if (exists("control", flagList)) {
    if (flagList$control == "shuffle") {
      flagList$control <- "--shuffle--"
    }
  }

  if (exists("bfile", flagList)) {
    if (flagList$control %in% c("motif", "uniform")) {
      flagList$control <- paste0("--", flagList$control, "--")
    }
  }

  flagList %>%
    cmdfun::cmd_list_to_flags(prefix = "--")
}

#' Parse AME output
#'
#' This imports AME results using the "ame.tsv" output, and optionally the
#' "sequences.tsv" output if run with "method = fisher". AME results differ
#' based on the method used, thus this must be set on import or the column
#' names will be incorrect.
#'
#' @param path path to ame results file ("ame.tsv")
#' @param method ame run method used (one of: c("fisher", "ranksum", "dmhg3",
#'   "dmhg4", "pearson", "spearman")). Default: "fisher".
#' @param sequences NULL/FALSE to skip sequence import, or path to sequences
#'   file to import (only valid for method = "fisher")
#'
#' @return data.frame with method-specific results. See [AME
#'   results](http://meme-suite.org/doc/ame-output-format.html) webpage for more
#'   information. If sequences is set to a path to the sequences.tsv and method
#'   = "fisher", the list-column `sequences` will be appended to resulting
#'   data.frame.
#'
#' @seealso [runAme()]
#'
#' @importFrom magrittr %<>%
#' @importFrom tidyr nest
#' @importFrom rlang .data
#' @export
#'
#' @family import
#'
#' @examples
#' ame_tsv <- system.file("extdata", "ame.tsv", package = "memes", mustWork = TRUE)
#' importAme(ame_tsv)
importAme <- function(path, method = c("fisher", "ranksum", "dmhg3", "dmhg4", "pearson", "spearman"), sequences = NULL) {
  method <- match.arg(method)
  has_sequences <- is.character(sequences)
  cols <- get_ame_coltypes(method)

  data <- readr::read_tsv(path,
                          col_names = names(cols$cols),
                          col_types = cols,
                          skip = 1,
                          comment = "#"
                          )

  if (nrow(data) == 0){
    message("AME detected no enrichment")
    return(NULL)
  }

  if (has_sequences && method != "fisher") {
    msg <- "`sequences` argument is invalid unless method = 'fisher'."
    stop(msg, call. = FALSE)
  }
  if (!has_sequences || method != "fisher") {
    return(data)
  }

  if (has_sequences && method == "fisher") {
    seq <- importAmeSequences(sequences)

    if (is.null(seq)){
      return(data)
    }

    seq %<>%
      dplyr::group_by(.data$motif_id, .data$motif_db) %>%
      tidyr::nest() %>%
      dplyr::rename("sequences" = "data") %>%
      data.frame

    return(dplyr::left_join(data, seq, by = c("motif_id","motif_db")))
  }

}

#' Helper for combining readr::cols() objects
#'
#' @param col readr::cols() object
#' @param cols_list list of readr::cols() objects. **NOTE** order MATTERS!
#'
#' @return combined cols() object of all inputs
#' @noRd
combine_cols <- function(col, cols_list){
    # original cols to col
    # pass extra cols to cols as list

    out <- col

    purrr::walk(cols_list, ~{
      out$cols <<- c(out$cols, .x$cols)
    })
    return(out)
}

#' Import AME sequences information for method="fisher" runs.
#'
#' @param path path to sequences.tsv ame output file
#'
#' @return data.frame with columns:
#'  - motif_db: name of motif db the identified motif was found in
#'  - motif_id: name of identified motif (primary identifier)
#'  - seq_id (name of fasta entry)
#'  - label_[fasta|pwm]_score: score used for labeling positive (either fasta or pwm score)
#'  - class_[fasta|pwm]_score: score used for classifying positives (either fasta or pwm score)
#'  - class: whether a sequence was called true-positve ("tp") or false-positive ("fp")
#'
#' @importFrom magrittr %<>%
#'
#' @examples
#' \donttest{
#' importAmeSequences("path/to/ame/sequences.tsv")
#' }
#'
#' @noRd
importAmeSequences <- function(path){

  sequences <- readr::read_tsv(path,
                               col_types = readr::cols("c", "c", "c", "d", "d", "c"),
                               col_names = TRUE,
                               comment = "#")
  if (nrow(sequences) == 0){
    message("Sequences output is empty")
    return(NULL)
  }

  sequences %<>%
    dplyr::rename_all(tolower) %>%
    # positions 4 & 5 encode which score was used to "label" (4) vs "classify" (5)
    # can be either PWM for Fasta score, and can't predict which one easily, so
    # just prefix these two.
    dplyr::rename_at(4, function(x){paste0("label_", x)}) %>%
    dplyr::rename_at(5, function(x){paste0("class_", x)})

}

#' Generate columntypes/names for ame results.
#'
#' @param method ame run method used (one of: c("fisher", "ranksum", "dmhg3",
#'   "dmhg4", "pearson", "spearman")).
#'
#' @return readr::cols object w/ names & datatypes for given method
#' @importFrom readr cols
#'
#' @noRd
get_ame_coltypes <- function(method){
  # Strategey: build readr::cols() vector for each input type, the combine together using switch for import.

  cols_common <- readr::cols("rank" = "i",
                             "motif_db" = "c",
                             "motif_id" = "c",
                             "motif_alt_id" = "c",
                             "consensus" = "c",
                             "pvalue" = "d",
                             "adj.pvalue" = "d",
                             "evalue" = "d",
                             "tests" = "i"
                             )

  cols_fisher_ranksum_dmhg <- readr::cols("fasta_max" = "d",
                                          "pos" = "i",
                                          "neg" = "i"
                                          )
  cols_fisher <- readr::cols("pwm_min" = "d",
                             "tp" = "i",
                             "tp_percent" = "d",
                             "fp" = "i",
                             "fp_percent" = "d"
                             )

  cols_ranksum <- readr::cols("u" = "d",
                              "pleft" = "d",
                              "pright" = "d",
                              "pboth" = "d",
                              "adj.pleft" = "d",
                              "adj.pright" = "d",
                              "adj.both" = "d"
                              )

  cols_pearson <- readr::cols("pearson_cc" = "d",
                              "mean_squared_error" = "d",
                              "slope" = "d",
                              "intercept" = "d"
                              )

  cols_spearman <- readr::cols("spearman_cc" = "d")

  method <- gsub("[3,4]dmhg", "dmhg", method)
  cols <- switch(method,
         fisher = combine_cols(cols_common, list(cols_fisher_ranksum_dmhg, cols_fisher)),
         ranksum = combine_cols(cols_common, list(cols_fisher_ranksum_dmhg, cols_ranksum)),
         dmhg = combine_cols(cols_common, list(cols_fisher_ranksum_dmhg)),
         pearson = combine_cols(cols_common, list(cols_pearson)),
         spearman = combine_cols(cols_common, list(cols_spearman)),
         stop(paste0(method, " is not a valid method"))
         )

  return(cols)

}
