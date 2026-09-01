.DEFAULT_GOAL := test

.PHONY: prepare test simulate draft app

prepare:
	Rscript scripts/prepare.R

test:
	Rscript tests/smoke.R

simulate:
	Rscript scripts/simulate.R

draft:
	Rscript scripts/draft.R

app:
	Rscript -e 'shiny::runApp(".")'
