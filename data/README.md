# Local report data

Place `safemaster_r19_text.rds` here for production analysis. It must contain the 2013–2024 r19 report data as an R data frame, with every column read as character, duplicate column names made unique and dictionary-defined unknown codes converted to `NA`.

Obtain source reports from JCQHC's Project to Collect Medical Near-Miss/Adverse Event Information public database. Reports and a database-export converter are not included. See the repository README for schema assumptions and the additional review inputs required for final analysis. Data files in this directory are ignored by Git.
