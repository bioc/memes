% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/meme.R
\name{importMeme}
\alias{importMeme}
\title{Import MEME results}
\usage{
importMeme(meme_txt, parse_genomic_coord = TRUE, combined_sites = FALSE)
}
\arguments{
\item{meme_txt}{path to "meme.txt" output}

\item{parse_genomic_coord}{whether to parse sequence headers into genomic
coordinates for motif position information, only works if fasta files were
written such that the sequence headers are in the form: "chr:start-end", or
some variation of this form (delimiters can be any of: "[^[:alnum:]]+" (ie
non-alphanumeric characters)).}

\item{combined_sites}{whether to add `combined_sites` output which contains coordinates of each sequence, the motif sequence}
}
\value{

}
\description{
Import MEME results
}
\examples{
# If fasta headers do not have sequence information, parse_genomic_coord must be set to FALSE
example_no_sequence <- system.file("extdata/meme_full.txt", package = "universalmotif", mustwork = TRUE)
importMeme(example_no_sequence, parse_genomic_coord = FALSE)

#TODO: Add example of file w/ sequence headers
}